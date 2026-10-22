import AppKit
import ProfileBarCore
import os

let log = Logger(subsystem: "dev.cuongnb.ChromeProfileBar", category: "app")

/// The user's Chrome, driven by Apple Events sent to its pid. Several processes can share
/// the bundle ID (e.g. a browser started by chrome-devtools-mcp), so automation instances
/// are skipped instead of trusting the bundle ID.
@MainActor
final class Chrome {
    nonisolated static let bundleID = "com.google.Chrome"

    private var automationPids: [pid_t: Bool] = [:]  // pid -> launched with --enable-automation
    private var cached: NSRunningApplication?

    var app: NSRunningApplication? {
        if let c = cached, !c.isTerminated { return c }
        let all = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID)
        cached = all.first { !isAutomation($0.processIdentifier) }
        log.info("Chrome pids \(all.map(\.processIdentifier), privacy: .public) -> user \(String(describing: self.cached?.processIdentifier), privacy: .public)")
        return cached
    }

    var pid: pid_t? { app?.processIdentifier }

    /// Chrome's app icon, for badging the profile tiles.
    nonisolated static var icon: NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }

    /// The profile's Google account picture, if Chrome has saved one.
    nonisolated static func avatar(dir: String) -> NSImage? {
        NSImage(contentsOf: FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Google/Chrome/\(dir)/Google Profile Picture.png"))
    }

    func isUserChrome(_ app: NSRunningApplication) -> Bool {
        app.bundleIdentifier == Self.bundleID && !isAutomation(app.processIdentifier)
    }

    private func isAutomation(_ pid: pid_t) -> Bool {
        if let known = automationPids[pid] { return known }
        let result = processArguments(pid)?.contains("--enable-automation") ?? false
        automationPids[pid] = result
        return result
    }

    private var target: AppleEventTarget? { pid.map(AppleEventTarget.init) }

    // MARK: Windows

    /// (id, given name) of every window, front to back.
    private func windows(_ t: AppleEventTarget) throws -> [(id: String, name: String)] {
        let ids = try t.get(AppleEventTarget.property("ID  ", of: AppleEventTarget.every("cwin")))?.strings ?? []
        let names = try t.get(AppleEventTarget.property("GNam", of: AppleEventTarget.every("cwin")))?.strings ?? []
        guard ids.count == names.count else { return [] }  // a window opened/closed in between
        return Array(zip(ids, names)).map { (id: $0.0, name: $0.1) }
    }

    func focus(windowNamed name: String) -> Bool {
        guard let t = target else { return false }
        do {
            guard let w = try windows(t).first(where: { $0.name == name }) else { return false }
            let win = AppleEventTarget.element("cwin", id: w.id)
            try t.set(AppleEventTarget.property("pmnd", of: win), to: NSAppleEventDescriptor(boolean: false))
            try t.set(AppleEventTarget.property("pidx", of: win), to: NSAppleEventDescriptor(int32: 1))
            try t.activate()
            return true
        } catch {
            log.error("focus(\(name, privacy: .public)): \(String(describing: error), privacy: .public)")
            return false
        }
    }

    func frontGivenName() -> String? {
        guard let t = target else { return nil }
        let front = AppleEventTarget.element("cwin", index: 1)
        return try? t.get(AppleEventTarget.property("GNam", of: front))?.stringValue
    }

    /// Names the frontmost window; clears the name from other windows so it stays unique.
    func nameFrontWindow(_ name: String) -> Bool {
        guard let t = target else { return false }
        do {
            let ws = try windows(t)
            guard let front = ws.first else { return false }
            for w in ws.dropFirst() where w.name == name {
                try t.set(AppleEventTarget.property("GNam", of: AppleEventTarget.element("cwin", id: w.id)),
                          to: NSAppleEventDescriptor(string: ""))
            }
            try t.set(AppleEventTarget.property("GNam", of: AppleEventTarget.element("cwin", id: front.id)),
                      to: NSAppleEventDescriptor(string: name))
            return true
        } catch {
            log.error("nameFrontWindow(\(name, privacy: .public)): \(String(describing: error), privacy: .public)")
            return false
        }
    }

    func activate() {
        guard let t = target else { return }
        try? t.activate()
    }

    func openProfile(dir: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-na", "Google Chrome", "--args", "--profile-directory=\(dir)"]
        do { try p.run() } catch { log.error("open: \(String(describing: error), privacy: .public)") }
    }

    /// Number of the frontmost normal-layer window of the user's Chrome. Uses only window
    /// numbers and owners, which need no permission (titles would need Screen Recording).
    func frontWindowNumber() -> Int? {
        guard let pid,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        return list.first {
            $0[kCGWindowOwnerPID as String] as? Int == Int(pid) && $0[kCGWindowLayer as String] as? Int == 0
        }?[kCGWindowNumber as String] as? Int
    }
}
