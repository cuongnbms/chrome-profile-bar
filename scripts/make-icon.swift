// Draws the app icon (a glass pill bar: the active profile as a filled pill, the others as
// dots) and packs it into an .icns.  Usage: swift scripts/make-icon.swift Resources/AppIcon.icns
import AppKit

let colors = (blue: 0x4285F4, green: 0x0F9D58, yellow: 0xF4B400, cyan: 0x00ACC1)

func cg(_ hex: Int, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func roundedRect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> CGPath {
    CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: nil)
}

func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r), transform: nil)
}

/// Renders the icon at `px`×`px`. The artwork is drawn in a 100×100 top-left space mapped onto
/// the 824 pt body of Apple's 1024 pt macOS icon grid (100 pt margin for the shadow).
func render(_ px: Int) -> NSBitmapImageRep {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let s = CGFloat(px) / 1024
    ctx.translateBy(x: 0, y: CGFloat(px))
    ctx.scaleBy(x: s, y: -s)
    ctx.translateBy(x: 100, y: 100)
    ctx.scaleBy(x: 8.24, y: 8.24)

    let body = roundedRect(0, 0, 100, 100, 22.5)

    // Body with drop shadow, then the vertical gradient clipped to it.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 24 * s, color: cg(0, 0.35))
    ctx.addPath(body)
    ctx.setFillColor(cg(0x16181D))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                              colors: [cg(0x3A3F4B), cg(0x16181D)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: 100), options: [])
    ctx.restoreGState()

    // Hairline rim so the dark body reads on a dark Dock.
    ctx.addPath(roundedRect(0.3, 0.3, 99.4, 99.4, 22.2))
    ctx.setStrokeColor(cg(0xFFFFFF, 0.12))
    ctx.setLineWidth(0.6)
    ctx.strokePath()

    // Glass bar.
    let bar = roundedRect(9, 38, 82, 24, 12)
    ctx.addPath(bar)
    ctx.setFillColor(cg(0xFFFFFF, 0.12))
    ctx.fillPath()
    ctx.addPath(bar)
    ctx.setStrokeColor(cg(0xFFFFFF, 0.22))
    ctx.setLineWidth(1)
    ctx.strokePath()

    // Active profile pill: white dot + label stroke.
    ctx.addPath(roundedRect(12, 41, 30, 18, 9))
    ctx.setFillColor(cg(colors.blue))
    ctx.fillPath()
    ctx.setFillColor(cg(0xFFFFFF))
    ctx.addPath(circle(20, 50, 3))
    ctx.addPath(roundedRect(26, 48.5, 11, 3, 1.5))
    ctx.fillPath()

    // The other profiles.
    for (x, c) in [(53, colors.green), (66, colors.yellow), (79, colors.cyan)] {
        ctx.addPath(circle(CGFloat(x), 50, 4))
        ctx.setFillColor(cg(c))
        ctx.fillPath()
    }

    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    rep.size = NSSize(width: px, height: px)
    return rep
}

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon.icns")
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon-\(getpid()).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }

for pt in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(pt)x\(pt).png" : "icon_\(pt)x\(pt)@2x.png"
        try render(pt * scale).representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Wrote \(output.path)")
