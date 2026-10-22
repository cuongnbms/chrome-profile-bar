import AppKit
import ProfileBarCore

/// Floating, non-activating panel on every Space; clicking it never steals focus.
final class BarPanel: NSPanel {
    init(bar: BarView) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        bar.autoresizingMask = [.width, .height]
        contentView = Self.background(for: bar)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Liquid Glass like the Dock on macOS 26, a blurred HUD capsule before that.
    private static func background(for bar: BarView) -> NSView {
        let radius = BarView.height / 2
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = radius
            glass.contentView = bar
            return glass
        }
        let fx = NSVisualEffectView()
        fx.material = .hudWindow
        fx.blendingMode = .behindWindow
        fx.state = .active
        let mask = NSImage(size: NSSize(width: 2 * radius + 1, height: 2 * radius + 1), flipped: false) {
            NSBezierPath(roundedRect: $0, xRadius: radius, yRadius: radius).fill()
            return true
        }
        mask.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        mask.resizingMode = .stretch
        fx.maskImage = mask
        fx.addSubview(bar)
        return fx
    }
}

/// Grip "⋮" + one borderless pill per profile: a dot in the profile color, a hover
/// highlight, and a pill filled with the profile color for the active one.
final class BarView: NSView {
    static let BH: CGFloat = 28, GAP: CGFloat = 2, PAD: CGFloat = 4, GRIP: CGFloat = 18
    static let BTN_PAD: CGFloat = 12, DOT: CGFloat = 7, DOT_GAP: CGFloat = 7
    static let height = PAD + BH + PAD
    static let font = NSFont.systemFont(ofSize: 13, weight: .medium)

    private struct Button {
        let label: String
        let color: NSColor
        let frame: NSRect
    }

    private var buttons: [Button] = []
    var activeIndex: Int? { didSet { if activeIndex != oldValue { needsDisplay = true } } }
    private var hoverIndex: Int? { didSet { if hoverIndex != oldValue { needsDisplay = true } } }
    private var pressedIndex: Int?

    /// (profile index, Alt held)
    var onClick: ((Int, Bool) -> Void)?
    var menuProvider: (() -> NSMenu)?

    override var isFlipped: Bool { true }

    /// Lays out the buttons and returns the size the bar needs.
    func configure(_ profiles: [Profile]) -> NSSize {
        var x = Self.PAD + Self.GRIP
        buttons = profiles.map { p in
            let textWidth = ceil(NSAttributedString(string: p.label, attributes: [.font: Self.font]).size().width)
            let w = Self.BTN_PAD + Self.DOT + Self.DOT_GAP + textWidth + Self.BTN_PAD
            defer { x += w + Self.GAP }
            let c = rgb(hex: p.color) ?? rgb(hex: Profile.defaultColor)!
            return Button(label: p.label, color: NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1),
                          frame: NSRect(x: x, y: Self.PAD, width: w, height: Self.BH))
        }
        removeAllToolTips()
        for (i, b) in buttons.enumerated() {
            let hotkey = i < 9 ? "  ⌃⌥\(i + 1)" : ""
            addToolTip(b.frame, owner: "\(b.label)\(hotkey)\n⌥-click: name the front Chrome window" as NSString,
                       userData: nil)
        }
        hoverIndex = nil
        needsDisplay = true
        let width = (buttons.last?.frame.maxX ?? Self.PAD + Self.GRIP) + Self.PAD + 2
        return NSSize(width: width, height: Self.height)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let grip = NSAttributedString(string: "⋮", attributes: [
            .font: NSFont.systemFont(ofSize: 15, weight: .bold), .foregroundColor: NSColor.tertiaryLabelColor])
        let gs = grip.size()
        grip.draw(at: NSPoint(x: Self.PAD + 2 + (Self.GRIP - gs.width) / 2, y: (bounds.height - gs.height) / 2))

        for (i, b) in buttons.enumerated() {
            let active = i == activeIndex
            let pill = NSBezierPath(roundedRect: b.frame, xRadius: Self.BH / 2, yRadius: Self.BH / 2)
            if active {
                b.color.setFill()
                pill.fill()
            } else if i == hoverIndex {
                NSColor.labelColor.withAlphaComponent(0.1).setFill()
                pill.fill()
            }

            let dot = NSRect(x: b.frame.minX + Self.BTN_PAD, y: b.frame.midY - Self.DOT / 2, width: Self.DOT, height: Self.DOT)
            (active ? NSColor.white.withAlphaComponent(0.9) : b.color).setFill()
            NSBezierPath(ovalIn: dot).fill()

            let text = NSAttributedString(string: b.label, attributes: [
                .font: Self.font, .foregroundColor: active ? NSColor.white : NSColor.labelColor])
            let s = text.size()
            text.draw(at: NSPoint(x: dot.maxX + Self.DOT_GAP, y: b.frame.midY - s.height / 2))
        }
    }

    private func index(at event: NSEvent) -> Int? {
        let p = convert(event.locationInWindow, from: nil)
        return buttons.firstIndex { $0.frame.contains(p) }
    }

    // MARK: Mouse

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if let i = index(at: event) {
            pressedIndex = i
        } else {
            window?.performDrag(with: event)  // drag the background to move the panel
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer { pressedIndex = nil }
        guard let i = pressedIndex, index(at: event) == i else { return }
        onClick?(i, event.modifierFlags.contains(.option))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseMoved(with event: NSEvent) { hoverIndex = index(at: event) }
    override func mouseEntered(with event: NSEvent) { hoverIndex = index(at: event) }
    override func mouseExited(with event: NSEvent) { hoverIndex = nil }

    override func menu(for event: NSEvent) -> NSMenu? { menuProvider?() }
}
