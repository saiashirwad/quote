import AppKit
@preconcurrency import ApplicationServices
import Carbon
import Foundation

enum Notes {
    static func resolvedPath() -> String {
        if let env = ProcessInfo.processInfo.environment["QUOTE_FILE"], !env.isEmpty {
            return NSString(string: env).expandingTildeInPath
        }
        return NSString(string: "~/notes/quote.md").expandingTildeInPath
    }

    static func entry(quote: String?, note: String) -> String? {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let quoteText = quote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasQuote = !quoteText.isEmpty
        let hasNote = !trimmedNote.isEmpty
        guard hasQuote || hasNote else { return nil }
        var parts: [String] = []
        if hasQuote {
            parts.append(quoteText.split(separator: "\n", omittingEmptySubsequences: false).map { $0.isEmpty ? ">" : "> \($0)" }.joined(separator: "\n"))
        }
        if hasNote {
            if hasQuote { parts.append("") }
            parts.append(trimmedNote)
        }
        parts.append("")
        parts.append("---")
        parts.append("")
        return parts.joined(separator: "\n")
    }

    static func append(_ entry: String, to existing: String) -> String {
        guard !entry.isEmpty else { return existing }
        if existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return entry }
        var result = existing
        if !result.hasSuffix("\n") { result += "\n" }
        return result + entry
    }
}

private nonisolated(unsafe) var hotKeyActions: [UInt32: @MainActor () -> Void] = [:]

@MainActor
private func registerHotKey(keyCode: UInt32, modifiers: UInt32, id: UInt32, label: String, action: @escaping @MainActor () -> Void) {
    hotKeyActions[id] = action
    var ref: EventHotKeyRef?
    let hkID = EventHotKeyID(signature: OSType(0x5154_4555), id: id)
    let status = RegisterEventHotKey(keyCode, modifiers, hkID, GetApplicationEventTarget(), 0, &ref)
    if status != noErr {
        fputs("quote: failed to register \(label) (status \(status)) — another app (e.g. Sendpoint) probably owns it\n", stderr)
    }
}

private func installHotKeyHandler() {
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    let callback: EventHandlerUPP = { _, event, _ -> OSStatus in
        var hotKeyID = EventHotKeyID()
        guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID) == noErr else {
            return OSStatus(eventNotHandledErr)
        }
        MainActor.assumeIsolated { hotKeyActions[hotKeyID.id]?() }
        return noErr
    }
    var handlerRef: EventHandlerRef?
    InstallEventHandler(GetApplicationEventTarget(), callback, 1, &spec, nil, &handlerRef)
}

private func axValue(_ el: AXUIElement, _ attr: CFString) -> CFTypeRef? {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, attr, &v) == .success else { return nil }
    return v
}

