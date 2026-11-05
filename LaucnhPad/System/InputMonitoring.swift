import AppKit
import Carbon.HIToolbox
import ApplicationServices

// MARK: - Raccourci clavier global (Carbon : fonctionne sans autorisation d'accessibilité)

@MainActor
final class HotKeyManager {
    static let shared = HotKeyManager()
    var onPress: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerInstalled = false
    private(set) var lastStatus: OSStatus = noErr

    func register(keyCode: UInt32, modifiers: UInt32) {
        unregister()
        installHandlerIfNeeded()
        let identifier = EventHotKeyID(signature: OSType(0x4C50_4144), id: 1) // 'LPAD'
        var reference: EventHotKeyRef?
        lastStatus = RegisterEventHotKey(keyCode, modifiers, identifier, GetApplicationEventTarget(), 0, &reference)
        hotKeyRef = lastStatus == noErr ? reference : nil
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    fileprivate func fire() { onPress?() }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyEventHandler, 1, &spec, nil, nil)
        handlerInstalled = true
    }
}

nonisolated private func hotKeyEventHandler(_ next: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    Task { @MainActor in HotKeyManager.shared.fire() }
    return noErr
}

enum ShortcutFormatter {
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    static func symbols(for flags: NSEvent.ModifierFlags) -> String {
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        return text
    }

    static let functionKeys: [UInt16: String] = [
        UInt16(kVK_F1): "F1", UInt16(kVK_F2): "F2", UInt16(kVK_F3): "F3", UInt16(kVK_F4): "F4",
        UInt16(kVK_F5): "F5", UInt16(kVK_F6): "F6", UInt16(kVK_F7): "F7", UInt16(kVK_F8): "F8",
        UInt16(kVK_F9): "F9", UInt16(kVK_F10): "F10", UInt16(kVK_F11): "F11", UInt16(kVK_F12): "F12",
        UInt16(kVK_F13): "F13", UInt16(kVK_F14): "F14", UInt16(kVK_F15): "F15", UInt16(kVK_F16): "F16",
        UInt16(kVK_F17): "F17", UInt16(kVK_F18): "F18", UInt16(kVK_F19): "F19", UInt16(kVK_F20): "F20",
    ]

    static func keyName(for event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_Space: return "Espace"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_Home: return "↖"
        case kVK_End: return "↘"
        case kVK_PageUp: return "⇞"
        case kVK_PageDown: return "⇟"
        default:
            if let name = functionKeys[event.keyCode] { return name }
            return (event.charactersIgnoringModifiers ?? "?").uppercased()
        }
    }
}

// MARK: - Gestes trackpad, touche Launchpad (F4) et coins actifs

@MainActor
final class InputEventMonitor {
    static let shared = InputEventMonitor()

    enum Action { case open, close, toggle }
    var onAction: ((Action) -> Void)?
    var isLaunchpadVisible: () -> Bool = { false }

    private(set) var gestureTapAvailable = false
    private var gestureTap: CFMachPort?
    private var gestureSource: CFRunLoopSource?
    private var globalGestureMonitor: Any?
    private var lastGestureTimestamp: TimeInterval = 0
    private var keyTap: CFMachPort?
    private var keySource: CFRunLoopSource?
    private var mouseMonitors: [Any] = []

    // État du pincement
    private var pinchFingers = 0
    private var pinchInitialSpread: CGFloat = 0
    private var pinchInitialCentroid: CGPoint = .zero
    private var pinchFired = false

    // État du coin actif
    private var activeHotCorner: HotCorner = .off
    private var cornerEnteredAt: Date?
    private var cornerFired = false
    private var cornerTask: Task<Void, Never>?

    static var accessibilityTrusted: Bool { AXIsProcessTrusted() }

    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func reconfigure() {
        stopAll()
        activeHotCorner = Prefs.hotCorner
        cachedPinchMode = Prefs.pinchMode
        cachedSensitivity = CGFloat(max(0.3, min(Prefs.scrollSensitivity, 2.5)))
        if cachedPinchMode != .off { startGestureTap() }
        if Prefs.interceptF4 { startKeyTap() }
        if activeHotCorner != .off { startHotCorner() }
    }

