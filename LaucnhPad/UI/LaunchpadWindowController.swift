import Combine
import SwiftUI
import AppKit

final class LaunchpadPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Vue hôte qui laisse le tout premier clic atteindre directement les contrôles
/// (boutons du widget musique, barre de lecture…) même si le panneau vient d'être activé.
final class LaunchpadHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // Contournement d'un crash du compilateur Swift 6.3 en Release : le deinit
    // synthétisé d'une sous-classe générique de NSHostingView fait planter
    // EarlyPerfInliner (isCallerAndCalleeLayoutConstraintsCompatible).
    // Un deinit explicite non isolé évite le passage problématique.
    nonisolated deinit {}
}

@MainActor
final class LaunchpadWindowController: NSObject {
    let store: LaunchpadStore
    let viewModel: LaunchpadViewModel
    let wallpaper = WallpaperProvider()
    var onOpenSettings: (() -> Void)?
    var onDidHide: (() -> Void)?
    var isOtherWindowVisible: () -> Bool = { false }
    var onRequestCloseOtherWindow: (() -> Void)?

    /// Niveau et écran du panneau (pour ouvrir les réglages par-dessus).
    var panelLevel: NSWindow.Level { panel.level }
    var panelScreen: NSScreen? { panel.screen }

    /// Rend le clavier au Launchpad (après fermeture des réglages par exemple).
    func focusPanel() {
        guard isVisible else { return }
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        viewModel.focusSearch()
    }

    private let panel: LaunchpadPanel
    private var monitors: [Any] = []
    private(set) var isVisible = false
    private var lastHidden = Date.distantPast
    private var hideTask: Task<Void, Never>?

    init(store: LaunchpadStore) {
        self.store = store
        viewModel = LaunchpadViewModel(store: store)
        panel = LaunchpadPanel(contentRect: NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900),
                               styleMask: [.borderless], backing: .buffered, defer: false)
        super.init()

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Au-dessus du Dock et de la barre des menus, mais sous les menus contextuels.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.animationBehavior = .none
        panel.acceptsMouseMovedEvents = true

        let host = LaunchpadHostingView(rootView: LaunchpadRootView(vm: viewModel, store: store, wallpaper: wallpaper))
        host.sizingOptions = []
        panel.contentView = host

