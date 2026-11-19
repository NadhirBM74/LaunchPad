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
        guard isClosing, let window else { return }
        window.orderOut(nil)
        window.alphaValue = 1.0
        isClosing = false
        let wasAbove = isAboveLaunchpad
        isAboveLaunchpad = false
        window.level = .normal
        if !Prefs.showDockIcon && !AdminTestWindowController.shared.isVisible { NSApp.setActivationPolicy(.accessory) }
        if wasAbove && !AdminTestWindowController.shared.isVisible { onClose?() }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Les réglages se ferment uniquement via la touche Échap (Esc) ou la fermeture du Launchpad
        return false
    }

    /// Affiche les réglages, toujours parfaitement centrés sur `screen`, avec animation progressive de fondu.
    /// - Parameter launchpadLevel: niveau du panneau Launchpad s'il est ouvert : la fenêtre passe juste au-dessus.
    func show(above launchpadLevel: NSWindow.Level? = nil, on screen: NSScreen? = nil) {
        let initialTargetScreen = resolveTargetScreen(preferred: screen)
        let initialFrame = centeredFrame(on: initialTargetScreen, centerHorizontallyInFullScreen: launchpadLevel != nil)

        if window == nil {
            let window = SettingsWindow(contentRect: initialFrame,
                                  styleMask: [.borderless],
                                  backing: .buffered, defer: false)
            window.title = loc("about.window_title")
            window.isMovableByWindowBackground = true
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
        window.title = loc("about.window_title")
        let targetAppearanceName: NSAppearance.Name = Prefs.backgroundStyle == .light ? .aqua : .darkAqua
        if window.appearance?.name != targetAppearanceName {
            window.appearance = NSAppearance(named: targetAppearanceName)
        }
        if window.contentViewController == nil {
            let hosting = NSHostingController(rootView: SettingsPanel(store: store))
            // Empêche NSHostingController de modifier la taille/position de la fenêtre lors du premier layout.
            hosting.sizingOptions = []
            window.contentViewController = hosting
        }

        // Annule une éventuelle animation de fermeture en cours si l'utilisateur réouvre immédiatement.
        if isClosing {
            isClosing = false
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                window.animator().alphaValue = 0.0
            }
        }

        let aboveLaunchpad = launchpadLevel != nil
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

        let targetScreen = resolveTargetScreen(preferred: screen)
        let targetFrame = centeredFrame(on: targetScreen, centerHorizontallyInFullScreen: aboveLaunchpad)
        window.setFrame(targetFrame, display: false)

        // Prépare le fondu d'apparition sans déplacement ni saut
        window.alphaValue = 0.0
        NotificationCenter.default.post(name: .settingsWillShow, object: nil)

        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        if window.frame != targetFrame {
            window.setFrame(targetFrame, display: true)
        }

        // Déclenche l'animation de fondu synchronisée avec le flou d'arrière-plan du Launchpad
        NotificationCenter.default.post(name: .settingsVisibilityDidChange, object: true)

        let duration = Prefs.reduceMotion ? 0.0 : 0.22
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
        guard let view = window?.contentView else { return }
        if ProcessInfo.processInfo.arguments.contains("--scroll-settings-down") {
            func findMainScrollView(in root: NSView) -> NSScrollView? {
                if let sv = root as? NSScrollView,
                   let doc = sv.documentView,
                   doc.bounds.height > sv.contentView.bounds.height + 50,
                   sv.bounds.width > 350 {
                    return sv
                }
                for child in root.subviews {
                    if let found = findMainScrollView(in: child) { return found }
                }
                return nil
            }
            if let sv = findMainScrollView(in: view), let doc = sv.documentView {
                let clip = sv.contentView
                let maxY = max(0, doc.bounds.height - clip.bounds.height)
                let targetY = doc.isFlipped ? min(maxY, 360) : max(0, maxY - 360)
                clip.scroll(to: NSPoint(x: 0, y: targetY))
                sv.reflectScrolledClipView(clip)
                view.layoutSubtreeIfNeeded()
            }
        }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
    #endif

    /// Le Launchpad se ferme (ex: geste à 3 doigts) : on ferme automatiquement les réglages
    /// pour qu'ils ne restent pas ouverts ni ne réapparaissent à la prochaine ouverture.
    func launchpadDidHide() {
        if isVisible {
            close()
        }
    }

    private func resolveTargetScreen(preferred: NSScreen?) -> NSScreen? {
        if let preferred { return preferred }
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func centeredFrame(on screen: NSScreen?, centerHorizontallyInFullScreen: Bool) -> NSRect {
        let fallback = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let visible = screen?.visibleFrame ?? screen?.frame ?? fallback
        let full = screen?.frame ?? visible
        let width = min(SettingsPanel.size.width, max(640, visible.width - 24))
        let height = min(SettingsPanel.size.height, max(480, visible.height - 24))
        let horizontalAnchor = centerHorizontallyInFullScreen ? full : visible
        let rawX = horizontalAnchor.minX + (horizontalAnchor.width - width) / 2
        let clampedX = min(max(rawX, visible.minX), visible.maxX - width)
        let rawY = visible.minY + (visible.height - height) / 2
        return NSRect(x: clampedX.rounded(), y: rawY.rounded(), width: width.rounded(), height: height.rounded())
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
