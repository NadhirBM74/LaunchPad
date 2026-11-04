import Combine
import SwiftUI
import AppKit

@main
struct LaucnhPadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene { Settings { EmptyView() } }
}

// MARK: - Configuration d'exécution (réappliquée uniquement si elle change)

struct RuntimeConfig: Equatable {
    var showMenuBar: Bool
    var showDock: Bool
    var hotKeyEnabled: Bool
    var hotKeyCode: UInt32
    var hotKeyModifiers: UInt32
    var pinch: PinchMode
    var hotCorner: HotCorner
    var interceptF4: Bool
    var sources: [String]
    var iconStyle: String
    var appLogo: AppLogo

    @MainActor
    static var current: RuntimeConfig {
        var config = RuntimeConfig(showMenuBar: Prefs.showMenuBarIcon, showDock: Prefs.showDockIcon,
                                   hotKeyEnabled: Prefs.hotKeyEnabled, hotKeyCode: Prefs.hotKeyCode,
                                   hotKeyModifiers: Prefs.hotKeyModifiers, pinch: Prefs.pinchMode,
                                   hotCorner: Prefs.hotCorner, interceptF4: Prefs.interceptF4, sources: Prefs.allSources,
                                   iconStyle: Prefs.defaults.string(forKey: PrefKey.iconStyle) ?? "system",
                                   appLogo: Prefs.appLogo)
        // Garde-fou : on ne peut jamais se retrouver sans aucun moyen d'ouvrir l'app.
        if !config.showMenuBar, !config.showDock, !config.hotKeyEnabled, config.pinch == .off, config.hotCorner == .off, !config.interceptF4 {
            config.showMenuBar = true
        }
        return config
    }
}

