import CoreGraphics

/// The Dock's glass on a screen, vertically (AppKit coordinates).
public struct DockBand: Equatable, Sendable {
    public var minY: CGFloat
    public var height: CGFloat

    public init(minY: CGFloat, height: CGFloat) {
        self.minY = minY
        self.height = height
    }
}

/// The glass sits 4pt above the screen edge and `visibleFrame` stops 2pt above the glass
/// (measured on macOS 26 with tile size 39: 59pt strip, 53pt glass).
let dockMarginBelow: CGFloat = 4, dockMarginAbove: CGFloat = 2

/// The bottom Dock's band on a screen, or nil if that screen has no visible bottom Dock.
public func bottomDockBand(frame: CGRect, visibleFrame v: CGRect) -> DockBand? {
    let strip = v.minY - frame.minY
    guard strip > dockMarginBelow + dockMarginAbove + 1 else { return nil }
    return DockBand(minY: frame.minY + dockMarginBelow, height: strip - dockMarginBelow - dockMarginAbove)
}

/// Glass height for a Dock tile size: the icon plus 7pt above and below it.
public func dockHeight(tileSize: CGFloat) -> CGFloat { tileSize + 14 }

/// Bar height matching a Dock of `dockHeight`, kept within a usable range.
public func barHeight(dockHeight: CGFloat?) -> CGFloat {
    max(36, min(dockHeight ?? 36, 64)).rounded()
}

/// Origin of the bar attached to the Dock: vertically centered on `band`, `gap` left of the
/// glass when `dockMinX` is known, else at `fallbackX`; clamped to `screen`.
public func dockedOrigin(size: CGSize, band: DockBand, dockMinX: CGFloat?, fallbackX: CGFloat,
                         screen: CGRect, gap: CGFloat = 8) -> CGPoint {
    let x = dockMinX.map { $0 - gap - size.width } ?? fallbackX
    return CGPoint(
        x: max(screen.minX, min(x, screen.maxX - size.width)).rounded(),
        y: (band.minY + (band.height - size.height) / 2).rounded())
}
