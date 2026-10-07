import AppKit
import QuoteFileLogic

@MainActor
final class NoteTextView: NSTextView {
    var onSave: (() -> Void)?
    var onCancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command), event.keyCode == 36 { // ⌘↩
            onSave?()
            return
        }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

@MainActor
final class NoteBoxController: NSWindowController {
    private let panel: NSPanel
    private let quoteLabel: NSTextField
    private let textView: NoteTextView
    private let scrollView: NSScrollView
    private var previousApp: NSRunningApplication?
    private var currentQuote: String?
    private var onSaved: ((String?, String) -> Void)?

    init(onSaved: @escaping (String?, String) -> Void) {
        self.onSaved = onSaved
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 160),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.title = "Quote"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .windowBackgroundColor

        quoteLabel = NSTextField(labelWithString: "")
        quoteLabel.font = .systemFont(ofSize: 13)
        quoteLabel.textColor = .secondaryLabelColor
        quoteLabel.lineBreakMode = .byWordWrapping
        quoteLabel.maximumNumberOfLines = 3
        quoteLabel.cell?.truncatesLastVisibleLine = true
        quoteLabel.preferredMaxLayoutWidth = 456
        quoteLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        quoteLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        quoteLabel.translatesAutoresizingMaskIntoConstraints = false

        textView = NoteTextView()
        textView.isRichText = false
        textView.font = .systemFont(ofSize: 14)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [quoteLabel, scrollView])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = panel.contentView!
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            content.widthAnchor.constraint(equalToConstant: 480),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            quoteLabel.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24),
            scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24),
            scrollView.heightAnchor.constraint(equalToConstant: 90),
        ])

        super.init(window: panel)

        textView.onSave = { [weak self] in self?.saveAndClose() }
        textView.onCancel = { [weak self] in self?.cancelAndClose() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    var isVisible: Bool { panel.isVisible }

    func present(quote: String?, startDictation: Bool) {
        previousApp = NSWorkspace.shared.frontmostApplication
        currentQuote = quote

        if let q = quote, !q.isEmpty {
            quoteLabel.stringValue = truncatedQuotePreview(q)
            quoteLabel.isHidden = false
        } else {
            quoteLabel.stringValue = ""
            quoteLabel.isHidden = true
        }

        textView.string = ""
        positionPanel()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKey()
        panel.makeFirstResponder(textView)

        if startDictation {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                guard self.panel.isKeyWindow else { return }
                NSApp.sendAction(Selector(("startDictation:")), to: nil, from: nil)
            }
        }
    }

    func refocus(startDictation: Bool) {
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeFirstResponder(textView)
        if startDictation {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                NSApp.sendAction(Selector(("startDictation:")), to: nil, from: nil)
            }
        }
    }

    private func truncatedQuotePreview(_ quote: String) -> String {
        let lines = quote.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.count <= 3 { return lines.joined(separator: "\n") }
        return lines.prefix(3).joined(separator: "\n") + "…"
    }

    private func positionPanel() {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
            ?? NSScreen.main else { return }
        let mouse = NSEvent.mouseLocation
        var frame = panel.frame
        frame.origin.x = mouse.x - frame.width / 2
        let upperThirdY = screen.frame.minY + screen.frame.height * 2 / 3 - frame.height / 2
        frame.origin.y = upperThirdY
        panel.setFrame(frame, display: true)
    }

    private func saveAndClose() {
        let note = textView.string
        let quote = currentQuote
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let quoteEmpty = quote?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        if trimmedNote.isEmpty && quoteEmpty {
            closeAndReactivate()
            return
        }
        onSaved?(quoteEmpty ? nil : quote, note)
        closeAndReactivate()
    }

    private func cancelAndClose() {
        closeAndReactivate()
    }

    private func closeAndReactivate() {
        panel.orderOut(nil)
        if let app = previousApp {
            app.activate()
        }
    }
}
