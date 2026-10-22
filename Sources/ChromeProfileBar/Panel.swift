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
        contentView = glassBackground(around: bar)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Matches the bar's metrics; call after `BarView.configure`.
    func setCornerRadius(_ radius: CGFloat) { setGlassCornerRadius(contentView!, radius) }
}

/// Liquid Glass like the Dock on macOS 26, a blurred HUD view before that.
@MainActor func glassBackground(around content: NSView) -> NSView {
    if #available(macOS 26, *) {
        let glass = NSGlassEffectView()
        glass.contentView = content
        return glass
    }
    let fx = NSVisualEffectView()
    fx.material = .hudWindow
    fx.blendingMode = .behindWindow
    fx.state = .active
    fx.addSubview(content)
    return fx
}

@MainActor func setGlassCornerRadius(_ background: NSView, _ radius: CGFloat) {
    if #available(macOS 26, *), let glass = background as? NSGlassEffectView {
        glass.cornerRadius = radius
    } else if let fx = background as? NSVisualEffectView {
        let mask = NSImage(size: NSSize(width: 2 * radius + 1, height: 2 * radius + 1), flipped: false) {
            NSBezierPath(roundedRect: $0, xRadius: radius, yRadius: radius).fill()
            return true
        }
        mask.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        mask.resizingMode = .stretch
        fx.maskImage = mask
    }
}

/// Sizes derived from the bar height so the bar can match the Dock: tiles and buttons as tall
/// as Dock icons, with corners concentric with the panel's.
struct BarMetrics {
    let height: CGFloat
    var pad: CGFloat { (height * 0.13).rounded() }
    var pill: CGFloat { height - 2 * pad }
    var pillRadius: CGFloat { (pill * 0.26).rounded() }
    var cornerRadius: CGFloat { pillRadius + pad }
    var btnPad: CGFloat { (pill * 0.36).rounded() }
    var font: NSFont { .systemFont(ofSize: height >= 48 ? 14 : 13, weight: .medium) }
}

/// Two looks. Tiles (default), like Dock icons: the profile's Chrome avatar (or its initial on
/// the profile color), the name in a bubble on hover, a dot under the active one. Labels:
/// grip "⋮" + one button per profile with a dot in the profile color, the active one filled.
final class BarView: NSView {
    static let GAP: CGFloat = 2, GRIP: CGFloat = 18, DOT: CGFloat = 7, DOT_GAP: CGFloat = 7

    private var m = BarMetrics(height: 36)
    private var showLabels = false
    var cornerRadius: CGFloat { m.cornerRadius }

    private struct Button {
        let label: String
        let color: NSColor
        let image: NSImage?
        let frame: NSRect
    }

    private var buttons: [Button] = []
    var activeIndex: Int? { didSet { if activeIndex != oldValue { needsDisplay = true } } }
    private var hoverIndex: Int? {
        didSet { if hoverIndex != oldValue { needsDisplay = true; updateBubble() } }
    }
    private var pressedIndex: Int? { didSet { if pressedIndex != oldValue { needsDisplay = true } } }
    private let bubble = HoverLabel()
    /// Drawn on the bottom-right corner of every tile.
    var badge: NSImage? { didSet { needsDisplay = true } }

    /// (profile index, Alt held)
    var onClick: ((Int, Bool) -> Void)?
    var menuProvider: (() -> NSMenu)?

    override var isFlipped: Bool { true }