func selectedText(of app: NSRunningApplication?) -> String? {
    guard AXIsProcessTrusted(), let app else { return nil }
    let pid = app.processIdentifier
    guard pid != ProcessInfo.processInfo.processIdentifier else { return nil }
    let appEl = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(appEl, 0.25)
    _ = AXUIElementSetAttributeValue(appEl, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    guard let focusedRef = axValue(appEl, kAXFocusedUIElementAttribute as CFString) else { return nil }
    let focused = unsafeDowncast(focusedRef as AnyObject, to: AXUIElement.self)
    guard let text = axValue(focused, kAXSelectedTextAttribute as CFString) as? String else { return nil }
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return text
}

final class KeyablePanel: NSPanel { override var canBecomeKey: Bool { true } }

final class NoteTextView: NSTextView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty else { return }
        let font = self.font ?? .systemFont(ofSize: 15)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.placeholderTextColor]
        let inset = textContainerInset
        let rect = NSRect(x: inset.width + 5, y: inset.height, width: bounds.width - inset.width * 2 - 10, height: bounds.height - inset.height * 2)
        "Note".draw(with: rect, options: .usesLineFragmentOrigin, attributes: attrs)
    }
    override func didChangeText() { super.didChangeText(); needsDisplay = true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    struct Draft { var quote: String?; var previousApp: NSRunningApplication?; var changeCount: Int }

    private let notesPath = Notes.resolvedPath()
    private var consumedChangeCount = NSPasteboard.general.changeCount
    private var draft: Draft?
    private let panel: KeyablePanel
    private let quoteLabel = NSTextField(labelWithString: "")
    private let textView = NoteTextView()
    private static let boxW: CGFloat = 520
    private static let pad: CGFloat = 16
    private static let contentW = boxW - pad * 2

    override init() {
        panel = KeyablePanel(contentRect: NSRect(x: 0, y: 0, width: Self.boxW, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        super.init()
        panel.delegate = self
        buildUI()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildMenus()
        installHotKeyHandler()
        registerHotKey(keyCode: 5, modifiers: UInt32(cmdKey), id: 1, label: "⌘G type") { [weak self] in self?.hotKeyType() }
        registerHotKey(keyCode: 9, modifiers: UInt32(cmdKey | controlKey), id: 3, label: "⌃⌘V send") { [weak self] in self?.sendNotes() }
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let trusted = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
        fputs("quote: accessibility trusted=\(trusted)\n", stderr)
        fputs("quote: file=\(notesPath) hotkeys=⌘G ⌃⌘V\n", stderr)
    }

    private func buildUI() {
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        effect.translatesAutoresizingMaskIntoConstraints = false
        quoteLabel.font = .systemFont(ofSize: 12)
        quoteLabel.textColor = .secondaryLabelColor
        quoteLabel.lineBreakMode = .byWordWrapping
        quoteLabel.maximumNumberOfLines = 3
        quoteLabel.cell?.truncatesLastVisibleLine = true
        quoteLabel.preferredMaxLayoutWidth = Self.contentW
        quoteLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        quoteLabel.translatesAutoresizingMaskIntoConstraints = false
        textView.isRichText = false
        textView.font = .systemFont(ofSize: 15)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.drawsBackground = false
        textView.insertionPointColor = .labelColor
        textView.textContainerInset = NSSize(width: 0, height: 4)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: Self.contentW, height: .greatestFiniteMagnitude)
        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView(views: [quoteLabel, scroll])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(stack)
        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(effect)
        panel.contentView = content
        NSLayoutConstraint.activate([
            effect.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            effect.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            effect.topAnchor.constraint(equalTo: content.topAnchor),
            effect.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: Self.pad),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -Self.pad),
            stack.topAnchor.constraint(equalTo: effect.topAnchor, constant: Self.pad),
            stack.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -Self.pad),
            quoteLabel.widthAnchor.constraint(equalToConstant: Self.contentW),
            scroll.widthAnchor.constraint(equalToConstant: Self.contentW),
        ])
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
    }

    private func menuItem(_ title: String, action: Selector?, key: String, flags: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = flags
        return item
    }

    private func buildMenus() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "Quit Quote", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        editItem.submenu = edit
        edit.addItem(menuItem("Undo", action: Selector(("undo:")), key: "z"))
        edit.addItem(menuItem("Redo", action: Selector(("redo:")), key: "Z", flags: [.command, .shift]))
        edit.addItem(.separator())
        edit.addItem(menuItem("Cut", action: #selector(NSText.cut(_:)), key: "x"))
        edit.addItem(menuItem("Copy", action: #selector(NSText.copy(_:)), key: "c"))
        edit.addItem(menuItem("Paste", action: #selector(NSText.paste(_:)), key: "v"))
        edit.addItem(menuItem("Select All", action: #selector(NSText.selectAll(_:)), key: "a"))
        edit.addItem(.separator())
        let saveItem = menuItem("Save Note", action: #selector(saveNote(_:)), key: "\r")
        saveItem.target = self
        edit.addItem(saveItem)
        let cancelItem = menuItem("Cancel", action: #selector(cancelNote(_:)), key: "\u{1b}", flags: [])
        cancelItem.target = self
        edit.addItem(cancelItem)
        NSApp.mainMenu = main
    }

    private func hotKeyType() {
        if draft != nil { refocus(); return }
        let front = NSWorkspace.shared.frontmostApplication
        let pb = NSPasteboard.general
        let changeCount = pb.changeCount
        var quote: String?
        if let ax = selectedText(of: front) {
            quote = ax
            fputs("quote: quote from accessibility (\(ax.count) chars)\n", stderr)
        } else if changeCount != consumedChangeCount, let s = pb.string(forType: .string), !s.isEmpty {
            quote = s
            fputs("quote: quote from clipboard (\(s.count) chars)\n", stderr)
        } else {
            fputs("quote: no quote\n", stderr)
        }
        showBox(quote: quote, previousApp: front, changeCount: changeCount)
    }

    private func showBox(quote: String?, previousApp: NSRunningApplication?, changeCount: Int) {
        draft = Draft(quote: quote, previousApp: previousApp, changeCount: changeCount)
        if let q = quote, !q.isEmpty {
            quoteLabel.stringValue = q
            quoteLabel.isHidden = false
        } else {
            quoteLabel.stringValue = ""
            quoteLabel.isHidden = true
        }
        textView.string = ""
        positionPanel()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(textView)
    }

    private func refocus() {
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(textView)
    }

    private func positionPanel() {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let screen else { return }
        var frame = panel.frame
        frame.origin.x = screen.frame.midX - frame.width / 2
        frame.origin.y = screen.frame.minY + screen.frame.height * 2 / 3 - frame.height / 2
        panel.setFrame(frame, display: true)
    }

    @objc func saveNote(_ sender: Any?) {
        guard let d = draft else { return }
        let note = textView.string
        let qTrim = d.quote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let nTrim = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if qTrim.isEmpty && nTrim.isEmpty { close(); return }
        let quoteArg = qTrim.isEmpty ? nil : d.quote
        do {
            let existing = (try? String(contentsOf: URL(fileURLWithPath: notesPath), encoding: .utf8)) ?? ""
            guard let entry = Notes.entry(quote: quoteArg, note: note) else { close(); return }
            let merged = Notes.append(entry, to: existing)
            let url = URL(fileURLWithPath: notesPath)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try merged.write(to: url, atomically: true, encoding: .utf8)
            consumedChangeCount = d.changeCount
            fputs("quote: saved to \(notesPath)\n", stderr)
        } catch {
            fputs("quote: save error: \(error)\n", stderr)
        }
        close()
    }

    @objc func cancelNote(_ sender: Any?) {
        guard draft != nil else { return }
        close()
    }

    func windowDidResignKey(_ notification: Notification) {
        guard draft != nil else { return }
        close()
    }

    private func close() {
        guard let d = draft else { return }
        draft = nil
        panel.orderOut(nil)
        d.previousApp?.activate()
    }

    private func sendNotes() {
        do {
            let path = notesPath
            let contents = FileManager.default.fileExists(atPath: path)
                ? try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8) : ""
            guard !contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                NSSound.beep()
                return
            }
            let notesURL = URL(fileURLWithPath: path)
            let dir = notesURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try contents.write(to: dir.appendingPathComponent("quote.last.md"), atomically: true, encoding: .utf8)
            try "".write(to: notesURL, atomically: true, encoding: .utf8)
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(contents, forType: .string)
            consumedChangeCount = pb.changeCount
            fputs("quote: sent \(contents.count) chars to pasteboard\n", stderr)
        } catch {
            fputs("quote: send error: \(error)\n", stderr)
            NSSound.beep()
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
