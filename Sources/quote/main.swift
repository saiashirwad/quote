import AppKit
@preconcurrency import ApplicationServices
import Carbon

func log(_ message: String) { fputs("quote: \(message)\n", stderr) }

enum Notes {
    static let url: URL = {
        let raw = ProcessInfo.processInfo.environment["QUOTE_FILE"]
        let path = (raw.map { $0.isEmpty ? nil : $0 } ?? nil).map { NSString(string: $0).expandingTildeInPath }
            ?? NSString(string: "~/notes/quote.md").expandingTildeInPath
        return URL(fileURLWithPath: path)
    }()
    static var backupURL: URL { url.deletingLastPathComponent().appendingPathComponent("quote.last.md") }
    static func read() -> String { (try? String(contentsOf: url, encoding: .utf8)) ?? "" }
    static func write(_ text: String, to target: URL = url) throws {
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: target, atomically: true, encoding: .utf8)
    }
    static func entry(quote: String?, note: String) -> String? {
        let quote = quote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let quoted = quote.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? ">" : "> \($0)" }.joined(separator: "\n")
        let blocks = [quote.isEmpty ? nil : quoted, note.isEmpty ? nil : note].compactMap { $0 }
        return blocks.isEmpty ? nil : blocks.joined(separator: "\n\n") + "\n\n---\n"
    }
    static func append(_ entry: String, to existing: String) -> String {
        guard !entry.isEmpty else { return existing }
        if existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return entry }
        var result = existing
        if !result.hasSuffix("\n") { result += "\n" }
        return result + entry
    }
}

@MainActor private enum HotKeyTable { static var actions: [UInt32: () -> Void] = [:] }

@MainActor
func registerHotKey(keyCode: Int, modifiers: Int, label: String, action: @escaping () -> Void) {
    if HotKeyTable.actions.isEmpty {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID) == noErr else {
                return OSStatus(eventNotHandledErr)
            }
            MainActor.assumeIsolated { HotKeyTable.actions[hotKeyID.id]?() }
            return noErr
        }
        var handlerRef: EventHandlerRef?
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &spec, nil, &handlerRef)
    }
    let id = UInt32(HotKeyTable.actions.count + 1)
    HotKeyTable.actions[id] = action
    var ref: EventHotKeyRef?
    let hkID = EventHotKeyID(signature: OSType(0x5154_4555), id: id)
    let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hkID, GetApplicationEventTarget(), 0, &ref)
    if status != noErr {
        log("failed to register \(label) (status \(status)) — another app (e.g. Sendpoint) probably owns it")
    }
}