        viewModel.onClose = { [weak self] launched in self?.hide(launchedApp: launched) }
        viewModel.onOpenSettings = { [weak self] in self?.onOpenSettings?() }
        viewModel.onBiometricAuthChange = { [weak self] isAuthenticating in
            guard let self else { return }
            if isAuthenticating {
                // Abaisser temporairement le niveau du panneau pour que la boîte de dialogue système
                // Touch ID / mot de passe (CoreAuthUI) s'affiche nettement au premier plan sans être masquée.
                self.panel.level = .floating
            } else {
                self.panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)
                self.focusPanel()
            }
        }

        installMonitors()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(appDidResignActive), name: NSApplication.didResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        center.addObserver(self, selector: #selector(defaultsChanged), name: UserDefaults.didChangeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(systemDidWake), name: NSWorkspace.didWakeNotification, object: nil)
    }

    // MARK: Affichage

    func toggle() { isVisible ? hide() : show() }

    #if DEBUG
    /// Capture du contenu du panneau (débogage uniquement).
    func snapshot(to url: URL) {
        guard let view = panel.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
    #endif

    func show() { present(interactive: false) }

    /// - Parameter interactive: true = la progression sera pilotée au doigt (pincement), pas d'animation automatique.
    private func present(interactive: Bool) {
        hideTask?.cancel()
        guard !isVisible else { return }
        let screen = targetScreen()
        isVisible = true
        viewModel.setPanelVisible(true)
        NotificationCenter.default.post(name: .launchpadVisibilityDidChange, object: true)

        let delay = Prefs.returnToFirstPage
        let resetPage = delay == 0 || (delay > 0 && Date().timeIntervalSince(lastHidden) > TimeInterval(delay))
        let wasOnScreen = panel.isVisible
        viewModel.prepareForShow(topInset: topInset(for: screen), resetPage: resetPage)
        applyLayout(on: screen, display: false)
        wallpaper.update(for: screen)
        store.refreshIfStale()

        // Réouverture pendant l'animation de fermeture : on repart de l'état courant (pas de saut).
        if !wasOnScreen { viewModel.setPresentation(0) }
        panel.alphaValue = 1
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        applyDockOption()
        if !interactive { viewModel.setAppeared(true) }
    }

    func hide(launchedApp: Bool = false) {
        guard isVisible else { return }
        isVisible = false
        NotificationCenter.default.post(name: .launchpadVisibilityDidChange, object: false)
        interactiveOpening = nil
        lastHidden = Date()
        viewModel.setAppeared(false)
        onDidHide?()
        restoreDock()
        let duration = Prefs.reduceMotion ? 0 : LaunchpadViewModel.hideDuration
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            if duration > 0 { try? await Task.sleep(for: .seconds(duration)) }
            guard let self, !Task.isCancelled, !self.isVisible else { return }
            self.panel.orderOut(nil)
            self.viewModel.setPanelVisible(false)
            self.viewModel.didHide()
            // Rend la main à l'app précédente si aucune app n'a été lancée.
            if !launchedApp, !self.isOtherWindowVisible() { NSApp.hide(nil) }
        }
    }

    // MARK: Pincement interactif (l'animation suit les doigts, comme le Launchpad de macOS)

    private var interactiveOpening: Bool?

    /// Début du geste : true si le Launchpad accepte de suivre le doigt.
    func beginInteractive(opening: Bool) -> Bool {
        if opening {
            guard !isVisible else { return false }
            present(interactive: true)
        } else {
            guard isVisible, !viewModel.isPresentingModal, viewModel.drag == nil else { return false }
        }
        interactiveOpening = opening
        return true
    }

    /// Visibilité suivie au doigt (0 = caché, 1 = affiché).
    func updateInteractive(_ visibility: CGFloat) {
        guard interactiveOpening != nil, isVisible else { return }
        viewModel.setPresentation(Double(visibility))
    }

    /// Fin du geste : on termine l'ouverture/fermeture ou on revient en arrière, en douceur depuis la position du doigt.
    func endInteractive(commit: Bool) {
        guard let opening = interactiveOpening else { return }
        interactiveOpening = nil
        guard isVisible else { return }
        if opening == commit {
            viewModel.setAppeared(true)      // ouverture confirmée, ou fermeture annulée
        } else {
            hide()                           // fermeture confirmée, ou ouverture annulée
        }
    }

    // MARK: Mode d'affichage (plein écran / fenêtre, comme LaunchOS)

    private var appliedMode: DisplayMode?

    private func topInset(for screen: NSScreen) -> CGFloat {
        Prefs.displayMode == .window ? 0 : screen.safeAreaInsets.top
    }

    /// Rectangle de la « fenêtre » (coordonnées de la vue, origine en haut à gauche), nil en plein écran.
    private func windowRect(on screen: NSScreen) -> CGRect? {
        guard Prefs.displayMode == .window else { return nil }
        let frame = screen.frame, visible = screen.visibleFrame
        let width = min(visible.width * 0.82, 1400)
        let height = min(visible.height * 0.84, 920)
        let midX = visible.midX - frame.minX
        let midY = frame.maxY - visible.midY
        return CGRect(x: midX - width / 2, y: midY - height / 2, width: width, height: height).integral
    }

    private func applyLayout(on screen: NSScreen, display: Bool) {
        appliedMode = Prefs.displayMode
        viewModel.updateWindowRect(windowRect(on: screen))
        // Le panneau reste toujours plein écran : le redimensionner fait boucler la mise en page de SwiftUI.
        if panel.frame != screen.frame { panel.setFrame(screen.frame, display: display) }
    }

    /// Masque le Dock pendant l'affichage (utile en mode fenêtre ; en plein écran le panneau le recouvre déjà).
    private func applyDockOption() {
        let wanted: NSApplication.PresentationOptions = Prefs.hideDock && Prefs.displayMode == .window ? [.autoHideDock] : []
        if NSApp.presentationOptions != wanted { NSApp.presentationOptions = wanted }
    }

    private func restoreDock() {
        if !NSApp.presentationOptions.isEmpty { NSApp.presentationOptions = [] }
    }

    @objc private func defaultsChanged() {
        Task { @MainActor [weak self] in
            guard let self, self.isVisible else { return }
            if self.appliedMode != Prefs.displayMode {
                let screen = self.panel.screen ?? self.targetScreen()
                self.viewModel.updateTopInset(self.topInset(for: screen))
                self.applyLayout(on: screen, display: true)
            }
            self.applyDockOption()
        }
    }

    private func targetScreen() -> NSScreen {
        let screens = NSScreen.screens
        guard let fallback = NSScreen.main ?? screens.first ?? panel.screen else {
            // Écran de secours virtuel si le WindowServer est en pleine reconfiguration
            return panel.screen ?? NSScreen()
        }
        switch Prefs.screenTarget {
        case .cursor:
            let location = NSEvent.mouseLocation
            return screens.first { NSMouseInRect(location, $0.frame, false) } ?? fallback
        case .main:
            return screens.first ?? fallback
        case .active:
            return fallback
        }
    }

    @objc private func appDidResignActive() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            // Ne pas masquer le Launchpad si une authentification Touch ID est en cours
            guard !self.viewModel.isAuthenticatingBiometrics else { return }
            if self.isVisible { self.hide(launchedApp: true) }
        }
    }

    @objc private func screensChanged() {
        Task { @MainActor [weak self] in
            guard let self, self.isVisible else { return }
            let screen = self.targetScreen()
            self.viewModel.updateTopInset(self.topInset(for: screen))
            self.applyLayout(on: screen, display: true)
            self.wallpaper.update(for: screen)
        }
    }

    @objc private func systemDidWake() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let screen = self.targetScreen()
            self.viewModel.updateTopInset(self.topInset(for: screen))
            if self.isVisible {
                self.applyLayout(on: screen, display: true)
                self.wallpaper.update(for: screen)
            }
        }
    }

    // MARK: Clavier, modificateurs et défilement

    private func installMonitors() {
        let monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .scrollWheel]) { [weak self] event in
            guard let self, self.isVisible else { return event }
            switch event.type {
            case .keyDown:
                guard event.window === self.panel else { return event }
                if event.keyCode == 53 && self.isOtherWindowVisible() {
                    self.onRequestCloseOtherWindow?()
                    return nil
                }
                return self.viewModel.handleKeyDown(event) ? nil : event
            case .flagsChanged:
                self.viewModel.handleFlags(event.modifierFlags)
                return event
            case .scrollWheel:
                guard event.window === self.panel else { return event }
                return self.viewModel.handleScroll(event) ? nil : event
            default:
                return event
            }
        }
        if let monitor { monitors.append(monitor) }
    }
}
