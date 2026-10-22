import AppKit
import ApplicationServices

/// What the bar needs to know about the Dock. The horizontal extent comes from the Dock's
/// icon list through Accessibility (optional); everything else from public state.
enum Dock {
    /// `com.apple.dock` tilesize, nil if never changed.
    static var tileSize: CGFloat? {
        (CFPreferencesCopyAppValue("tilesize" as CFString, "com.apple.dock" as CFString) as? NSNumber)
            .map { CGFloat(truncating: $0) }
    }

    /// Frame of the Dock's icon list in AX coordinates (top-left origin of the primary screen).
    static func listFrame() -> CGRect? {
        guard AXIsProcessTrusted(),
              let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
        else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1)
        let children = copy(app, kAXChildrenAttribute) as? [AXUIElement] ?? []
        guard let list = children.first(where: { copy($0, kAXRoleAttribute) as? String == kAXListRole }),
              let pos = copy(list, kAXPositionAttribute), let size = copy(list, kAXSizeAttribute)
        else { return nil }
        var p = CGPoint.zero, s = CGSize.zero
        AXValueGetValue(pos as! AXValue, .cgPoint, &p)
        AXValueGetValue(size as! AXValue, .cgSize, &s)
        return CGRect(origin: p, size: s)
    }

    private static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }
}
