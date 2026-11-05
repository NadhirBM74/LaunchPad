import Combine
import SwiftUI
import AppKit
import ServiceManagement

// MARK: - Fenêtre des réglages personnalisée (Gestion de la touche Échap et du focus)

final class SettingsWindow: NSWindow {
    weak var controller: SettingsWindowController?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        if let controller {
            controller.close()
        } else {
            close()
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Touche Échap
            if let controller {
                controller.close()
            } else {
                close()
            }
            return
        }
        super.keyDown(with: event)
    }
}

// MARK: - Fenêtre des réglages (fenêtre normale : plus de conflit avec le panneau plein écran)

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: SettingsWindow?
    private let store: LaunchpadStore
    var onRequestReorganize: (() -> Void)?
    /// Appelé à la fermeture (permet de rendre le focus au Launchpad).
    var onClose: (() -> Void)?
    private var isClosing = false

    init(store: LaunchpadStore) { self.store = store }

    var isVisible: Bool { window?.isVisible == true && !isClosing }
    private(set) var isAboveLaunchpad = false

    /// Ferme la fenêtre des réglages avec animation de fondu progressif
    func close() {
        guard let window, window.isVisible, !isClosing else { return }
        isClosing = true

        // Notifie immédiatement le Launchpad pour estomper le flou d'arrière-plan en synchronie
        NotificationCenter.default.post(name: .settingsVisibilityDidChange, object: false)

        let duration = Prefs.reduceMotion ? 0.0 : 0.22
        if duration > 0 {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().alphaValue = 0.0
            }, completionHandler: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.finalizeClose()
                }
            })
        } else {
            finalizeClose()
        }
    }

    private func finalizeClose() {
        guard let window else { return }
        window.orderOut(nil)
        window.contentViewController = nil
        window.alphaValue = 1.0
        isClosing = false
        let wasAbove = isAboveLaunchpad
        isAboveLaunchpad = false
        window.level = .normal
        if !Prefs.showDockIcon && !AdminTestWindowController.shared.isVisible { NSApp.setActivationPolicy(.accessory) }
        if wasAbove && !AdminTestWindowController.shared.isVisible { onClose?() }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        close()
        return false
    }

    /// Affiche les réglages, centrés sur `screen`, avec animation progressive de fondu.
    /// - Parameter launchpadLevel: niveau du panneau Launchpad s'il est ouvert : la fenêtre passe juste au-dessus.
    func show(above launchpadLevel: NSWindow.Level? = nil, on screen: NSScreen? = nil) {
        if window == nil {
            let window = SettingsWindow(contentRect: NSRect(x: 0, y: 0, width: SettingsPanel.size.width, height: SettingsPanel.size.height),
                                  styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.title = "Réglages LaucnhPad"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.collectionBehavior = [.moveToActiveSpace]
            window.delegate = self
            window.controller = self
            self.window = window
        }
        guard let window else { return }
        if window.contentViewController == nil {
            window.contentViewController = NSHostingController(rootView: SettingsPanel(store: store))
        }

        isClosing = false

        if let launchpadLevel {
            // Au-dessus du Launchpad, sans le fermer.
            isAboveLaunchpad = true
            window.level = NSWindow.Level(rawValue: launchpadLevel.rawValue + 1)
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        } else {
            isAboveLaunchpad = false
            window.level = .normal
            window.collectionBehavior = [.moveToActiveSpace]
            // Une app « barre des menus » (LSUIElement) n'est pas toujours activée par macOS :
            // on passe temporairement en app normale pour que la fenêtre passe au premier plan.
            NSApp.setActivationPolicy(.regular)
        }
        let targetScreen = screen ?? NSScreen.main ?? NSScreen.screens.first
        window.contentView?.layoutSubtreeIfNeeded()
        center(window, on: targetScreen)

        // Prépare le fondu d'apparition sans déplacement ni saut
        window.alphaValue = 0.0

        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        // SwiftUI peut ajuster la taille de la fenêtre après l'affichage : on recentre ensuite.
        center(window, on: targetScreen)
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else { return }
            self.center(window, on: targetScreen)
        }

        // Déclenche l'animation de fondu synchronisée avec le flou d'arrière-plan du Launchpad
        NotificationCenter.default.post(name: .settingsVisibilityDidChange, object: true)

        let duration = Prefs.reduceMotion ? 0.0 : 0.26
        if duration > 0 {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().alphaValue = 1.0
            })
        } else {
            window.alphaValue = 1.0
        }
    }

    #if DEBUG
    func snapshot(to url: URL) {
        guard let view = window?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
    #endif

    /// Le Launchpad se ferme : la fenêtre reste ouverte mais redevient une fenêtre normale.
    func launchpadDidHide() {
        guard let window, isAboveLaunchpad else { return }
        isAboveLaunchpad = false
        window.level = .normal
        window.collectionBehavior = [.moveToActiveSpace]
        if window.isVisible { NSApp.setActivationPolicy(.regular) }
    }

    private func center(_ window: NSWindow, on screen: NSScreen?) {
        guard let screen else { window.center(); return }
        let area = screen.visibleFrame
        let size = window.frame.size
        window.setFrameOrigin(NSPoint(x: (area.midX - size.width / 2).rounded(),
                                      y: (area.midY - size.height / 2).rounded()))
    }

    func windowWillClose(_ notification: Notification) {
        NotificationCenter.default.post(name: .settingsVisibilityDidChange, object: false)
        let wasAbove = isAboveLaunchpad
        isAboveLaunchpad = false
        window?.level = .normal
        if !Prefs.showDockIcon && !AdminTestWindowController.shared.isVisible { NSApp.setActivationPolicy(.accessory) }
        if wasAbove && !AdminTestWindowController.shared.isVisible { onClose?() }
    }
}
