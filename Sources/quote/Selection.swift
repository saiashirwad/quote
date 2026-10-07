import AppKit
@preconcurrency import ApplicationServices

@MainActor
enum Selection {
    private static var manualAccessibilityPIDs = Set<pid_t>()

    static func promptForTrustIfNeeded() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        fputs("quote: accessibility trusted=\(trusted)\n", stderr)
    }

    static func selectedText(in app: NSRunningApplication?) -> String? {
        guard AXIsProcessTrusted(), let app else { return nil }
        let pid = app.processIdentifier
        guard pid != ProcessInfo.processInfo.processIdentifier else { return nil }

        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 0.25)

        if !manualAccessibilityPIDs.contains(pid) {
            manualAccessibilityPIDs.insert(pid)
            _ = AXUIElementSetAttributeValue(
                appElement,
                "AXManualAccessibility" as CFString,
                kCFBooleanTrue
            )
        }

        guard let focusedRef = copyAXValue(appElement, attribute: kAXFocusedUIElementAttribute as CFString) else {
            return nil
        }
        let focused = unsafeDowncast(focusedRef as AnyObject, to: AXUIElement.self)
        guard let text = copyAXValue(focused, attribute: kAXSelectedTextAttribute as CFString) as? String else {
            return nil
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return text
    }

    private static func copyAXValue(_ element: AXUIElement, attribute: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value
    }
}