func selectedText(of app: NSRunningApplication?) -> String? {
    func ax(_ el: AXUIElement, _ attr: CFString) -> CFTypeRef? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr, &v) == .success else { return nil }
        return v
    }
    guard AXIsProcessTrusted(), let app else { return nil }
    guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
    let appEl = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetMessagingTimeout(appEl, 0.25)
    _ = AXUIElementSetAttributeValue(appEl, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    guard let focusedRef = ax(appEl, kAXFocusedUIElementAttribute as CFString) else { return nil }
    let focused = unsafeDowncast(focusedRef as AnyObject, to: AXUIElement.self)
    guard let text = ax(focused, kAXSelectedTextAttribute as CFString) as? String,
          !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
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
    // NSTextView turns Esc into complete:, so it never reaches a menu key equivalent.
    override func cancelOperation(_ sender: Any?) { NSApp.sendAction(#selector(AppDelegate.cancelNote(_:)), to: nil, from: self) }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    struct Draft { var quote: String?; var previousApp: NSRunningApplication?; var changeCount: Int }

    private var consumedChangeCount = NSPasteboard.general.changeCount
    private var draft: Draft?
    private let panel: KeyablePanel
    private let quoteLabel = NSTextField(labelWithString: "")
    private let textView = NoteTextView()

    override init() {
        panel = KeyablePanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
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
        registerHotKey(keyCode: kVK_ANSI_G, modifiers: cmdKey, label: "⌘G type") { [weak self] in self?.open() }
        registerHotKey(keyCode: kVK_ANSI_V, modifiers: cmdKey | controlKey, label: "⌃⌘V send") { [weak self] in self?.sendNotes() }
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        log("accessibility trusted=\(AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary))")
        log("file=\(Notes.url.path) hotkeys=⌘G ⌃⌘V")
    }

    private func buildUI() {
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        effect.autoresizingMask = [.width, .height]
        quoteLabel.font = .systemFont(ofSize: 12)
        quoteLabel.textColor = .secondaryLabelColor
        quoteLabel.lineBreakMode = .byWordWrapping
        quoteLabel.maximumNumberOfLines = 3
        quoteLabel.cell?.truncatesLastVisibleLine = true
        quoteLabel.preferredMaxLayoutWidth = 488
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
        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        let stack = NSStackView(views: [quoteLabel, scroll])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(stack)
        panel.contentView = effect
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            stack.topAnchor.constraint(equalTo: effect.topAnchor),
            stack.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
    }

    private func menuItem(_ title: String, action: Selector?, key: String, flags: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = flags
        return item
    }

    private func buildMenus() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "Quit Quote", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: ""); main.addItem(editItem)
        let edit = NSMenu(title: "Edit"); editItem.submenu = edit
        edit.addItem(menuItem("Undo", action: Selector(("undo:")), key: "z"))
        edit.addItem(menuItem("Redo", action: Selector(("redo:")), key: "Z", flags: [.command, .shift]))
        edit.addItem(.separator())
        edit.addItem(menuItem("Cut", action: #selector(NSText.cut(_:)), key: "x"))
        edit.addItem(menuItem("Copy", action: #selector(NSText.copy(_:)), key: "c"))
        edit.addItem(menuItem("Paste", action: #selector(NSText.paste(_:)), key: "v"))
        edit.addItem(menuItem("Select All", action: #selector(NSText.selectAll(_:)), key: "a"))
        edit.addItem(.separator())
        let saveItem = menuItem("Save Note", action: #selector(saveNote(_:)), key: "\r"); saveItem.target = self; edit.addItem(saveItem)
        NSApp.mainMenu = main
    }

    private func open() {
        if draft != nil { focus(); return }
        let front = NSWorkspace.shared.frontmostApplication
        let pb = NSPasteboard.general
        let changeCount = pb.changeCount
        var quote: String?
        if let ax = selectedText(of: front) {
            quote = ax; log("quote from accessibility (\(ax.count) chars)")
        } else if changeCount != consumedChangeCount, let s = pb.string(forType: .string), !s.isEmpty {
            quote = s; log("quote from clipboard (\(s.count) chars)")
        } else { log("no quote") }
        draft = Draft(quote: quote, previousApp: front, changeCount: changeCount)
        quoteLabel.stringValue = quote ?? ""
        quoteLabel.isHidden = quote == nil
        textView.string = ""
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let screen {
            var frame = panel.frame
            frame.origin.x = screen.frame.midX - frame.width / 2
            frame.origin.y = screen.frame.minY + screen.frame.height * 2 / 3 - frame.height / 2
            panel.setFrame(frame, display: true)
        }
        focus()
    }

    private func focus() {
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(textView)
    }

    @objc func saveNote(_ sender: Any?) {
        guard let draft else { return }
        if let entry = Notes.entry(quote: draft.quote, note: textView.string) {
            do {
                try Notes.write(Notes.append(entry, to: Notes.read()))
                consumedChangeCount = draft.changeCount
                log("saved to \(Notes.url.path)")
            } catch { log("save error: \(error)") }
        }
        close()
    }

    @objc func cancelNote(_ sender: Any?) { close() }
    func windowDidResignKey(_ notification: Notification) { close() }

    private func close() {
        guard let d = draft else { return }
        draft = nil
        panel.orderOut(nil)
        d.previousApp?.activate()
    }

    private func sendNotes() {
        do {
            let contents = Notes.read()
            guard !contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { NSSound.beep(); return }
            try Notes.write(contents, to: Notes.backupURL)
            try Notes.write("")
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(contents, forType: .string)
            consumedChangeCount = pb.changeCount
            log("sent \(contents.count) chars to pasteboard")
        } catch { log("send error: \(error)"); NSSound.beep() }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
