import CoreGraphics
import Foundation
import Testing

@testable import ProfileBarCore

@Suite struct ConfigTests {
    @Test func defaultsFallBackToLabel() throws {
        let ps = try Config.decode(Data(#"[{ "label": "Work", "dir": "Profile 1" }]"#.utf8))
        #expect(ps == [Profile(label: "Work", window: "Work", profile: "Work", dir: "Profile 1", color: "#4285F4")])
    }

    @Test func explicitValuesWin() throws {
        let json = ##"[{ "label": "Work", "window": "work", "profile": "example.com", "dir": "Profile 2", "color": "#0F9D58" }]"##
        let p = try #require(try Config.decode(Data(json.utf8)).first)
        #expect(p.window == "work")
        #expect(p.profile == "example.com")
        #expect(p.color == "#0F9D58")
    }

    @Test func missingDirIsAnError() {
        #expect(throws: DecodingError.self) { try Config.decode(Data(#"[{ "label": "X" }]"#.utf8)) }
    }

    @Test func sampleIsValid() throws {
        #expect(try Config.decode(Data(Config.sample.utf8)).count == 2)
    }

    @Test func loadCreatesSampleWhenMissing() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("profiles.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(try Config.load(from: url).count == 2)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }
}

@Suite struct TitleMatchTests {
    let p = Profile(label: "Work", window: "work", profile: "example.com", dir: "Profile 2")

    @Test(arguments: [
        "work",
        "work - Google Chrome",
        "Inbox - Google Chrome - Alex (example.com)",
        "Inbox - example.com",
        "Inbox – example.com",
    ])
    func matches(_ title: String) { #expect(p.matchesTitle(title)) }

    @Test(arguments: ["", "workX", "Inbox - Google Chrome - Alex (Main)", "example.com docs"])
    func doesNotMatch(_ title: String) { #expect(!p.matchesTitle(title)) }
}

@Suite struct HexTests {
    @Test func parses() throws {
        let c = try #require(rgb(hex: "#FF8000"))
        #expect(c.r == 1 && c.b == 0 && abs(c.g - 128.0 / 255) < 1e-9)
        #expect(rgb(hex: "00ACC1") != nil)
    }

    @Test(arguments: ["", "#FFF", "#GGGGGG", "#1234567"])
    func rejects(_ s: String) { #expect(rgb(hex: s) == nil) }
}

@Suite struct PlacementTests {
    let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: 1440, y: 0, width: 1920, height: 1080)]
    let size = CGSize(width: 400, height: 40)

    @Test func nilWhenNothingSaved() { #expect(placeOnScreen(nil, size: size, screens: screens) == nil) }

    @Test func keepsVisiblePosition() {
        #expect(placeOnScreen(CGPoint(x: 100, y: 100), size: size, screens: screens) == CGPoint(x: 100, y: 100))
    }

    @Test func clampsToTheScreenItIsOn() {
        #expect(placeOnScreen(CGPoint(x: 1300, y: 890), size: size, screens: screens) == CGPoint(x: 1040, y: 860))
    }

    @Test func nilWhenOffAllScreens() {
        #expect(placeOnScreen(CGPoint(x: -500, y: 100), size: size, screens: screens) == nil)
        #expect(placeOnScreen(CGPoint(x: 3360, y: 10), size: size, screens: screens) == nil)
    }

    @Test func defaultIsBottomCenter() {
        let f = CGRect(x: 0, y: 70, width: 1440, height: 800)
        #expect(defaultOrigin(size: size, visibleFrame: f) == CGPoint(x: 520, y: 78))
    }
}

@Suite struct ProcessArgumentsTests {
    @Test func readsOwnArguments() throws {
        let args = try #require(processArguments(getpid()))
        #expect(args == CommandLine.arguments)
    }

    @Test func nilForMissingProcess() { #expect(processArguments(-1) == nil) }
}
