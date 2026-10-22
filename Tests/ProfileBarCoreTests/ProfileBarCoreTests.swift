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

@Suite struct DockTests {
    let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let band = DockBand(minY: 4, height: 53)
    let size = CGSize(width: 400, height: 53)

    @Test func bandFromVisibleFrame() {
        #expect(bottomDockBand(frame: screen, visibleFrame: CGRect(x: 0, y: 59, width: 1920, height: 991)) == band)
    }

    @Test func noBandWithoutBottomDock() {
        #expect(bottomDockBand(frame: screen, visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1050)) == nil)
        // Dock on the left: the strip is horizontal, not at the bottom.
        #expect(bottomDockBand(frame: screen, visibleFrame: CGRect(x: 60, y: 0, width: 1860, height: 1050)) == nil)
        // A secondary screen below the menu bar screen keeps its own origin.
        let side = CGRect(x: 1920, y: -200, width: 1920, height: 1080)
        #expect(bottomDockBand(frame: side, visibleFrame: side) == nil)
    }

    @Test func heightFollowsTheDockWithinLimits() {
        #expect(dockHeight(tileSize: 39) == 53)
        #expect(barHeight(dockHeight: 53) == 53)
        #expect(barHeight(dockHeight: nil) == 36)
        #expect(barHeight(dockHeight: 20) == 36)
        #expect(barHeight(dockHeight: 142) == 64)
    }

    @Test func sitsLeftOfTheDock() {
        #expect(dockedOrigin(size: size, band: band, dockMinX: 452, fallbackX: 0, screen: screen) == CGPoint(x: 44, y: 4))
    }

    @Test func centersShorterBarOnTheBand() {
        let big = DockBand(minY: 4, height: 142)
        let o = dockedOrigin(size: CGSize(width: 400, height: 64), band: big, dockMinX: 900, fallbackX: 0, screen: screen)
        #expect(o == CGPoint(x: 492, y: 43))
    }

    @Test func keepsFallbackXWithoutDockFrame() {
        #expect(dockedOrigin(size: size, band: band, dockMinX: nil, fallbackX: 41, screen: screen) == CGPoint(x: 41, y: 4))
    }

    @Test func clampsWhenTheDockLeavesNoRoom() {
        #expect(dockedOrigin(size: size, band: band, dockMinX: 200, fallbackX: 0, screen: screen) == CGPoint(x: 0, y: 4))
    }
}

@Suite struct ProcessArgumentsTests {
    @Test func readsOwnArguments() throws {
        let args = try #require(processArguments(getpid()))
        #expect(args == CommandLine.arguments)
    }

    @Test func nilForMissingProcess() { #expect(processArguments(-1) == nil) }
}