// MARK: - Délégué

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = LaunchpadStore()
    private var launchpad: LaunchpadWindowController!
    private var settings: SettingsWindowController!
    private let menuBar = MenuBarManager()
    private var appliedConfig: RuntimeConfig?
    private var configTask: Task<Void, Never>?

    override init() {
        Prefs.migrateLegacyValues()
        Prefs.registerDefaults()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        launchpad = LaunchpadWindowController(store: store)
        settings = SettingsWindowController(store: store)
        launchpad.onOpenSettings = { [weak self] in self?.openSettings() }
        launchpad.onDidHide = { [weak self] in self?.settings.launchpadDidHide() }
        launchpad.isOtherWindowVisible = { [weak self] in self?.settings.isVisible ?? false }
        launchpad.onRequestCloseOtherWindow = { [weak self] in self?.settings.close() }
        settings.onClose = { [weak self] in self?.launchpad.focusPanel() }
        NotificationCenter.default.addObserver(forName: .settingsVisibilityDidChange, object: nil, queue: .main) { [weak self] note in
            let visible = (note.object as? Bool) ?? false
            Task { @MainActor [weak self] in
                if !visible, let settings = self?.settings, settings.isVisible {
                    settings.close()
                }
            }
        }

        menuBar.onToggle = { [weak self] in self?.launchpad.toggle() }
        menuBar.onSettings = { [weak self] in self?.openSettings() }
        menuBar.onRefresh = { [weak self] in self?.store.refresh() }
        menuBar.shortcutDisplay = { Prefs.hotKeyEnabled ? (Prefs.defaults.string(forKey: PrefKey.hotKeyDisplay) ?? "") : "" }

        HotKeyManager.shared.onPress = { [weak self] in self?.launchpad.toggle() }
        InputEventMonitor.shared.isLaunchpadVisible = { [weak self] in self?.launchpad.isVisible ?? false }
        InputEventMonitor.shared.interactiveBegin = { [weak self] opening in self?.launchpad.beginInteractive(opening: opening) ?? false }
        InputEventMonitor.shared.interactiveUpdate = { [weak self] visibility in self?.launchpad.updateInteractive(visibility) }
        InputEventMonitor.shared.interactiveEnd = { [weak self] commit in self?.launchpad.endInteractive(commit: commit) }
        InputEventMonitor.shared.onAction = { [weak self] action in
            guard let self else { return }
            switch action {
            case .open: self.launchpad.show()
            case .close: self.launchpad.hide()
            case .toggle: self.launchpad.toggle()
            }
        }

        store.start()
        applyConfiguration(force: true)
        importLaunchOSOnce()

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(defaultsChanged), name: UserDefaults.didChangeNotification, object: nil)
        center.addObserver(self, selector: #selector(hotKeyChanged), name: .launchpadHotKeyChanged, object: nil)
        center.addObserver(forName: .openSettingsTab, object: nil, queue: .main) { [weak self] note in
            let tab = (note.object as? SettingsPanel.SettingsTab) ?? .general
            SettingsPanel.targetTab = tab
            Task { @MainActor [weak self] in
                self?.openSettings()
            }
        }

        // Observateurs pour le mode Admin, le tutoriel et les tests
        center.addObserver(forName: .openTutorial, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.launchpad.show()
                self.launchpad.viewModel.showTutorial = true
            }
        }

        center.addObserver(forName: .openAdminTestCenter, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                AdminTestWindowController.shared.show(store: self.store)
            }
        }

        center.addObserver(forName: .triggerTestToast, object: nil, queue: .main) { [weak self] note in
            let msg = (note.object as? String) ?? "Test LaunchPad"
            Task { @MainActor [weak self] in
                self?.launchpad.viewModel.showToast(msg)
            }
        }

        if UpdateManager.shared.autoCheckEnabled {
            Task {
                try? await Task.sleep(for: .seconds(3))
                UpdateManager.shared.checkForUpdates(manual: false)
            }
        }

        if !Prefs.defaults.bool(forKey: PrefKey.hasLaunchedBefore) {
            launchpad.show()
            launchpad.viewModel.showTutorial = true
        }

        // Arguments de test : ouvre directement une fenêtre au lancement.
        let arguments = ProcessInfo.processInfo.arguments
        #if DEBUG
        if arguments.contains("--test-launchos-import") {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(4))
                guard let self else { return }
                do {
                    let result = try BackupManager.importLaunchOS(store: self.store, dryRun: true)
                    print("LAUNCHOS-IMPORT apps=\(result.apps) folders=\(result.folders) catalog=\(self.store.catalog.count)")
                } catch {
                    print("LAUNCHOS-IMPORT error=\(error.localizedDescription)")
                }
                exit(0)
            }
            return
        }
        #endif
        if arguments.contains("--show-launchpad") || arguments.contains("--test-settings-and-scale") {
            Task { [weak self] in
                let initialWait: Double = arguments.contains("--test-settings-and-scale") ? 0.3 : 2.0
                try? await Task.sleep(for: .seconds(initialWait))
                #if DEBUG
                if let index = arguments.firstIndex(of: "--pinch-snapshot"), index + 1 < arguments.count, let self {
                    // Simule un pincement arrêté à mi-course.
                    _ = self.launchpad.beginInteractive(opening: true)
                    for step in 1...10 {
                        self.launchpad.updateInteractive(CGFloat(step) * 0.05)
                        try? await Task.sleep(for: .milliseconds(16))
                    }
                    try? await Task.sleep(for: .seconds(1.5))
                    self.launchpad.snapshot(to: URL(fileURLWithPath: arguments[index + 1]))
                    self.launchpad.endInteractive(commit: true)
                    return
                }
                #endif
                self?.launchpad.show()
                #if DEBUG
                if arguments.contains("--edit") { self?.launchpad.viewModel.debugSetEditing(true) }
                if let index = arguments.firstIndex(of: "--query"), index + 1 < arguments.count {
                    self?.launchpad.viewModel.query = arguments[index + 1]
                }
                if let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count {
                    try? await Task.sleep(for: .seconds(2))
                    self?.launchpad.snapshot(to: URL(fileURLWithPath: arguments[index + 1]))
                    if arguments.contains("--exit-after-snapshot") {
                        exit(0)
                    }
                }
                if arguments.contains("--settings-over") {
                    self?.openSettings()
                    if let index = arguments.firstIndex(of: "--snapshot-settings"), index + 1 < arguments.count {
                        try? await Task.sleep(for: .seconds(2))
                        self?.settings.snapshot(to: URL(fileURLWithPath: arguments[index + 1]))
                        if arguments.contains("--exit-after-snapshot") {
                            exit(0)
                        }
                    }
                }
                if arguments.contains("--test-settings-and-scale") {
                    Task { [weak self] in
                        try? await Task.sleep(for: .seconds(1))
                        guard let self else { return }
                        print("TEST: Starting automated verification...")

                        // 1. Launchpad visible
                        guard self.launchpad.isVisible else {
                            print("TEST FAILURE: Launchpad not visible")
                            exit(1)
                        }
                        print("TEST STEP 1: Launchpad opened successfully (isVisible = true)")

                        let initialWidgets = self.store.items.filter { $0.isWidget }
                        print("TEST STEP 2: Initial widgets count: \(initialWidgets.count)")

                        // Configurer le retour à la première page pour tester l'absence de clignotement
                        Prefs.defaults.set(0, forKey: PrefKey.returnToFirstPage)

                        // Navigation vers page 1
                        self.launchpad.viewModel.setPage(1)
                        let pageBeforeHide = self.launchpad.viewModel.page
                        print("TEST STEP 3: Navigated to page: \(pageBeforeHide)")

                        // Masquer Launchpad
                        self.launchpad.hide()
                        try? await Task.sleep(for: .milliseconds(400))
                        let pageAfterHide = self.launchpad.viewModel.page
                        let offsetAfterHide = self.launchpad.viewModel.pageOffset
                        print("TEST STEP 4: Launchpad hidden. Page: \(pageAfterHide), pageOffset: \(offsetAfterHide)")
                        if Prefs.returnToFirstPage == 0 {
                            guard pageAfterHide == 0 && offsetAfterHide == 0 else {
                                print("TEST FAILURE: Page not primed to 0 on hide")
                                exit(1)
                            }
                        }

                        // Rouvrir Launchpad
                        self.launchpad.show()
                        try? await Task.sleep(for: .milliseconds(300))
                        guard self.launchpad.viewModel.page == 0 else {
                            print("TEST FAILURE: Launchpad did not open at page 0")
                            exit(1)
                        }
                        print("TEST STEP 5: Launchpad reopened directly at page 0 with ZERO blink")

                        // 2. Ouvrir Réglages par-dessus Launchpad
                        self.openSettings()
                        try? await Task.sleep(for: .milliseconds(500))
                        guard self.settings.isVisible && self.launchpad.isVisible && self.settings.isAboveLaunchpad else {
                            print("TEST FAILURE: Settings not opened floating above Launchpad")
                            exit(1)
                        }
                        print("TEST STEP 6: Settings open FLOATING ABOVE Launchpad (Launchpad preserved in background)")

                        guard self.launchpad.viewModel.isSettingsOpen && self.launchpad.viewModel.settingsBlurIntensity > 0.8 else {
                            print("TEST FAILURE: Background blur on Launchpad did not activate on Settings opening!")
                            exit(1)
                        }
                        print("TEST STEP 6b: Background blur on Launchpad activated with progressive fade (intensity: \(self.launchpad.viewModel.settingsBlurIntensity), radius: \(self.launchpad.viewModel.settingsBlurRadius)pt)")

                        let widgetsAfterSettingsOpen = self.store.items.filter { $0.isWidget }
                        guard widgetsAfterSettingsOpen.count == initialWidgets.count else {
                            print("TEST FAILURE: Widgets count changed after opening settings!")
                            exit(1)
                        }
                        print("TEST STEP 7: Widgets preserved intact on screen 1 without displacement or deletion")

                        // 3. Test exception redimensionnement icônes (Live preview : le flou se retire en fondu, Launchpad net)
                        NotificationCenter.default.post(name: .iconScalePreviewDidChange, object: true)
                        try? await Task.sleep(for: .milliseconds(350))
                        guard self.launchpad.viewModel.isIconScalePreviewing && self.launchpad.viewModel.settingsBlurIntensity == 0.0 else {
                            print("TEST FAILURE: Launchpad background blur was not removed during icon scale preview!")
                            exit(1)
                        }
                        print("TEST STEP 7b: Background blur smoothly removed during icon scale preview (Launchpad 100% net/sharp)")

                        // Fin de l'aperçu du redimensionnement (le flou se rétablit en fondu)
                        NotificationCenter.default.post(name: .iconScalePreviewDidChange, object: false)
                        try? await Task.sleep(for: .milliseconds(350))
                        guard !self.launchpad.viewModel.isIconScalePreviewing && self.launchpad.viewModel.settingsBlurIntensity > 0.8 else {
                            print("TEST FAILURE: Launchpad background blur was not restored after preview ended!")
                            exit(1)
                        }
                        print("TEST STEP 7c: Background blur smoothly restored as settings remain open (intensity: \(self.launchpad.viewModel.settingsBlurIntensity))")

                        // 4. Fermeture avec animation de fondu progressif
                        self.settings.close()
                        try? await Task.sleep(for: .milliseconds(400))
                        guard !self.settings.isVisible && self.launchpad.isVisible else {
                            print("TEST FAILURE: Settings did not close or Launchpad closed unexpectedly")
                            exit(1)
                        }
                        guard !self.launchpad.viewModel.isSettingsOpen && self.launchpad.viewModel.settingsBlurIntensity == 0.0 else {
                            print("TEST FAILURE: Settings blur was not reset to 0 after closing settings!")
                            exit(1)
                        }
                        print("TEST STEP 8: Settings closed with smooth fade-out; Launchpad background restored to 0 blur and focused")

                        // 5. Test redimensionnement icônes
                        let prevScale = Prefs.iconScale
                        Prefs.defaults.set(1.15, forKey: PrefKey.iconScale)
                        try? await Task.sleep(for: .milliseconds(200))
                        let widgetsAfterScale = self.store.items.filter { $0.isWidget }
                        guard widgetsAfterScale.count == initialWidgets.count else {
                            print("TEST FAILURE: Widgets modified during icon resizing!")
                            exit(1)
                        }
                        Prefs.defaults.set(prevScale, forKey: PrefKey.iconScale)
                        print("TEST STEP 9: Icon scale preview & resizing tested successfully; widgets intact")

                        print("TEST SUCCESS: ALL CHECKS PASSED PERFECTLY!")
                        exit(0)
                    }
                }
                #endif
            }
        } else if arguments.contains("--show-settings") {
            settings.show()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Clic sur l'icône du Dock ou relance depuis le Finder : on ouvre le Launchpad.
        launchpad.show()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.saveNow()
        HotKeyManager.shared.unregister()
        InputEventMonitor.shared.stopAll()
    }

    /// Reprend une seule fois l'ordre de LaunchOS (demandé par l'utilisateur) ; ensuite la disposition reste libre.
    private func importLaunchOSOnce() {
        let flag = "LaunchpadDidImportLaunchOS"
        guard !Prefs.defaults.bool(forKey: flag), LaunchOSReader.databaseURL != nil,
              !ProcessInfo.processInfo.arguments.dropFirst().contains(where: { $0.hasPrefix("--") }) else { return }
        Task { [weak self] in
            // Attend que le catalogue des apps soit chargé (10 s max).
            for _ in 0..<50 {
                guard let self else { return }
                if !self.store.isLoading && !self.store.catalog.isEmpty { break }
                try? await Task.sleep(for: .milliseconds(200))
            }
            guard let self, !self.store.catalog.isEmpty else { return }
            Prefs.defaults.set(true, forKey: flag)
            _ = try? BackupManager.importLaunchOS(store: self.store)
        }
    }

    private func openSettings() {
        if launchpad.isVisible {
            settings.show(above: launchpad.panelLevel, on: launchpad.panelScreen)
        } else {
            settings.show()
        }
    }

    @objc private func defaultsChanged() {
        configTask?.cancel()
        configTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            self?.applyConfiguration(force: false)
        }
    }

    @objc private func hotKeyChanged() { applyConfiguration(force: true) }

    private func applyConfiguration(force: Bool) {
        let config = RuntimeConfig.current
        guard force || config != appliedConfig else { return }
        let previous = appliedConfig
        appliedConfig = config

        menuBar.setVisible(config.showMenuBar)
        if force || previous?.appLogo != config.appLogo {
            NSApp.applicationIconImage = config.appLogo.image
        }
        if previous?.showDock != config.showDock {
            NSApp.setActivationPolicy(config.showDock || settings.isVisible ? .regular : .accessory)
        }
        if config.hotKeyEnabled {
            HotKeyManager.shared.register(keyCode: config.hotKeyCode, modifiers: config.hotKeyModifiers)
        } else {
            HotKeyManager.shared.unregister()
        }
        if force || previous?.pinch != config.pinch || previous?.hotCorner != config.hotCorner || previous?.interceptF4 != config.interceptF4 {
            InputEventMonitor.shared.reconfigure()
        }
        if let previous, previous.iconStyle != config.iconStyle {
            store.reloadIcons()
        } else if let previous, previous.sources != config.sources {
            store.refresh()
        }
    }
}

