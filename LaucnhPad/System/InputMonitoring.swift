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
        if Prefs.pinchMode != .off { startGestureTap() }
        if Prefs.interceptF4 { startKeyTap() }
        if activeHotCorner != .off { startHotCorner() }
    }

    func stopAll() {
        for (tap, source) in [(gestureTap, gestureSource), (keyTap, keySource)] {
            if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
            if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        }
        gestureTap = nil; gestureSource = nil; keyTap = nil; keySource = nil
        mouseMonitors.forEach { NSEvent.removeMonitor($0) }
        mouseMonitors.removeAll()
        cornerTask?.cancel()
    }

    fileprivate func reenableTaps() {
        if let gestureTap, !CGEvent.tapIsEnabled(tap: gestureTap) { CGEvent.tapEnable(tap: gestureTap, enable: true) }
        if let keyTap, !CGEvent.tapIsEnabled(tap: keyTap) { CGEvent.tapEnable(tap: keyTap, enable: true) }
    }

    // MARK: Pincement (event tap en écoute seule sur les événements « gesture »)

    private func startGestureTap() {
        let mask = CGEventMask(1) << CGEventMask(NSEvent.EventType.gesture.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                          eventsOfInterest: mask, callback: gestureTapCallback, userInfo: refcon) else {
            gestureTapAvailable = false
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        gestureTap = tap
        gestureSource = source
        gestureTapAvailable = true
    }

    fileprivate func handleGesture(_ event: NSEvent) {
        let mode = Prefs.pinchMode
        let touches = event.allTouches().filter { $0.phase != .ended && $0.phase != .cancelled }
        let count = touches.count
        guard mode.accepts(count) else {
            // Doigts levés (ou nombre de doigts changé) : fin du geste interactif.
            finishInteractive()
            if count < 3 { resetPinch() }
            return
        }
        let points = touches.map(\.normalizedPosition)
        let centroid = CGPoint(x: points.map(\.x).reduce(0, +) / CGFloat(count), y: points.map(\.y).reduce(0, +) / CGFloat(count))
        let spread = points.map { hypot($0.x - centroid.x, $0.y - centroid.y) }.reduce(0, +) / CGFloat(count)

        if count != pinchFingers || pinchInitialSpread == 0 {
            finishInteractive()
            pinchFingers = count
            pinchInitialSpread = spread
            pinchInitialCentroid = centroid
            pinchFired = false
            return
        }
        guard pinchInitialSpread > 0.03 else { return }
        // Un balayage déplace le centre sans changer l'écartement : on l'ignore.
        let drift = hypot(centroid.x - pinchInitialCentroid.x, centroid.y - pinchInitialCentroid.y)
        let ratio = spread / pinchInitialSpread

        if !interactiveActive {
            guard !pinchFired else { return }
            let visible = isLaunchpadVisible()
            let start = visible ? (ratio - 1) / Self.closeRange : (1 - ratio) / Self.openRange
            guard start > 0.06, drift < 0.12 else { return }
            guard interactiveBegin?(!visible) == true else { pinchFired = true; return }
            interactiveActive = true
            interactiveOpening = !visible
            interactiveProgress = 0
            interactiveVelocity = 0
        }
        // Le geste devient un balayage : on annule.
        if drift > 0.3 {
            finishInteractive(forceCancel: true)
            return
        }
        let raw = interactiveOpening ? (1 - ratio) / Self.openRange : (ratio - 1) / Self.closeRange
        let progress = min(max(raw, 0), 1)
        interactiveVelocity = interactiveVelocity * 0.5 + (progress - interactiveProgress) * 0.5
        interactiveProgress = progress
        // Visibilité du Launchpad : 0 → 1 à l'ouverture, 1 → 0 à la fermeture.
        interactiveUpdate?(interactiveOpening ? progress : 1 - progress)
        scheduleInteractiveWatchdog()
    }

    /// Écartement nécessaire pour une ouverture / fermeture complète.
    private static let openRange: CGFloat = 0.45   // pincer jusqu'à 55 % de l'écartement initial
    private static let closeRange: CGFloat = 0.6   // écarter jusqu'à 160 %

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
        // Comme macOS : on termine si le geste est assez avancé ou lancé dans le bon sens.
        let commit = !forceCancel && velocity > -0.01 && (progress > 0.35 || (progress > 0.1 && velocity > 0.004))
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
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] _ in
            self?.checkCorner()
        }) { mouseMonitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved], handler: { [weak self] event in
            self?.checkCorner()
            return event
        }) { mouseMonitors.append(local) }
    }

    private func checkCorner() {
        let corner = activeHotCorner
        guard corner != .off else { return }
        let location = NSEvent.mouseLocation
        let inside = NSScreen.screens.contains { screen in
            let frame = screen.frame
            let target: CGPoint
            switch corner {
            case .topLeft: target = CGPoint(x: frame.minX, y: frame.maxY)
            case .topRight: target = CGPoint(x: frame.maxX, y: frame.maxY)
            case .bottomLeft: target = CGPoint(x: frame.minX, y: frame.minY)
            case .bottomRight: target = CGPoint(x: frame.maxX, y: frame.minY)
            case .off: return false
            }
            return abs(location.x - target.x) <= 3 && abs(location.y - target.y) <= 3
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
