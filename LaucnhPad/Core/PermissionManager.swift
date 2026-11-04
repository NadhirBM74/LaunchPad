import Foundation
import ApplicationServices
import AppKit
import SwiftUI
import Combine

// MARK: - Gestionnaire centralisé des autorisations système de LaunchPad
// Gère et surveille l'autorisation d'Accessibilité (AXIsProcessTrusted),
// indispensable pour les gestes trackpad, l'interception F4, les coins actifs
// et les commandes multimédia des widgets.

@MainActor
final class PermissionManager: ObservableObject {
    static let shared = PermissionManager()

    @Published private(set) var isAccessibilityGranted: Bool = AXIsProcessTrusted()
    @Published var showPermissionCard: Bool = false
    @Published var hasDismissedBanner: Bool = false

    private var pollTimer: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    private var lastTrustedState: Bool = false

    private init() {
        lastTrustedState = AXIsProcessTrusted()
        isAccessibilityGranted = lastTrustedState
        if !lastTrustedState {
            startMonitoring()
        }
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.checkStatus()
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .launchpadVisibilityDidChange)
            .compactMap { $0.object as? Bool }
            .filter { $0 }
            .sink { [weak self] _ in
                self?.checkStatus()
            }
            .store(in: &cancellables)
    }

    /// Démarre la surveillance en temps réel de l'état de l'accessibilité (uniquement tant qu'elle n'est pas accordée)
    func startMonitoring() {
        guard !isAccessibilityGranted else {
            pollTimer?.cancel()
            pollTimer = nil
            return
        }
        guard pollTimer == nil else { return }
        pollTimer = Timer.publish(every: 1.8, tolerance: 0.4, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.checkStatus()
            }
    }

    /// Rafraîchit l'état et réagit immédiatement à l'octroi de l'autorisation
    func checkStatus() {
        let current = AXIsProcessTrusted()
        if current != isAccessibilityGranted {
            isAccessibilityGranted = current
        }

        // Si l'autorisation vient d'être accordée par l'utilisateur dans Réglages Système
        if current && !lastTrustedState {
            lastTrustedState = true
            pollTimer?.cancel()
            pollTimer = nil
            onAccessibilityGranted()
        } else if !current {
            lastTrustedState = false
            startMonitoring()
        }
    }

    /// Action appelée automatiquement dès que l'accessibilité est accordée
    private func onAccessibilityGranted() {
        // 1. Reconfigure immédiatement les écouteurs de gestes et touches sans redémarrer
        InputEventMonitor.shared.reconfigure()

        // 2. Notifie l'ensemble de l'application
        NotificationCenter.default.post(name: .accessibilityPermissionDidChange, object: true)

        // 3. Masque automatiquement les invites
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                self?.showPermissionCard = false
            }
        }
    }

    /// Déclenche la demande d'autorisation système et ouvre Réglages Système > Accessibilité
    func requestAccessibility() {
        // 1. Demande native macOS (affiche l'alerte système si ce n'est pas déjà fait)
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        // 2. Ouvre directement le panneau Accessibilité dans Réglages Système
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }

        // 3. Accélère la vérification pendant que l'utilisateur est dans Réglages Système
        checkStatus()
    }

    /// Vérification automatique au lancement de l'application
    func checkOnLaunch(onShowLaunchpad: (() -> Void)? = nil) {
        checkStatus()
        guard !isAccessibilityGranted else { return }

        let promptedKey = PrefKey.hasPromptedAccessibility
        let hasPrompted = Prefs.defaults.bool(forKey: promptedKey)

        if !hasPrompted {
            Prefs.defaults.set(true, forKey: promptedKey)
            // Premier lancement : demande poliment l'autorisation
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                guard let self, !self.isAccessibilityGranted else { return }
                self.showPermissionCard = true
                onShowLaunchpad?()
            }
        }
    }

    /// Demande explicite manuelle ou lors de l'interaction avec une fonctionnalité bloquée
    func promptUserForAccessibility() {
        checkStatus()
        if isAccessibilityGranted {
            return
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            showPermissionCard = true
        }
    }
}

extension Notification.Name {
    static let accessibilityPermissionDidChange = Notification.Name("AccessibilityPermissionDidChange")
}