    /// Lays out the buttons for a bar `height` tall and returns the size the bar needs.
    /// `avatars` is parallel to `profiles`.
    func configure(_ profiles: [Profile], avatars: [NSImage?], labels: Bool, height: CGFloat) -> NSSize {
        m = BarMetrics(height: height)
        showLabels = labels
        var x = m.pad + (labels ? Self.GRIP : 0)
        buttons = profiles.enumerated().map { i, p in
            let w = labels ? m.btnPad + Self.DOT + Self.DOT_GAP + textWidth(p.label) + m.btnPad : m.pill
            defer { x += w + Self.GAP }
            let c = rgb(hex: p.color) ?? rgb(hex: Profile.defaultColor)!
            return Button(label: p.label, color: NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1),
                          image: avatars.indices.contains(i) ? avatars[i] : nil,
                          frame: NSRect(x: x, y: m.pad, width: w, height: m.pill))
        }
        removeAllToolTips()
        if labels {
            for (i, b) in buttons.enumerated() {
                addToolTip(b.frame, owner: "\(b.label)\(hotkey(i))\n⌥-click: name the front Chrome window" as NSString,
                           userData: nil)
            }
        }
        hoverIndex = nil
        needsDisplay = true
        let width = (buttons.last?.frame.maxX ?? x) + m.pad
        return NSSize(width: width, height: height)
    }

    private func textWidth(_ s: String) -> CGFloat {
        ceil(NSAttributedString(string: s, attributes: [.font: m.font]).size().width)
    }

    private func hotkey(_ i: Int) -> String { i < 9 ? "  ⌃⌥\(i + 1)" : "" }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if showLabels { drawLabels() } else { drawTiles() }
    }

    private func drawTiles() {
        for (i, b) in buttons.enumerated() {
            // Like an app icon on its canvas: the shape leaves a margin inside the tile.
            let inset = (b.frame.width * 0.09).rounded()
            let icon = b.frame.insetBy(dx: inset, dy: inset)
            let radius = icon.width * 0.225
            let shape = NSBezierPath(roundedRect: icon, xRadius: radius, yRadius: radius)

            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
            shadow.shadowBlurRadius = 2
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            shadow.set()
            b.color.setFill()
            shape.fill()
            NSGraphicsContext.restoreGraphicsState()

            NSGraphicsContext.saveGraphicsState()
            shape.addClip()
            if let image = b.image {
                image.draw(in: icon, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
                           hints: [.interpolation: NSImageInterpolation.high.rawValue])
            } else {
                NSGradient(starting: b.color.blended(withFraction: 0.25, of: .white)!,
                           ending: b.color.blended(withFraction: 0.2, of: .black)!)!.draw(in: icon, angle: 90)
                let initial = NSAttributedString(string: b.label.prefix(1).uppercased(), attributes: [
                    .font: NSFont.systemFont(ofSize: icon.height * 0.5, weight: .semibold), .foregroundColor: NSColor.white])
                let s = initial.size()
                initial.draw(at: NSPoint(x: icon.midX - s.width / 2, y: icon.midY - s.height / 2))
            }
            if i == pressedIndex {
                NSColor.black.withAlphaComponent(0.3).setFill()
                shape.fill()
            }
            NSGraphicsContext.restoreGraphicsState()
            NSColor.white.withAlphaComponent(0.15).setStroke()
            shape.lineWidth = 0.5
            shape.stroke()

            if let badge {
                // Only the round logo: it fills the middle 64% of Chrome's (squircle) app icon.
                let s = (icon.width * 0.4).rounded()
                let spot = NSRect(x: icon.maxX - s + 3, y: icon.maxY - s + 3, width: s, height: s)
                let circle = NSBezierPath(ovalIn: spot)
                NSGraphicsContext.saveGraphicsState()
                let shadow = NSShadow()
                shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
                shadow.shadowBlurRadius = 1.5
                shadow.set()
                NSColor.white.setFill()
                circle.fill()
                NSGraphicsContext.restoreGraphicsState()
                NSGraphicsContext.saveGraphicsState()
                circle.addClip()
                let full = s / 0.63
                badge.draw(in: spot.insetBy(dx: (s - full) / 2, dy: (s - full) / 2), from: .zero,
                           operation: .sourceOver, fraction: 1, respectFlipped: true,
                           hints: [.interpolation: NSImageInterpolation.high.rawValue])
                NSGraphicsContext.restoreGraphicsState()
            }

            if i == activeIndex {  // the Dock's "running" dot, in the bottom padding
                let d: CGFloat = 4, y = (b.frame.maxY + bounds.height) / 2
                NSColor.labelColor.withAlphaComponent(0.75).setFill()
                NSBezierPath(ovalIn: NSRect(x: b.frame.midX - d / 2, y: y - d / 2, width: d, height: d)).fill()
            }
        }
    }

    private func drawLabels() {
        let grip = NSAttributedString(string: "⋮", attributes: [
            .font: NSFont.systemFont(ofSize: 15, weight: .bold), .foregroundColor: NSColor.tertiaryLabelColor])
        let gs = grip.size()
        grip.draw(at: NSPoint(x: m.pad + 2 + (Self.GRIP - gs.width) / 2, y: (bounds.height - gs.height) / 2))

        for (i, b) in buttons.enumerated() {
            let active = i == activeIndex
            let pill = NSBezierPath(roundedRect: b.frame, xRadius: m.pillRadius, yRadius: m.pillRadius)
            if active {
                b.color.setFill()
                pill.fill()
            } else if i == hoverIndex {
                NSColor.labelColor.withAlphaComponent(0.1).setFill()
                pill.fill()
            }

            let dot = NSRect(x: b.frame.minX + m.btnPad, y: b.frame.midY - Self.DOT / 2, width: Self.DOT, height: Self.DOT)
            (active ? NSColor.white.withAlphaComponent(0.9) : b.color).setFill()
            NSBezierPath(ovalIn: dot).fill()

            let text = NSAttributedString(string: b.label, attributes: [
                .font: m.font, .foregroundColor: active ? NSColor.white : NSColor.labelColor])
            let s = text.size()
            text.draw(at: NSPoint(x: dot.maxX + Self.DOT_GAP, y: b.frame.midY - s.height / 2))
        }
    }

    private func updateBubble() {
        guard !showLabels, let i = hoverIndex, let window else { return bubble.hide() }
        let tile = window.convertToScreen(convert(buttons[i].frame, to: nil))
        let title = NSMutableAttributedString(string: buttons[i].label, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.labelColor])
        title.append(NSAttributedString(string: hotkey(i), attributes: [
            .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor]))
        bubble.show(title, centerX: tile.midX, bottomY: window.frame.maxY + 6)
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

    /// Drops the hover state (and its bubble) when the bar is hidden under the pointer.
    func clearHover() { hoverIndex = nil }
}

/// The Dock's name bubble: a small glass capsule above the hovered tile.
@MainActor
final class HoverLabel {
    private let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
                                defer: true)
    private let text = NSTextField(labelWithString: "")
    private let content = NSView()
    private static let padX: CGFloat = 12, padY: CGFloat = 5

    init() {
        panel.level = NSWindow.Level(NSWindow.Level.floating.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        content.addSubview(text)
        panel.contentView = glassBackground(around: content)
    }

    func show(_ title: NSAttributedString, centerX: CGFloat, bottomY: CGFloat) {
        text.attributedStringValue = title
        let s = text.fittingSize
        let size = NSSize(width: ceil(s.width) + 2 * Self.padX, height: ceil(s.height) + 2 * Self.padY)
        text.frame = NSRect(x: Self.padX, y: Self.padY, width: ceil(s.width), height: ceil(s.height))
        content.frame = NSRect(origin: .zero, size: size)
        setGlassCornerRadius(panel.contentView!, size.height / 2)
        panel.setFrame(NSRect(x: (centerX - size.width / 2).rounded(), y: bottomY, width: size.width, height: size.height),
                       display: true)
        panel.orderFrontRegardless()
    }

    func hide() { panel.orderOut(nil) }
}