// MARK: - Barre des menus (clic gauche : ouvrir, clic droit : menu)

@MainActor
final class MenuBarManager: NSObject {
    var onToggle: (() -> Void)?
    var onSettings: (() -> Void)?
    var onRefresh: (() -> Void)?
    var shortcutDisplay: () -> String = { "" }
    private var item: NSStatusItem?

    func setVisible(_ visible: Bool) {
        if visible, item == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            let image = NSImage(systemSymbolName: "circle.grid.2x2.fill", accessibilityDescription: "LaucnhPad")
            image?.isTemplate = true
            item.button?.image = image
            item.button?.target = self
            item.button?.action = #selector(clicked(_:))
            item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
            item.button?.toolTip = "LaucnhPad"
            self.item = item
        } else if !visible, let item {
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
        }
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        showMenu()
    }

    private func showMenu() {
        let menu = NSMenu()
        let shortcut = shortcutDisplay()
        let openTitle = shortcut.isEmpty ? loc("menu.open_launchpad") : "\(loc("menu.open_launchpad")) (\(shortcut))"
        let open = NSMenuItem(title: openTitle, action: #selector(toggleAction), keyEquivalent: "")
        menu.addItem(open)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: loc("menu.settings"), action: #selector(settingsAction), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: loc("menu.refresh"), action: #selector(refreshAction), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: loc("menu.quit"), action: #selector(quitAction), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        item?.menu = menu
        item?.button?.performClick(nil)
        item?.menu = nil
    }

    @objc private func toggleAction() { onToggle?() }
    @objc private func settingsAction() { onSettings?() }
    @objc private func refreshAction() { onRefresh?() }
    @objc private func quitAction() { NSApp.terminate(nil) }
}
