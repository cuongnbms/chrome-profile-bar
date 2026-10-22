import Foundation

public enum Config {
    public static let defaultURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/chrome-profile-bar/profiles.json")

    public static let sample = """
        [
          { "label": "Main", "window": "Main", "profile": "Main", "dir": "Default", "color": "#4285F4" },
          { "label": "Work", "dir": "Profile 1", "color": "#0F9D58" }
        ]

        """

    public static func decode(_ data: Data) throws -> [Profile] {
        try JSONDecoder().decode([Profile].self, from: data)
    }

    /// Reads the profiles, writing `sample` first if the file does not exist yet.
    public static func load(from url: URL = defaultURL) throws -> [Profile] {
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(sample.utf8).write(to: url)
        }
        return try decode(Data(contentsOf: url))
    }
}
