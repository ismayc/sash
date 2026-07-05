import AppKit
import ApplicationServices

/// Wraps the Accessibility-permission gate. Moving windows that belong to *other*
/// apps requires the process to be "trusted" in System Settings ▸ Privacy & Security ▸
/// Accessibility. Without it every AX call silently fails.
enum Accessibility {

    /// Is this process currently trusted?
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Trigger the system prompt that offers to open the Accessibility pane and lists this app.
    @discardableResult
    static func requestIfNeeded() -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    /// Deep-link straight to the Accessibility settings pane.
    static func openSettingsPane() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