    /// Réglages mis en cache : le chemin chaud (chaque événement trackpad du système) ne lit jamais UserDefaults.
    private var cachedPinchMode: PinchMode = .off
    private var cachedSensitivity: CGFloat = 1.0

    func stopAll() {
        for (tap, source) in [(gestureTap, gestureSource), (keyTap, keySource)] {
            if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
            if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        }
        gestureTap = nil; gestureSource = nil; keyTap = nil; keySource = nil
        if let globalGestureMonitor {
            NSEvent.removeMonitor(globalGestureMonitor)
            self.globalGestureMonitor = nil
        }
        mouseMonitors.forEach { NSEvent.removeMonitor($0) }
        mouseMonitors.removeAll()
        cornerTask?.cancel()
        interactiveWatchdog?.cancel()
    }

    fileprivate func reenableTaps() {
        if let gestureTap, !CGEvent.tapIsEnabled(tap: gestureTap) { CGEvent.tapEnable(tap: gestureTap, enable: true) }
        if let keyTap, !CGEvent.tapIsEnabled(tap: keyTap) { CGEvent.tapEnable(tap: keyTap, enable: true) }
    }

    // MARK: Pincement (Event tap + moniteur global pour capture précise et fluide)

    private func startGestureTap() {
        let mask = CGEventMask(1) << CGEventMask(NSEvent.EventType.gesture.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        if let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                       eventsOfInterest: mask, callback: gestureTapCallback, userInfo: refcon) {
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            gestureTap = tap
            gestureSource = source
            gestureTapAvailable = true
        } else {
            gestureTapAvailable = false
        }

        // Moniteur global compagnon pour garantir la réception sans délai
        if globalGestureMonitor == nil {
            globalGestureMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.gesture]) { [weak self] event in
                self?.handleGesture(event)
            }
        }
    }

    fileprivate func handleGesture(_ event: NSEvent) {
        // Déduplication entre CGEventTap et le global monitor
        guard abs(event.timestamp - lastGestureTimestamp) > 0.0005 else { return }
        lastGestureTimestamp = event.timestamp

        let mode = cachedPinchMode
        guard mode != .off else { return }

        // Récupère l'ensemble des contacts physiques actifs (y compris stationnaires) sans allocations superflues
        let touching = event.touches(matching: .touching, in: nil)
        let rawTouches = touching.isEmpty ? event.allTouches() : touching
        var count = 0
        var sumX: CGFloat = 0
        var sumY: CGFloat = 0
        var p0: CGPoint = .zero
        var p1: CGPoint = .zero
        var p2: CGPoint = .zero
        var p3: CGPoint = .zero
        var p4: CGPoint = .zero
        for touch in rawTouches {
            let phase = touch.phase
            if phase != .ended && phase != .cancelled {
                let pos = touch.normalizedPosition
                sumX += pos.x
                sumY += pos.y
                switch count {
                case 0: p0 = pos
                case 1: p1 = pos
                case 2: p2 = pos
                case 3: p3 = pos
                default: p4 = pos
                }
                count += 1
            }
        }

        // Tolérance continue : en cours de geste, tolérer 2 à 5 doigts sans interruption
        if interactiveActive {
            if count < 2 {
                finishInteractive()
                resetPinch()
                return
            }
        } else {
            guard mode.accepts(count) else {
                if count < 3 { resetPinch() }
                return
            }
        }

        let invCount = 1.0 / CGFloat(count)
        let centroid = CGPoint(x: sumX * invCount, y: sumY * invCount)
        var spreadSum: CGFloat = 0
        let sampleCount = min(count, 5)
        if sampleCount > 0 { spreadSum += hypot(p0.x - centroid.x, p0.y - centroid.y) }
        if sampleCount > 1 { spreadSum += hypot(p1.x - centroid.x, p1.y - centroid.y) }
        if sampleCount > 2 { spreadSum += hypot(p2.x - centroid.x, p2.y - centroid.y) }
        if sampleCount > 3 { spreadSum += hypot(p3.x - centroid.x, p3.y - centroid.y) }
        if sampleCount > 4 { spreadSum += hypot(p4.x - centroid.x, p4.y - centroid.y) }
        let spread = spreadSum / CGFloat(sampleCount)

        // Réinitialisation du référentiel initial lors d'un nouveau geste
        if !interactiveActive && (count != pinchFingers || pinchInitialSpread == 0) {
            pinchFingers = count
            pinchInitialSpread = spread
            pinchInitialCentroid = centroid
            pinchFired = false
            // Sensibilité relue une seule fois par geste (le réglage s'applique dès le geste suivant)
            cachedSensitivity = CGFloat(max(0.3, min(Prefs.scrollSensitivity, 2.5)))
            return
        }

        guard pinchInitialSpread > 0.025 else { return }
        let drift = hypot(centroid.x - pinchInitialCentroid.x, centroid.y - pinchInitialCentroid.y)
        let ratio = spread / pinchInitialSpread

        // Prise en compte directe de la sensibilité configurée par l'utilisateur
        let sensitivity = cachedSensitivity
        let openRange = Self.baseOpenRange / sensitivity
        let closeRange = Self.baseCloseRange / sensitivity

        if !interactiveActive {
            guard !pinchFired else { return }
            let visible = isLaunchpadVisible()

            let pinchInwardProgress = (1.0 - ratio) / openRange
            let spreadOutwardProgress = (ratio - 1.0) / closeRange

            // Seuil d'initiation équilibré (juste milieu entre réactivité et absence de faux déclenchements)
            let initThreshold: CGFloat = 0.075 / sensitivity

            let shouldStart: Bool
            let opening: Bool

            if !visible {
                // Fermé : pincer vers l'intérieur ouvre
                shouldStart = pinchInwardProgress > initThreshold
                opening = true
            } else {
                // Déjà ouvert : écarter vers l'extérieur OU repincer vers l'intérieur ferme
                if spreadOutwardProgress > initThreshold {
                    shouldStart = true
                    opening = false
                } else if pinchInwardProgress > (initThreshold * 1.15) {
                    shouldStart = true
                    opening = false
                } else {
                    shouldStart = false
                    opening = false
                }
            }

            // Tolérance de dérive équilibrée : évite les démarrages sur simple balayage
            guard shouldStart, drift < 0.22 else { return }
            guard interactiveBegin?(opening) == true else { pinchFired = true; return }
            interactiveActive = true
            interactiveOpening = opening
            interactiveProgress = 0
            interactiveVelocity = 0
        }

        // Annulation si le geste se transforme en balayage (drift excessif)
        if drift > 0.35 {
            finishInteractive(forceCancel: true)
            return
        }

        let raw: CGFloat
        if interactiveOpening {
            raw = (1.0 - ratio) / openRange
        } else {
            raw = ratio < 1.0 ? (1.0 - ratio) / openRange : (ratio - 1.0) / closeRange
        }

        let progress = min(max(raw, 0), 1)
        interactiveVelocity = interactiveVelocity * 0.5 + (progress - interactiveProgress) * 0.5
        interactiveProgress = progress

        // Visibilité du Launchpad : 0 → 1 à l'ouverture, 1 → 0 à la fermeture
        interactiveUpdate?(interactiveOpening ? progress : 1.0 - progress)
        scheduleInteractiveWatchdog()
    }

    /// Amplitudes de base pour ouverture / fermeture complète
    private static let baseOpenRange: CGFloat = 0.42
    private static let baseCloseRange: CGFloat = 0.58

    private var interactiveActive = false
    private var interactiveOpening = false
    private var interactiveProgress: CGFloat = 0
    private var interactiveVelocity: CGFloat = 0
    private var interactiveWatchdog: Task<Void, Never>?

    /// Le geste commence : renvoie false si le Launchpad refuse (fenêtre modale, etc.).
    var interactiveBegin: ((_ opening: Bool) -> Bool)?
    /// Visibilité du Launchpad (0 = caché, 1 = affiché).
    var interactiveUpdate: ((_ visibility: CGFloat) -> Void)?
    /// Fin du geste : true = terminer l'action (ouvrir / fermer), false = revenir à l'état initial.
    var interactiveEnd: ((_ commit: Bool) -> Void)?

    private func finishInteractive(forceCancel: Bool = false) {
        guard interactiveActive else { return }
        interactiveActive = false
        interactiveWatchdog?.cancel()
        pinchFired = true
        let progress = interactiveProgress, velocity = interactiveVelocity

        // Validation au juste milieu : engagement franc requis (> 34 % ou > 22 % avec vitesse nette)
        let commit = !forceCancel && (progress > 0.34 || (progress > 0.22 && velocity > 0.003))
        interactiveEnd?(commit)
    }

    /// Sécurité : si plus aucun événement n'arrive (doigts levés sans événement final), on termine.
    private func scheduleInteractiveWatchdog() {
        interactiveWatchdog?.cancel()
        interactiveWatchdog = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            self?.finishInteractive()
            self?.resetPinch()
        }
    }

    private func resetPinch() {
        pinchFingers = 0
        pinchInitialSpread = 0
        pinchFired = false
    }

    // MARK: Touche Launchpad / F4 (nécessite l'accessibilité pour intercepter la touche)

    private func startKeyTap() {
        guard Self.accessibilityTrusted else { return }
        let mask = (CGEventMask(1) << CGEventMask(CGEventType.keyDown.rawValue)) | (CGEventMask(1) << CGEventMask(CGEventType.keyUp.rawValue))
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: keyTapCallback, userInfo: refcon) else { return }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        keyTap = tap
        keySource = source
    }

    // MARK: Coin actif

    private func startHotCorner() {
        refreshCornerTargets()
        if screenObserver == nil {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshCornerTargets() }
            }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] _ in
            self?.checkCorner()
        }) { mouseMonitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved], handler: { [weak self] event in
            self?.checkCorner()
            return event
        }) { mouseMonitors.append(local) }
    }

    /// Points cibles du coin actif sur chaque écran (recalculés uniquement si la configuration d'écrans change).
    private var cornerTargets: [CGPoint] = []
    private var screenObserver: NSObjectProtocol?

    private func refreshCornerTargets() {
        let corner = activeHotCorner
        cornerTargets = NSScreen.screens.compactMap { screen in
            let frame = screen.frame
            switch corner {
            case .topLeft: return CGPoint(x: frame.minX, y: frame.maxY)
            case .topRight: return CGPoint(x: frame.maxX, y: frame.maxY)
            case .bottomLeft: return CGPoint(x: frame.minX, y: frame.minY)
            case .bottomRight: return CGPoint(x: frame.maxX, y: frame.minY)
            case .off: return nil
            }
        }
    }

    private func checkCorner() {
        guard activeHotCorner != .off else { return }
        let location = NSEvent.mouseLocation
        let inside = cornerTargets.contains { target in
            abs(location.x - target.x) <= 3 && abs(location.y - target.y) <= 3
        }
        if inside {
            guard !cornerFired, cornerEnteredAt == nil else { return }
            cornerEnteredAt = Date()
            cornerTask?.cancel()
            cornerTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(160))
                guard let self, !Task.isCancelled, self.cornerEnteredAt != nil else { return }
                self.cornerFired = true
                self.onAction?(.toggle)
            }
        } else {
            cornerTask?.cancel()
            cornerEnteredAt = nil
            cornerFired = false
        }
    }
}

nonisolated private func gestureTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated {
            Unmanaged<InputEventMonitor>.fromOpaque(refcon).takeUnretainedValue().reenableTaps()
        }
        return Unmanaged.passUnretained(event)
    }
    if let nsEvent = NSEvent(cgEvent: event) {
        MainActor.assumeIsolated {
            Unmanaged<InputEventMonitor>.fromOpaque(refcon).takeUnretainedValue().handleGesture(nsEvent)
        }
    }
    return Unmanaged.passUnretained(event)
}

nonisolated private func keyTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated {
            Unmanaged<InputEventMonitor>.fromOpaque(refcon).takeUnretainedValue().reenableTaps()
        }
        return Unmanaged.passUnretained(event)
    }
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let flags = event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
    // 131 = touche Launchpad des claviers Apple ; 118 = F4 standard sans modificateur.
    guard keyCode == 131 || (keyCode == Int64(kVK_F4) && flags.isEmpty) else { return Unmanaged.passUnretained(event) }
    if type == .keyDown, event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
        MainActor.assumeIsolated {
            Unmanaged<InputEventMonitor>.fromOpaque(refcon).takeUnretainedValue().onAction?(.toggle)
        }
    }
    return nil // la touche est consommée
}
