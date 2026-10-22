import AppKit

/// Calls `onChange` when the focused window of the user's Chrome may have changed:
/// on Chrome activation/termination, and — only while Chrome is frontmost — when the number
/// of its top window changes (checked once a second via CGWindowList, no Apple Events).
@MainActor
final class ActiveTracker {
    private let chrome: Chrome
    private let onChange: () -> Void
    private var timer: Timer?
    private var lastWindow: Int?

    init(chrome: Chrome, onChange: @escaping () -> Void) {
        self.chrome = chrome
        self.onChange = onChange
    }

    func start() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { n in
            let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self.activated(app) }
        }
        nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { n in
            let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == Chrome.bundleID else { return }
            MainActor.assumeIsolated { self.onChange() }
        }
        activated(NSWorkspace.shared.frontmostApplication)
    }

    private func activated(_ app: NSRunningApplication?) {
        guard let app, chrome.isUserChrome(app) else {
            timer?.invalidate()
            timer = nil
            return
        }
        lastWindow = chrome.frontWindowNumber()
        onChange()
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1, repeats: true) { _ in MainActor.assumeIsolated { self.tick() } }
        t.tolerance = 0.3
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        let n = chrome.frontWindowNumber()
        guard n != lastWindow else { return }
        lastWindow = n
        onChange()
    }
}
