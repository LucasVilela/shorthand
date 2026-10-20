import AppKit
import ApplicationServices
import Carbon.HIToolbox

enum Permissions {
    /// Whether Shorthand is allowed under Privacy & Security → Accessibility.
    /// With `prompt`, macOS shows its "would like to control this computer" dialog once.
    static func isTrusted(prompt: Bool) -> Bool {
        // The string value of kAXTrustedCheckOptionPrompt.
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": prompt] as CFDictionary)
    }

    /// True while some app (usually one with a password field focused) has turned on
    /// Secure Input. macOS then hides keystrokes from Shorthand, so nothing expands.
    static var isSecureInputOn: Bool {
        IsSecureEventInputEnabled()
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
