import CoreGraphics

/// Keeps a saved origin only if it is on some screen, clamped so the panel fits.
/// Coordinates are AppKit's (bottom-left origin); `screens` are full screen frames.
public func placeOnScreen(_ saved: CGPoint?, size: CGSize, screens: [CGRect]) -> CGPoint? {
    guard let pos = saved, let f = screens.first(where: { $0.contains(pos) }) else { return nil }
    return CGPoint(
        x: max(f.minX, min(pos.x, f.maxX - size.width)),
        y: max(f.minY, min(pos.y, f.maxY - size.height)))
}

/// Centered at the bottom of `visibleFrame` (the main screen minus Dock and menu bar).
public func defaultOrigin(size: CGSize, visibleFrame f: CGRect) -> CGPoint {
    CGPoint(x: (f.minX + (f.width - size.width) / 2).rounded(), y: f.minY + 8)
}
