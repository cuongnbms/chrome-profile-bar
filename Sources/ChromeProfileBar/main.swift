import AppKit
import ProfileBarCore
import ServiceManagement

@MainActor
final class AppController: NSObject, NSApplicationDelegate {
    private static let originKey = "panelOrigin"

    private var profiles: [Profile] = []
    private let chrome = Chrome()
    private let hotKeys = HotKeys()
    private let bar = BarView()
    private lazy var panel = BarPanel(bar: bar)
    private lazy var tracker = ActiveTracker(chrome: chrome) { [weak self] in self?.refreshActive() }

    func applicationDidFinishLaunching(_ notification: Notification) {
        bar.onClick = { [weak self] i, alt in alt ? self?.assign(i) : self?.switchTo(i) }
        bar.menuProvider = { [weak self] in self?.makeMenu() ?? NSMenu() }
        apply(loadProfiles() ?? [])
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { _ in
            MainActor.assumeIsolated { self.saveOrigin() }
        }
        panel.orderFrontRegardless()
        tracker.start()
        refreshActive()
    }

    // MARK: Profiles

    private func loadProfiles() -> [Profile]? {
        do {
            return try Config.load()
        } catch {
            alert("Cannot read \(Config.defaultURL.path)", String(describing: error))
            return nil
        }
    }

    private func apply(_ profiles: [Profile]) {
        self.profiles = profiles
        let size = bar.configure(profiles)
        let saved = (UserDefaults.standard.array(forKey: Self.originKey) as? [Double]).flatMap {
            $0.count == 2 ? CGPoint(x: $0[0], y: $0[1]) : nil
        }
        let origin = placeOnScreen(saved, size: size, screens: NSScreen.screens.map(\.frame))
            ?? defaultOrigin(size: size, visibleFrame: (NSScreen.main ?? NSScreen.screens[0]).visibleFrame)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)

        hotKeys.unregisterAll()
        hotKeys.register(keyCode: HotKeys.keyP, modifiers: HotKeys.ctrlAlt) { [weak self] in self?.toggle() }
        for (i, key) in HotKeys.digitKeyCodes.prefix(profiles.count).enumerated() {
            hotKeys.register(keyCode: key, modifiers: HotKeys.ctrlAlt) { [weak self] in self?.switchTo(i) }
        }
    }

    private func saveOrigin() {
        UserDefaults.standard.set([panel.frame.origin.x, panel.frame.origin.y], forKey: Self.originKey)
    }

    // MARK: Actions

    /// Focus the profile's window, or open a new one if none exists.
    private func switchTo(_ i: Int) {
        guard profiles.indices.contains(i) else { return }
        let p = profiles[i]
        if chrome.focus(windowNamed: p.window) {
            log.info("switch \(p.label, privacy: .public): focused by window name")
            refreshActive()
            return
        }
        if let pid = chrome.pid, WindowTitles.isTrusted,
           let w = WindowTitles.windows(pid: pid).first(where: { p.matchesTitle(WindowTitles.title($0)) }) {
            log.info("switch \(p.label, privacy: .public): raised by title")
            WindowTitles.raise(w)
            chrome.activate()
            refreshActive()
            return
        }
        log.info("switch \(p.label, privacy: .public): opening --profile-directory=\(p.dir, privacy: .public)")
        chrome.openProfile(dir: p.dir)
        // Name the new window so the next click lands on it.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            if self.chrome.frontGivenName() == "" {
                log.info("naming new window \(p.window, privacy: .public): \(self.chrome.nameFrontWindow(p.window))")
            }
            self.refreshActive()
        }
    }

    /// Name the frontmost Chrome window after the profile.
    private func assign(_ i: Int) {
        guard profiles.indices.contains(i) else { return }
        let ok = chrome.nameFrontWindow(profiles[i].window)
        log.info("assign \(self.profiles[i].window, privacy: .public): \(ok)")
        if ok { refreshActive() }
    }

    private func toggle() {
        if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
        log.info("toggle: visible=\(self.panel.isVisible)")
    }

    private func refreshActive() {
        let i = detectActive()
        if i != bar.activeIndex { log.info("active: \(i.map { self.profiles[$0].label } ?? "none", privacy: .public)") }
        bar.activeIndex = i
    }

    private func detectActive() -> Int? {
        guard let pid = chrome.pid else { return nil }
        if let given = chrome.frontGivenName(), let i = profiles.firstIndex(where: { $0.window == given }) {
            return i
        }
        guard WindowTitles.isTrusted, let title = WindowTitles.focusedWindowTitle(pid: pid) else { return nil }
        return profiles.firstIndex { $0.matchesTitle(title) }
    }

    // MARK: Menu

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector, on: Bool = false) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.state = on ? .on : .off
            menu.addItem(item)
        }
        add("Launch at Login", #selector(toggleLogin), on: SMAppService.mainApp.status == .enabled)
        add("Match Window Titles (Accessibility)…", #selector(accessibility), on: WindowTitles.isTrusted)
        menu.addItem(.separator())
        add("Open Config", #selector(openConfig))
        add("Reload Config", #selector(reloadConfig))
        menu.addItem(.separator())
        add("Quit Chrome Profile Bar", #selector(quit))
        return menu
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            alert("Launch at Login", String(describing: error))
        }
    }

    @objc private func accessibility() {
        if WindowTitles.isTrusted {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        } else {
            WindowTitles.requestTrust()
        }
    }

    @objc private func openConfig() {
        _ = loadProfiles()  // creates the sample if missing
        NSWorkspace.shared.open(Config.defaultURL)
    }

    @objc private func reloadConfig() {
        if let ps = loadProfiles() {
            apply(ps)
            refreshActive()
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    private func alert(_ message: String, _ info: String) {
        log.error("\(message, privacy: .public): \(info, privacy: .public)")
        NSApp.activate()
        let a = NSAlert()
        a.messageText = message
        a.informativeText = info
        a.runModal()
    }
}

let app = NSApplication.shared
let controller = AppController()
app.delegate = controller
app.setActivationPolicy(.accessory)
app.run()
