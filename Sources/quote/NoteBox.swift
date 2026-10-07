import AppKit
import QuoteFileLogic

final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

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

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty else { return }
        let font = self.font ?? .systemFont(ofSize: 15)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.placeholderTextColor,
        ]
        let inset = textContainerInset
        let rect = NSRect(
            x: inset.width + 5,
            y: inset.height,
            width: bounds.width - inset.width * 2 - 10,
            height: bounds.height - inset.height * 2
        )
        "Note".draw(with: rect, options: .usesLineFragmentOrigin, attributes: attrs)
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }
}

@MainActor
final class NoteBoxController: NSWindowController {
    private let panel: KeyablePanel
    private let quoteLabel: NSTextField
    private let textView: NoteTextView
    private let scrollView: NSScrollView
    private var previousApp: NSRunningApplication?
    private var currentQuote: String?
    private var onSaved: ((String?, String) -> Void)?
    private var suppressResignCancel = false
    private var hasClosed = false

    private static let boxWidth: CGFloat = 520
    private static let padding: CGFloat = 16
    private static let contentWidth: CGFloat = boxWidth - padding * 2

    init(onSaved: @escaping (String?, String) -> Void) {
        self.onSaved = onSaved
        panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.boxWidth, height: 200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true

        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        effect.translatesAutoresizingMaskIntoConstraints = false

        quoteLabel = NSTextField(labelWithString: "")
        quoteLabel.font = .systemFont(ofSize: 12)
        quoteLabel.textColor = .secondaryLabelColor
        quoteLabel.lineBreakMode = .byWordWrapping
        quoteLabel.maximumNumberOfLines = 3
        quoteLabel.cell?.truncatesLastVisibleLine = true
        quoteLabel.preferredMaxLayoutWidth = Self.contentWidth
        quoteLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        quoteLabel.translatesAutoresizingMaskIntoConstraints = false

        textView = NoteTextView()
        textView.isRichText = false
        textView.font = .systemFont(ofSize: 15)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.insertionPointColor = .labelColor
        textView.textContainerInset = NSSize(width: 0, height: 4)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: Self.contentWidth,
            height: CGFloat.greatestFiniteMagnitude
        )

        scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [quoteLabel, scrollView])
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

            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: Self.padding),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -Self.padding),
            stack.topAnchor.constraint(equalTo: effect.topAnchor, constant: Self.padding),
            stack.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -Self.padding),

            quoteLabel.widthAnchor.constraint(equalToConstant: Self.contentWidth),
            scrollView.widthAnchor.constraint(equalToConstant: Self.contentWidth),
            scrollView.heightAnchor.constraint(equalToConstant: 90),
        ])

        super.init(window: panel)

        textView.onSave = { [weak self] in self?.saveAndClose() }
        textView.onCancel = { [weak self] in self?.cancelAndClose() }

        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.panelDidResignKey()
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    var isVisible: Bool { panel.isVisible }

    func present(quote: String?, previousApp: NSRunningApplication? = nil) {
        hasClosed = false
        suppressResignCancel = true
        self.previousApp = previousApp ?? NSWorkspace.shared.frontmostApplication
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
        panel.makeFirstResponder(textView)

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            self?.suppressResignCancel = false
        }
    }

    func refocus() {
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeFirstResponder(textView)
    }

    private func panelDidResignKey() {
        guard !suppressResignCancel, !hasClosed, panel.isVisible else { return }
        cancelAndClose()
    }

    private func truncatedQuotePreview(_ quote: String) -> String {
        let lines = quote.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.count <= 3 { return lines.joined(separator: "\n") }
        return lines.prefix(3).joined(separator: "\n") + "…"
    }

    private func positionPanel() {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
            ?? NSScreen.main else { return }
        var frame = panel.frame
        frame.origin.x = screen.frame.midX - frame.width / 2
        let upperThirdY = screen.frame.minY + screen.frame.height * 2 / 3 - frame.height / 2
        frame.origin.y = upperThirdY
        panel.setFrame(frame, display: true)
    }

    private func saveAndClose() {
        guard !hasClosed else { return }
        suppressResignCancel = true
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
        guard !hasClosed else { return }
        suppressResignCancel = true
        closeAndReactivate()
    }

    private func closeAndReactivate() {
        guard !hasClosed else { return }
        hasClosed = true
        panel.orderOut(nil)
        if let app = previousApp {
            app.activate()
        }
    }
}
