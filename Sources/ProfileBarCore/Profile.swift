import Foundation

/// One button on the bar.
///   label   : button text
///   window  : window name ("Name window…" / given name) used to find the window
///   profile : profile display name, fallback match against the window title suffix
///   dir     : last segment of "Profile Path" in chrome://version
public struct Profile: Equatable, Sendable {
    public static let defaultColor = "#4285F4"

    public let label: String
    public let window: String
    public let profile: String
    public let dir: String
    public let color: String

    public init(label: String, window: String? = nil, profile: String? = nil, dir: String, color: String? = nil) {
        self.label = label
        self.window = window ?? label
        self.profile = profile ?? label
        self.dir = dir
        self.color = color ?? Profile.defaultColor
    }

    /// Chrome titles look like "<given name or page> - Google Chrome - <person> (<profile>)".
    public func matchesTitle(_ title: String) -> Bool {
        if title == window || title.hasPrefix(window + " - ") { return true }
        if title.hasSuffix("(\(profile))") { return true }
        return [" - ", " – "].contains { title.hasSuffix($0 + profile) }
    }
}

extension Profile: Decodable {
    private enum CodingKeys: String, CodingKey { case label, window, profile, dir, color }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            label: try c.decode(String.self, forKey: .label),
            window: try c.decodeIfPresent(String.self, forKey: .window),
            profile: try c.decodeIfPresent(String.self, forKey: .profile),
            dir: try c.decode(String.self, forKey: .dir),
            color: try c.decodeIfPresent(String.self, forKey: .color))
    }
}

/// Parses "#RRGGBB" (the "#" is optional) into 0…1 components.
public func rgb(hex: String) -> (r: Double, g: Double, b: Double)? {
    let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
    return (Double(v >> 16 & 0xFF) / 255, Double(v >> 8 & 0xFF) / 255, Double(v & 0xFF) / 255)
}
