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
        case kVK_Space: return loc("hotkey.space")
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
    private var keyTapThread: Thread?
    nonisolated(unsafe) private var keyTapRunLoop: CFRunLoop?
    private var mouseMonitors: [Any] = []

    // État du pincement
    private var pinchFingers = 0
    private var pinchInitialSpread: CGFloat = 0
    private var pinchInitialCentroid: CGPoint = .zero
    private var pinchInteractiveBaseline: CGFloat = 0
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
        if let tap = gestureTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = gestureSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        gestureTap = nil; gestureSource = nil

        if let tap = keyTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let rl = keyTapRunLoop {
            if let source = keySource {
                CFRunLoopRemoveSource(rl, source, .commonModes)
            }
            CFRunLoopStop(rl)
        } else if let source = keySource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        keyTap = nil; keySource = nil; keyTapRunLoop = nil; keyTapThread = nil

        if let globalGestureMonitor {
            NSEvent.removeMonitor(globalGestureMonitor)
            self.globalGestureMonitor = nil
        }
        mouseMonitors.forEach { NSEvent.removeMonitor($0) }
        mouseMonitors.removeAll()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        cornerTask?.cancel()
        cornerTask = nil
        interactiveWatchdog?.cancel()
        interactiveWatchdog = nil
        interactiveActive = false
        resetPinch()
    }

    nonisolated fileprivate func reenableKeyTap() {
        Task { @MainActor [weak self] in
            if let keyTap = self?.keyTap, !CGEvent.tapIsEnabled(tap: keyTap) {
                CGEvent.tapEnable(tap: keyTap, enable: true)
            }
        }
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

        // Moniteur global compagnon : si CGEventTap capture déjà `.gesture`, n'écouter que `.magnify` pour éviter les doublons 120 Hz.
        if globalGestureMonitor == nil {
            let events: NSEvent.EventTypeMask = gestureTapAvailable ? [.magnify] : [.gesture, .magnify]
            globalGestureMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] event in
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

        // Prise en compte directe de l'événement de pincement natif macOS (.magnify) uniquement s'il implique ≥ 3 doigts
        // (évite tout conflit avec le zoom à 2 doigts dans Safari, Finder, Aperçu, etc.).
        if event.type == .magnify {
            let touchingCount = event.touches(matching: .touching, in: nil).count
            guard touchingCount >= 3 || (!gestureTapAvailable && cachedPinchMode.accepts(max(3, touchingCount))) else {
                return
            }
            let mag = event.magnification
            let visible = isLaunchpadVisible()
            if !interactiveActive && !pinchFired {
                if !visible && mag < -0.045 {
                    pinchFired = true
                    onAction?(.open)
                    return
                } else if visible && (mag > 0.045 || mag < -0.055) {
                    pinchFired = true
                    onAction?(.close)
                    return
                }
            }
            return
        }

        // Récupère uniquement les contacts physiques actifs sans fallback inutile sur allTouches() quand aucun doigt ne touche
        let touching = event.touches(matching: .touching, in: nil)
        if touching.isEmpty {
            if interactiveActive {
                finishInteractive()
            }
            resetPinch()
            return
        }
        var count = 0
        var sumX: CGFloat = 0
        var sumY: CGFloat = 0
        var p0: CGPoint = .zero
        var p1: CGPoint = .zero
        var p2: CGPoint = .zero
        var p3: CGPoint = .zero
        var p4: CGPoint = .zero
        for touch in touching {
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
        // Ne réinitialise pas le référentiel si un 4ème doigt effleure brièvement le trackpad (ex: 3 vers 4 ou 4 vers 3)
        if !interactiveActive {
            if pinchInitialSpread == 0 || abs(count - pinchFingers) >= 2 {
                pinchFingers = count
                pinchInitialSpread = spread
                pinchInitialCentroid = centroid
                pinchInteractiveBaseline = 0
                pinchFired = false
                return
            } else if count != pinchFingers {
                pinchFingers = count
            }
        }

        guard pinchInitialSpread > 0.015 else { return }
        let driftDX = centroid.x - pinchInitialCentroid.x
        let driftDY = centroid.y - pinchInitialCentroid.y
        let driftSq = driftDX * driftDX + driftDY * driftDY
        let ratio = spread / pinchInitialSpread
        let visible = isLaunchpadVisible()

        // Prise en compte directe de la sensibilité configurée par l'utilisateur
        let sensitivity = cachedSensitivity
        let openRange = Self.baseOpenRange / sensitivity
        let closeRange = Self.baseCloseRange / sensitivity

        if !interactiveActive {
            guard !pinchFired else { return }

            // Discrimination stricte : si les 3 doigts se déplacent en parallèle (Mission Control, Exposé, Spaces,
            // ou glissement à 3 doigts) plutôt qu'un pincement radial autour du centroïde, ignorer totalement le geste.
            let radialChange = abs(1.0 - ratio)
            if count == 3 && driftSq > pow(max(0.038, radialChange * 1.28), 2) {
                return
            }

            let pinchInwardProgress = (1.0 - ratio) / openRange
            let spreadOutwardProgress = (ratio - 1.0) / closeRange

            // Seuil d'initiation très réactif dès qu'un vrai pincement radial démarre
            let initThreshold: CGFloat = 0.024 / sensitivity

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
                } else if pinchInwardProgress > (initThreshold * 1.12) {
                    shouldStart = true
                    opening = false
                } else {
                    shouldStart = false
                    opening = false
                }
            }

            // Bloque toute translation globale incompatible avec un pincement
            guard shouldStart, driftSq < (0.28 * 0.28) else { return }

            guard interactiveBegin?(opening) == true else { pinchFired = true; return }
            interactiveActive = true
            interactiveOpening = opening
            pinchInteractiveBaseline = max(0, opening ? pinchInwardProgress : max(pinchInwardProgress, spreadOutwardProgress))
            interactiveProgress = 0
            interactiveVelocity = 0
            interactiveUpdate?(opening ? 0 : 1)
            scheduleInteractiveWatchdog()
            return
        }

        // Annulation si le geste devient un grand balayage latéral/vertical macOS (drift excessif)
        if driftSq > (0.45 * 0.45) {
            finishInteractive(forceCancel: true)
            return
        }

        let rawMagnitude: CGFloat
        if interactiveOpening {
            rawMagnitude = (1.0 - ratio) / openRange
        } else {
            rawMagnitude = ratio < 1.0 ? (1.0 - ratio) / openRange : (ratio - 1.0) / closeRange
        }

        // Progression continue depuis 0.0 à partir du seuil d'entrée (aucun saut visuel à l'ouverture)
        let span = max(0.28, 1.0 - pinchInteractiveBaseline)
        let normalized = (rawMagnitude - pinchInteractiveBaseline) / span
        let progress = min(max(normalized, 0), 1)
        interactiveVelocity = interactiveVelocity * 0.35 + (progress - interactiveProgress) * 0.65
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
    private var lastInteractiveEventTime: ContinuousClock.Instant = .now

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
        interactiveWatchdog = nil
        pinchFired = true
        let progress = interactiveProgress, velocity = interactiveVelocity

        // Si l'utilisateur ouvrait LaunchPad : tout pincement engagé (> 8%) ou vitesse positive confirme l'ouverture !
        let commit: Bool
        if forceCancel {
            commit = false
        } else if interactiveOpening {
            commit = progress > 0.08 || velocity >= 0.0
        } else {
            commit = progress > 0.28 || (progress > 0.16 && velocity > 0.002)
        }
        interactiveEnd?(commit)
    }

    /// Sécurité : si plus aucun événement n'arrive (doigts levés sans événement final), on termine (sans réallouer à 120 Hz).
    private func scheduleInteractiveWatchdog() {
        lastInteractiveEventTime = .now
        guard interactiveWatchdog == nil else { return }
        interactiveWatchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(180))
                guard let self, !Task.isCancelled, self.interactiveActive else { break }
                if ContinuousClock.now - self.lastInteractiveEventTime >= .milliseconds(700) {
                    self.finishInteractive()
                    self.resetPinch()
                    break
                }
            }
            self?.interactiveWatchdog = nil
        }
    }

    private func resetPinch() {
        pinchFingers = 0
        pinchInitialSpread = 0
        pinchInteractiveBaseline = 0
        pinchFired = false
    }

    // MARK: Touche Launchpad / F4 (exécuté sur un thread RunLoop dédié : 0 réveil du thread principal pour les frappes ordinaires)

    private func startKeyTap() {
        guard Self.accessibilityTrusted else { return }
        // Écoute keyDown, keyUp ET NX_SYSDEFINED (type 14) pour intercepter F4 sans Fn (touche Spotlight/Launchpad Apple)
        let mask = (CGEventMask(1) << CGEventMask(CGEventType.keyDown.rawValue))
            | (CGEventMask(1) << CGEventMask(CGEventType.keyUp.rawValue))
            | (CGEventMask(1) << 14)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: keyTapCallback,
            userInfo: refcon
        ) ?? CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: keyTapCallback,
            userInfo: refcon
        )
        guard let tap, let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else { return }
        keyTap = tap
        keySource = source
        CGEvent.tapEnable(tap: tap, enable: true)

        struct SendableSource: @unchecked Sendable { let value: CFRunLoopSource }
        let sendableSource = SendableSource(value: source)
        let thread = Thread { [weak self] in
            let rl = CFRunLoopGetCurrent()
            self?.keyTapRunLoop = rl
            CFRunLoopAddSource(rl, sendableSource.value, .commonModes)
            CFRunLoopRun()
        }
        thread.name = "me.LaucnhPad.keyEventTap"
        thread.qualityOfService = .userInteractive
        keyTapThread = thread
        thread.start()
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
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] event in
            self?.checkCorner(screenPoint: event.locationInWindow)
        }) { mouseMonitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved], handler: { [weak self] event in
            self?.checkCorner(screenPoint: NSEvent.mouseLocation)
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

    private func checkCorner(screenPoint: CGPoint) {
        guard activeHotCorner != .off else { return }
        let inside = cornerTargets.contains { target in
            abs(screenPoint.x - target.x) <= 3 && abs(screenPoint.y - target.y) <= 3
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

nonisolated(unsafe) private var lastLaunchpadKeyToggleTime: CFAbsoluteTime = 0

nonisolated private func triggerLaunchpadFromKeyTap(refcon: UnsafeMutableRawPointer) {
    let now = CFAbsoluteTimeGetCurrent()
    guard now - lastLaunchpadKeyToggleTime > 0.18 else { return }
    lastLaunchpadKeyToggleTime = now
    let monitor = Unmanaged<InputEventMonitor>.fromOpaque(refcon).takeUnretainedValue()
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            monitor.onAction?(.toggle)
        }
    }
}

nonisolated private func keyTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        Unmanaged<InputEventMonitor>.fromOpaque(refcon).takeUnretainedValue().reenableKeyTap()
        return Unmanaged.passUnretained(event)
    }

    let modifiersMask: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
    guard event.flags.intersection(modifiersMask).isEmpty else {
        return Unmanaged.passUnretained(event)
    }

    // Touche média / fonction système Apple (NX_SYSDEFINED == 14) : intercepte F4 sans Fn (Launchpad / Spotlight)
    if type.rawValue == 14 {
        if let nsEvent = NSEvent(cgEvent: event), nsEvent.subtype.rawValue == 8 {
            let keyCode = Int((nsEvent.data1 & 0xFFFF_0000) >> 16)
            // 13 = NX_KEYTYPE_LAUNCH_PANEL, 131 = Launchpad Apple, 177 / 129 = Spotlight F4 Apple Silicon
            if keyCode == 13 || keyCode == 131 || keyCode == 177 || keyCode == 129 {
                let keyFlags = nsEvent.data1 & 0x0000_FFFF
                let keyState = (keyFlags & 0xFF00) >> 8
                let isRepeat = (keyFlags & 0x0001) != 0
                if keyState == 0x0A && !isRepeat {
                    triggerLaunchpadFromKeyTap(refcon: refcon)
                }
                return nil
            }
        }
        return Unmanaged.passUnretained(event)
    }

    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    // 131 = touche Launchpad, 177 / 129 = touche Spotlight F4 (sans Fn), 118 (kVK_F4) = F4 standard
    guard keyCode == 131 || keyCode == 177 || keyCode == 129 || keyCode == Int64(kVK_F4) else {
        return Unmanaged.passUnretained(event)
    }
    if type == .keyDown, event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
        triggerLaunchpadFromKeyTap(refcon: refcon)
    }
    return nil // Consomme keyDown et keyUp pour empêcher Spotlight de s'ouvrir
}
