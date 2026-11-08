import Foundation
import Combine
import AppKit

/// Gestionnaire de la licence et de l'état Freemium de l'application.
///
/// Trois états sont pris en charge :
/// - **Version gratuite** : fonctionnalités de base actives, thèmes Sombre et Verre flouté.
/// - **Essai Pro de 7 jours** : accès Pro complet sans restriction avec décompte en direct ; repasse en gratuit à l'échéance.
/// - **Version Pro Permanente** : débloquée par achat/licence (Lemon Squeezy ou clé), sans limite de temps.
@MainActor
final class LicenseManager: ObservableObject {
    static let shared = LicenseManager()

    @Published private(set) var isPro: Bool {
        didSet {
            Prefs.isProUnlocked = isPro
        }
    }

    @Published private(set) var licenseKey: String {
        didSet {
            Prefs.licenseKey = licenseKey
        }
    }

    @Published private(set) var isValidatingOnline: Bool = false

    // MARK: - Propriétés de l'Essai Gratuit 7 Jours
    @Published private(set) var isTrialActive: Bool = false
    @Published private(set) var isProLifetime: Bool = false
    @Published private(set) var trialStartDate: Date? = nil
    @Published private(set) var trialEndDate: Date? = nil
    @Published private(set) var hasUsedTrial: Bool = false

    @Published private(set) var timeRemainingString: String = ""
    @Published private(set) var trialDaysRemaining: Int = 0
    @Published private(set) var trialHoursRemaining: Int = 0
    @Published private(set) var trialMinutesRemaining: Int = 0
    @Published private(set) var trialSecondsRemaining: Int = 0
    @Published private(set) var trialProgress: Double = 0.0

    private var countdownTimer: Timer?

    /// Identifiant de l'instance d'activation attribué par l'API de licence (Lemon Squeezy / Polar)
    /// Permet de comptabiliser exactement 1, 2 ou 5 appareils Mac activés.
    private let instanceIdKey = "LaunchpadLicenseInstanceId"

    var licenseInstanceId: String {
        get { UserDefaults.standard.string(forKey: instanceIdKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: instanceIdKey) }
    }

    /// URL de la page d'achat Pro ("Get Pro") ouverte depuis l'application
    static let getProCheckoutURL = URL(string: "https://github.com/NadhirBM74/LaunchPad#pricing")!

    private init() {
        let loadedLicenseKey = Prefs.licenseKey
        let loadedIsProLifetime = Prefs.isProLifetime || (!loadedLicenseKey.isEmpty && loadedLicenseKey == "1234")
        let loadedIsTrialActive = Prefs.isTrialActive
        let loadedTrialStartDate = Prefs.trialStartDate
        let loadedTrialEndDate = Prefs.trialEndDate
        let loadedHasUsedTrial = Prefs.hasUsedTrial

        let trialValid = loadedIsTrialActive && (loadedTrialEndDate ?? Date.distantPast) > Date()
        let calculatedIsPro = loadedIsProLifetime || trialValid

        self.isPro = calculatedIsPro
        self.licenseKey = loadedLicenseKey
        self.isProLifetime = loadedIsProLifetime
        self.isTrialActive = loadedIsTrialActive
        self.trialStartDate = loadedTrialStartDate
        self.trialEndDate = loadedTrialEndDate
        self.hasUsedTrial = loadedHasUsedTrial

        Prefs.isProUnlocked = calculatedIsPro

        // Si l'essai était marqué actif mais est expiré à l'ouverture, on nettoie
        if loadedIsTrialActive && !loadedIsProLifetime {
            if let end = loadedTrialEndDate, Date() >= end {
                handleTrialExpiration(notify: false)
            } else {
                updateCountdownValues()
                startCountdownTicker()
            }
        }
    }

    // =========================================================================
    // MARK: - Gestion de l'Essai 7 Jours & Décompte
    // =========================================================================

