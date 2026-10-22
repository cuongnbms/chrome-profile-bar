import AppKit
import ProfileBarCore
import ServiceManagement

@MainActor
final class AppController: NSObject, NSApplicationDelegate {
    private static let originKey = "panelOrigin", attachKey = "attachToDock", labelsKey = "showLabels"
    /// Left edge of the Dock's glass relative to its AX icon list.
    private static let dockListInset: CGFloat = 0

    private var profiles: [Profile] = []
    private var avatars: [NSImage?] = []
    private var avatarDates: [Date?] = []
    private let chrome = Chrome()
    private let hotKeys = HotKeys()
    private let bar = BarView()
    private lazy var panel = BarPanel(bar: bar)
    private lazy var tracker = ActiveTracker(chrome: chrome) { [weak self] in self?.refreshActive() }
    private var placedOrigin: NSPoint?
    private var placeTask: Task<Void, Never>?
    private var dropTask: Task<Void, Never>?

    /// Keep the bar next to the Dock; dragging it away turns this off.
    private var attached: Bool {
        get { UserDefaults.standard.object(forKey: Self.attachKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.attachKey) }
    }

    /// Labelled buttons instead of Dock-like tiles.
    private var showLabels: Bool {
        get { UserDefaults.standard.bool(forKey: Self.labelsKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.labelsKey) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        bar.onClick = { [weak self] i, alt in alt ? self?.assign(i) : self?.switchTo(i) }
        bar.menuProvider = { [weak self] in self?.makeMenu() ?? NSMenu() }
        bar.badge = Chrome.icon
        apply(loadProfiles() ?? [])
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { _ in
            MainActor.assumeIsolated { self.moved() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil,
                                               queue: .main) { _ in
            MainActor.assumeIsolated { self.placeSoon() }
        }
        // Apps with a Dock icon change the Dock's width when they launch or quit.
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { n in
                let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard app?.activationPolicy == .regular else { return }
                MainActor.assumeIsolated { self.placeSoon() }
            }
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
        loadAvatars()
        place()

        hotKeys.unregisterAll()
        hotKeys.register(keyCode: HotKeys.keyP, modifiers: HotKeys.ctrlAlt) { [weak self] in self?.toggle() }
        for (i, key) in HotKeys.digitKeyCodes.prefix(profiles.count).enumerated() {
            hotKeys.register(keyCode: key, modifiers: HotKeys.ctrlAlt) { [weak self] in self?.switchTo(i) }
        }
    }

    // MARK: Placement

    /// As tall as the Dock; left of it when attached, else at the saved origin.
    private func place() {
        let screens = NSScreen.screens
        let docked = dockedScreen()
        let size = bar.configure(profiles, avatars: avatars, labels: showLabels,
                                 height: barHeight(dockHeight: docked?.band.height ?? Dock.tileSize.map(dockHeight)))
        panel.setCornerRadius(bar.cornerRadius)

        let saved = (UserDefaults.standard.array(forKey: Self.originKey) as? [Double]).flatMap {
            $0.count == 2 ? CGPoint(x: $0[0], y: $0[1]) : nil
        }
        var origin = placeOnScreen(saved, size: size, screens: screens.map(\.frame))
        if attached, let docked {
            let list = Dock.listFrame()
            origin = dockedOrigin(size: size, band: docked.band, dockMinX: list.map { $0.minX - Self.dockListInset },
                                  fallbackX: origin?.x ?? docked.screen.minX, screen: docked.screen)
            log.info("dock band \(String(describing: docked.band), privacy: .public) list \(String(describing: list), privacy: .public) ax \(WindowTitles.isTrusted)")
        }
        let frame = NSRect(origin: origin ?? defaultOrigin(size: size, visibleFrame: (NSScreen.main ?? screens[0]).visibleFrame),
                           size: size)
        guard frame != panel.frame else { return }
        placedOrigin = frame.origin
        panel.setFrame(frame, display: true)
    }

    /// The screen with a visible bottom Dock, and the Dock's band on it.
    private func dockedScreen() -> (screen: CGRect, band: DockBand)? {
        NSScreen.screens.lazy.compactMap { s in
            bottomDockBand(frame: s.frame, visibleFrame: s.visibleFrame).map { (screen: s.frame, band: $0) }
        }.first
    }

    /// The Dock animates its width, so wait for it to settle.
    private func placeSoon() {
        placeTask?.cancel()
        placeTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.6))
            guard !Task.isCancelled else { return }
            self.place()
        }
    }

    private func moved() {
        guard panel.frame.origin != placedOrigin else { return }  // our own setFrame
        UserDefaults.standard.set([panel.frame.origin.x, panel.frame.origin.y], forKey: Self.originKey)
        dropTask?.cancel()
        dropTask = Task { @MainActor in
            while NSEvent.pressedMouseButtons != 0 {
                try? await Task.sleep(for: .milliseconds(100))
                if Task.isCancelled { return }
            }
            self.dropped()
        }
    }

    /// Dropped level with the Dock: stay attached (at the new x if the Dock's frame is unknown);
    /// anywhere else: detach.
    private func dropped() {
        let near = dockedScreen().map { abs(panel.frame.midY - $0.band.minY - $0.band.height / 2) < $0.band.height } ?? false
        log.info("dropped at \(String(describing: self.panel.frame.origin), privacy: .public), attached: \(near)")
        attached = near
        if near { place() }
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
        if panel.isVisible {
            bar.clearHover()
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
        log.info("toggle: visible=\(self.panel.isVisible)")
    }

    private func loadAvatars() {
        avatarDates = profiles.map { Self.modified(Chrome.avatarURL(dir: $0.dir)) }
        avatars = profiles.map { NSImage(contentsOf: Chrome.avatarURL(dir: $0.dir)) }
    }

    /// Picks up pictures Chrome has re-downloaded since they were loaded.
    private func reloadAvatarsIfChanged() {
        guard profiles.map({ Self.modified(Chrome.avatarURL(dir: $0.dir)) }) != avatarDates else { return }
        log.info("profile pictures changed, reloading")
        loadAvatars()
        place()
    }

    private static func modified(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private func refreshActive() {
        reloadAvatarsIfChanged()
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
        add("Show Labels", #selector(toggleLabels), on: showLabels)
        add("Attach to Dock", #selector(toggleAttach), on: attached)
        add("Launch at Login", #selector(toggleLogin), on: SMAppService.mainApp.status == .enabled)
        add("Match Window Titles (Accessibility)…", #selector(accessibility), on: WindowTitles.isTrusted)
        menu.addItem(.separator())
        add("Open Config", #selector(openConfig))
        add("Reload Config", #selector(reloadConfig))
        menu.addItem(.separator())
        add("Quit Chrome Profile Bar", #selector(quit))
        return menu
    }

    @objc private func toggleLabels() {
        showLabels.toggle()
        place()
    }

    @objc private func toggleAttach() {
        attached.toggle()
        place()
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
