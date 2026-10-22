import AppKit
import ApplicationServices

/// Chrome window titles ("… - Google Chrome - <person> (<profile>)") through Accessibility.
/// Optional: Chrome's scripting `name` is only the tab title, so the profile-suffix fallback
/// needs this permission. Everything else works without it.
enum WindowTitles {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that leads to System Settings > Accessibility.
    static func requestTrust() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func windows(pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1)
        return copy(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
    }

    static func focusedWindowTitle(pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1)
        guard let w = copy(app, kAXFocusedWindowAttribute), CFGetTypeID(w) == AXUIElementGetTypeID() else { return nil }
        return title(w as! AXUIElement)
    }

    static func title(_ window: AXUIElement) -> String {
        copy(window, kAXTitleAttribute) as? String ?? ""
    }

    /// Unminimizes and raises; the caller activates the app afterwards.
    static func raise(_ window: AXUIElement) {
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }

    private static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }
}