    /// Démarre un essai gratuit de 7 jours avec toutes les fonctionnalités Pro actives.
    @discardableResult
    func startSevenDayTrial() -> Bool {
        if isProLifetime {
            return false // Déjà pro permanent
        }

        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now.addingTimeInterval(7 * 24 * 3600)

        self.trialStartDate = now
        self.trialEndDate = end
        self.isTrialActive = true
        self.hasUsedTrial = true
        self.isPro = true

        Prefs.trialStartDate = now
        Prefs.trialEndDate = end
        Prefs.isTrialActive = true
        Prefs.hasUsedTrial = true
        Prefs.isProUnlocked = true

        updateCountdownValues()
        startCountdownTicker()

        AppNotificationManager.shared.sendTrialStartedNotification(days: 7)
        NotificationCenter.default.post(name: .trialStatusDidChange, object: nil)
        AdminManager.shared.log(category: "Licence", message: "Essai gratuit de 7 jours activé jusqu'au \(end.formatted(date: .abbreviated, time: .shortened))")

        return true
    }

    /// Démarre le minuteur qui rafraîchit le compte à rebours chaque seconde.
    private func startCountdownTicker() {
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateCountdownValues()
            }
        }
    }

    /// Arrête le minuteur de compte à rebours.
    private func stopCountdownTicker() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }

    /// Met à jour les valeurs de décompte restantes (jours, heures, minutes, secondes).
    func updateCountdownValues() {
        guard isTrialActive, !isProLifetime, let end = trialEndDate, let start = trialStartDate else {
            return
        }

        let now = Date()
        let remaining = end.timeIntervalSince(now)

        if remaining <= 0 {
            handleTrialExpiration(notify: true)
            return
        }

        let totalDuration = max(1.0, end.timeIntervalSince(start))
        let elapsed = now.timeIntervalSince(start)
        self.trialProgress = min(1.0, max(0.0, elapsed / totalDuration))

        let totalSeconds = Int(remaining)
        let days = totalSeconds / 86400
        let hours = (totalSeconds % 86400) / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        self.trialDaysRemaining = days
        self.trialHoursRemaining = hours
        self.trialMinutesRemaining = minutes
        self.trialSecondsRemaining = seconds

        if days > 0 {
            self.timeRemainingString = String(format: "%d j %02d h %02d m %02d s", days, hours, minutes, seconds)
        } else {
            self.timeRemainingString = String(format: "%02d h %02d m %02d s", hours, minutes, seconds)
        }
    }

    /// Traite l'expiration de l'essai de 7 jours et remet l'application en version gratuite.
    private func handleTrialExpiration(notify: Bool = true) {
        stopCountdownTicker()

        self.isTrialActive = false
        self.isPro = false
        self.timeRemainingString = "Expiré"
        self.trialDaysRemaining = 0
        self.trialHoursRemaining = 0
        self.trialMinutesRemaining = 0
        self.trialSecondsRemaining = 0
        self.trialProgress = 1.0

        Prefs.isTrialActive = false
        Prefs.isProUnlocked = false

        // Rétablissement des réglages de base si des éléments Pro étaient sélectionnés
        if Prefs.appLogo.isProOnly {
            Prefs.defaults.set(AppLogo.noir.rawValue, forKey: PrefKey.appLogo)
            NSApp.applicationIconImage = AppLogo.noir.image
        }
        if Prefs.backgroundStyle == .liquidGlass {
            Prefs.defaults.set(AppTheme.dark.rawValue, forKey: PrefKey.backgroundStyle)
        }

        AdminManager.shared.log(category: "Licence", message: "Essai gratuit de 7 jours expiré : retour automatique en version gratuite.")

        if notify {
            AppNotificationManager.shared.sendTrialExpiredNotification()
            NotificationCenter.default.post(name: .trialDidExpire, object: nil)
        }
        NotificationCenter.default.post(name: .trialStatusDidChange, object: nil)
    }

    /// Vérifie l'état de l'essai (à appeler au démarrage ou lors du réveil du Mac).
    func checkTrialStatus() {
        if isTrialActive && !isProLifetime {
            if let end = trialEndDate, Date() >= end {
                handleTrialExpiration(notify: true)
            } else {
                updateCountdownValues()
                if countdownTimer == nil {
                    startCountdownTicker()
                }
            }
        }
    }

    /// Valide et accorde la licence Pro permanente (Lifetime).
    func unlockLifetimePro(licenseKey: String = "1234") {
        stopCountdownTicker()

        self.isProLifetime = true
        self.isTrialActive = false
        self.isPro = true
        self.licenseKey = licenseKey
        self.timeRemainingString = ""

        Prefs.isProLifetime = true
        Prefs.isTrialActive = false
        Prefs.isProUnlocked = true
        Prefs.licenseKey = licenseKey

        AppNotificationManager.shared.sendProActivatedNotification()
        NotificationCenter.default.post(name: .trialStatusDidChange, object: nil)
        AdminManager.shared.log(category: "Licence", message: "Licence Pro Permanente débloquée avec succès.")
    }

    // =========================================================================
    // MARK: - API de Paiement & Licence (Lemon Squeezy License API)
    // =========================================================================
    //
    // Architecture prête pour Lemon Squeezy (recommandé pour les licences 1 / 2 / 5 Macs) :
    // - Endpoint d'activation : POST https://api.lemonsqueezy.com/v1/licenses/activate
    // - Endpoint de vérification : POST https://api.lemonsqueezy.com/v1/licenses/validate
    // - Endpoint de désactivation : POST https://api.lemonsqueezy.com/v1/licenses/deactivate
    // Aucune clé secrète API n'est requise dans le binaire macOS : Lemon Squeezy gère
    // automatiquement le quota d'appareils (1, 2 ou 5 Macs) associé à la variante achetée.
    // =========================================================================

    private struct LemonSqueezyActivationResponse: Decodable {
        let activated: Bool?
        let valid: Bool?
        let error: String?
        let instance: InstanceInfo?

        struct InstanceInfo: Decodable {
            let id: String
            let name: String?
        }
    }

    /// Ouvre la page d'achat "Get Pro" dans le navigateur par défaut.
    func openGetProPage() {
        NSWorkspace.shared.open(Self.getProCheckoutURL)
    }

    /// Valide une clé de licence saisie par l'utilisateur (synchrone pour le code démo "1234").
    /// - Parameter code: La clé saisie dans les paramètres.
    /// - Returns: Un tuple contenant le statut de succès et un message explicatif pour l'interface.
    @discardableResult
    func validate(code: String) -> (success: Bool, message: String) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            return (false, loc("license.err_empty"))
        }

        // Code de démonstration local ("1234") ou clé de test Lemon Squeezy ("LP-PRO-...")
        if trimmed == "1234" || trimmed.uppercased().hasPrefix("LP-PRO-") || trimmed.uppercased().hasPrefix("TEST-") {
            unlockLifetimePro(licenseKey: trimmed)
            licenseInstanceId = "demo-local-instance"
            return (true, loc("license.success"))
        }

        return (false, loc("license.err_invalid"))
    }

    /// Active une clé de licence réelle en ligne via l'API Lemon Squeezy (supporte les packs 1, 2 et 5 Macs)
    /// tout en conservant le code "1234" pour les tests locaux.
    func activateLicenseOnline(code: String) async -> (success: Bool, message: String) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            return (false, loc("license.err_empty"))
        }

        // 1. Test immédiat si c'est le code démo "1234" ou clé de test Lemon Squeezy
        if trimmed == "1234" || trimmed.uppercased().hasPrefix("LP-PRO-") || trimmed.uppercased().hasPrefix("TEST-") {
            return validate(code: trimmed)
        }

        // 2. Appel réseau vers l'API officielle Lemon Squeezy Licenses
        isValidatingOnline = true
        defer { isValidatingOnline = false }

        guard let url = URL(string: "https://api.lemonsqueezy.com/v1/licenses/activate") else {
            return (false, loc("license.err_invalid"))
        }

        let hostName = Host.current().localizedName ?? "MacBook-LaunchPad"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: String] = [
            "license_key": trimmed,
            "instance_name": hostName
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResp = response as? HTTPURLResponse else {
                return (false, loc("license.err_invalid"))
            }

            if let decoded = try? JSONDecoder().decode(LemonSqueezyActivationResponse.self, from: data) {
                if decoded.activated == true || decoded.valid == true, (200...299).contains(httpResp.statusCode) {
                    unlockLifetimePro(licenseKey: trimmed)
                    if let instId = decoded.instance?.id {
                        licenseInstanceId = instId
                    }
                    return (true, loc("license.success"))
                } else if let apiError = decoded.error, !apiError.isEmpty {
                    return (false, apiError)
                }
            }
            return (false, loc("license.err_invalid"))
        } catch {
            return (false, loc("license.err_invalid"))
        }
    }

    /// Réinitialise l'application en version gratuite et libère l'emplacement Mac sur Lemon Squeezy si applicable.
    func deactivate() {
        stopCountdownTicker()
        let currentKey = licenseKey
        let currentInstance = licenseInstanceId

        isProLifetime = false
        isTrialActive = false
        isPro = false
        licenseKey = ""
        licenseInstanceId = ""
        trialStartDate = nil
        trialEndDate = nil
        timeRemainingString = ""
        trialProgress = 0.0

        Prefs.isProLifetime = false
        Prefs.isTrialActive = false
        Prefs.isProUnlocked = false
        Prefs.trialStartDate = nil
        Prefs.trialEndDate = nil

        NotificationCenter.default.post(name: .trialStatusDidChange, object: nil)

        if Prefs.appLogo.isProOnly {
            Prefs.defaults.set(AppLogo.noir.rawValue, forKey: PrefKey.appLogo)
            NSApp.applicationIconImage = AppLogo.noir.image
        }

        // Libération asynchrone du poste sur Lemon Squeezy (pour les licences 1, 2 ou 5 appareils)
        if !currentKey.isEmpty, currentKey != "1234", !currentInstance.isEmpty {
            Task.detached {
                guard let url = URL(string: "https://api.lemonsqueezy.com/v1/licenses/deactivate") else { return }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let body = ["license_key": currentKey, "instance_id": currentInstance]
                request.httpBody = try? JSONSerialization.data(withJSONObject: body)
                _ = try? await URLSession.shared.data(for: request)
            }
        }
    }

    // =========================================================================
    // MARK: - Méthodes de Test & Simulation (Admin)
    // =========================================================================

    /// Simule un essai se terminant dans un nombre d'heures donné (pour tester le décompte).
    func simulateTrialEndingIn(hours: Double) {
        if isProLifetime { return }
        let now = Date()
        let end = now.addingTimeInterval(hours * 3600)
        let start = now.addingTimeInterval(-((7 * 24) - hours) * 3600)

        self.trialStartDate = start
        self.trialEndDate = end
        self.isTrialActive = true
        self.isPro = true
        self.hasUsedTrial = true

        Prefs.trialStartDate = start
        Prefs.trialEndDate = end
        Prefs.isTrialActive = true
        Prefs.hasUsedTrial = true
        Prefs.isProUnlocked = true

        updateCountdownValues()
        startCountdownTicker()
        NotificationCenter.default.post(name: .trialStatusDidChange, object: nil)
    }

    /// Simule l'expiration immédiate de l'essai de 7 jours.
    func simulateTrialExpired() {
        if isProLifetime { return }
        handleTrialExpiration(notify: true)
    }

    /// Réinitialise l'historique d'essai pour permettre de retester le tutoriel comme au premier jour.
    func resetTrialHistory() {
        deactivate()
        hasUsedTrial = false
        Prefs.hasUsedTrial = false
    }
}
