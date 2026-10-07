import AppKit
import QuoteFileLogic

@MainActor
final class QuoteAppDelegate: NSObject, NSApplicationDelegate {
    private var hotKeys: HotKeyCenter!
    private var noteBox: NoteBoxController!
    private let notesPath = NoteFile.resolvedPath()
    /// Pasteboard changeCount after send, or when a note with quote was saved — unchanged means no new quote.
    private var pasteboardBaselineChangeCount: Int
    private var capturePasteboardChangeCount: Int?

    override init() {
        pasteboardBaselineChangeCount = NSPasteboard.general.changeCount
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildEditMenu()

        noteBox = NoteBoxController { [weak self] quote, note in
            self?.saveNote(quote: quote, note: note)
        }

        hotKeys = HotKeyCenter { [weak self] id in
            self?.handleHotKey(id)
        }
        hotKeys.install()

        fputs("quote: file=\(notesPath) hotkeys=⌘G ⌃⌘V\n", stderr)
    }

    private func buildEditMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "Quit Quote", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let editMenuItem = NSMenuItem()
        editMenuItem.title = "Edit"
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu

        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        NSApp.mainMenu = mainMenu
    }

    private func handleHotKey(_ id: HotKeyID) {
        switch id {
        case .typeNote:
            if noteBox.isVisible {
                noteBox.refocus()
            } else {
                openBox()
            }
        case .send:
            sendNotes()
        }
    }

    private func openBox() {
        let pb = NSPasteboard.general
        let changeCount = pb.changeCount
        capturePasteboardChangeCount = changeCount
        var quote: String?
        if changeCount != pasteboardBaselineChangeCount,
           let s = pb.string(forType: .string),
           !s.isEmpty
        {
            quote = s
        }
        noteBox.present(quote: quote)
    }

    private func saveNote(quote: String?, note: String) {
        do {
            try NoteFile.appendNote(quote: quote, note: note, path: notesPath)
            if let q = quote, !q.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let captured = capturePasteboardChangeCount
            {
                pasteboardBaselineChangeCount = captured
            }
            capturePasteboardChangeCount = nil
            fputs("quote: saved to \(notesPath)\n", stderr)
        } catch {
            fputs("quote: save error: \(error)\n", stderr)
        }
    }

    private func sendNotes() {
        do {
            let contents = try NoteFile.sendNotes(path: notesPath)
            guard !contents.isEmpty else {
                NSSound.beep()
                return
            }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(contents, forType: .string)
            pasteboardBaselineChangeCount = pb.changeCount
            fputs("quote: sent \(contents.count) chars to pasteboard\n", stderr)
        } catch {
            fputs("quote: send error: \(error)\n", stderr)
            NSSound.beep()
        }
    }
}

let app = NSApplication.shared
let delegate = QuoteAppDelegate()
app.delegate = delegate
app.run()
