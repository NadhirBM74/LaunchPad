import Foundation
import Combine
import AppKit
import Security
import Collaboration
import OpenDirectory

// MARK: - Persistance Indestructible dans le Trousseau d'Accès (Keychain)
// Garantit que même si l'utilisateur supprime l'application (ou les préférences UserDefaults)
// et la réinstalle, la date et le décompte exact de son essai gratuit restent préservés.

nonisolated enum KeychainTrialStorage {
    private static let service = "me.LaucnhPad.trial"
    private static let account = "device_trial_info"

    nonisolated static func save(startDate: Date, endDate: Date, hasUsed: Bool) {
        let dict: [String: Any] = [
            "start": startDate.timeIntervalSince1970,
            "end": endDate.timeIntervalSince1970,
            "hasUsed": hasUsed
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    nonisolated static func load() -> (startDate: Date, endDate: Date, hasUsed: Bool)? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data,
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let startTs = dict["start"] as? TimeInterval,
              let endTs = dict["end"] as? TimeInterval,
              let hasUsed = dict["hasUsed"] as? Bool else {
            return nil
        }
        return (Date(timeIntervalSince1970: startTs), Date(timeIntervalSince1970: endTs), hasUsed)
    }

    nonisolated static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func saveInBackground(startDate: Date, endDate: Date, hasUsed: Bool) {
        Task.detached(priority: .utility) {
            save(startDate: startDate, endDate: endDate, hasUsed: hasUsed)
        }
    }

    static func clearInBackground() {
        Task.detached(priority: .utility) {
            clear()
        }
    }
}

/// État isolé du décompte seconde par seconde de l'essai 7 jours.
/// Évite d'invalider toute l'application quand seul le compteur change chaque seconde.
@MainActor
final class TrialCountdownState: ObservableObject {
    @Published fileprivate(set) var timeRemainingString: String = ""
    @Published fileprivate(set) var trialDaysRemaining: Int = 0
    @Published fileprivate(set) var trialHoursRemaining: Int = 0
    @Published fileprivate(set) var trialMinutesRemaining: Int = 0
    @Published fileprivate(set) var trialSecondsRemaining: Int = 0
    @Published fileprivate(set) var trialProgress: Double = 0.0
}

/// Gestionnaire de la licence et de l'état Freemium de l'application.
///
/// Trois états sont pris en charge :
/// - **Version gratuite** : fonctionnalités de base actives, thèmes Sombre et Clair.
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

    let countdown = TrialCountdownState()

    var timeRemainingString: String { countdown.timeRemainingString }
    var trialDaysRemaining: Int { countdown.trialDaysRemaining }
    var trialHoursRemaining: Int { countdown.trialHoursRemaining }
    var trialMinutesRemaining: Int { countdown.trialMinutesRemaining }
    var trialSecondsRemaining: Int { countdown.trialSecondsRemaining }
    var trialProgress: Double { countdown.trialProgress }

    // MARK: - Profil du Compte Apple / macOS (Photo & Prénom)
    @Published private(set) var appleAccountFirstName: String = ""
    @Published private(set) var appleAccountAvatar: NSImage? = nil

    private var countdownTimer: Timer?
    private var activeCountdownObservers: Int = 0
    private var expirationWatchdogTask: Task<Void, Never>?
    private var hasLoadedAppleProfile = false

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
        let loadedLicenseKey = Prefs.licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let loadedIsProLifetime = Prefs.isProLifetime && !loadedLicenseKey.isEmpty

        // Lecture instantanée depuis UserDefaults au démarrage, puis réconciliation Keychain hors fil principal.
        let loadedTrialStartDate = Prefs.trialStartDate
        let loadedTrialEndDate = Prefs.trialEndDate
        let loadedHasUsedTrial = Prefs.hasUsedTrial
        let loadedIsTrialActive = Prefs.isTrialActive

        let trialValid = loadedIsTrialActive && (loadedTrialEndDate ?? Date.distantPast) > Date()
        let calculatedIsPro = loadedIsProLifetime || trialValid

        self.isPro = calculatedIsPro
        self.licenseKey = loadedLicenseKey
        self.isProLifetime = loadedIsProLifetime
        self.isTrialActive = trialValid
        self.trialStartDate = loadedTrialStartDate
        self.trialEndDate = loadedTrialEndDate
        self.hasUsedTrial = loadedHasUsedTrial

        if Prefs.isProUnlocked != calculatedIsPro { Prefs.isProUnlocked = calculatedIsPro }
        if Prefs.isTrialActive != trialValid { Prefs.isTrialActive = trialValid }

        // Si l'essai était marqué actif mais est expiré à l'ouverture, on nettoie
        if loadedIsTrialActive && !loadedIsProLifetime {
            if let end = loadedTrialEndDate, Date() >= end {
                handleTrialExpiration(notify: false)
            } else if trialValid {
                updateCountdownValues()
                scheduleExpirationWatchdog()
            }
        }

        // Ne pas bloquer le démarrage avec le Trousseau si la licence/essai est déjà connu localement
        if !loadedIsProLifetime && (loadedTrialStartDate == nil || loadedTrialEndDate == nil || !loadedHasUsedTrial) {
            reconcileKeychainInBackground(
                cachedStart: loadedTrialStartDate,
                cachedEnd: loadedTrialEndDate,
                cachedHasUsed: loadedHasUsedTrial
            )
        }
        // Nom instantané sans IPC OpenDirectory ; l'avatar haute résolution est chargé paresseusement à l'ouverture des Réglages.
        let userName = NSUserName()
        let fallbackFull = NSFullUserName()
        self.appleAccountFirstName = Self.extractFirstName(from: fallbackFull)
            ?? (userName.prefix(1).uppercased() + userName.dropFirst())
    }

    private func reconcileKeychainInBackground(cachedStart: Date?, cachedEnd: Date?, cachedHasUsed: Bool) {
        Task.detached(priority: .utility) { [weak self] in
            if let keychain = KeychainTrialStorage.load() {
                if cachedStart == nil || cachedEnd == nil || !cachedHasUsed {
                    await MainActor.run { [weak self] in
                        guard let self, !self.isProLifetime else { return }
                        let trialValid = keychain.hasUsed && Date() < keychain.endDate
                        self.trialStartDate = keychain.startDate
                        self.trialEndDate = keychain.endDate
                        self.hasUsedTrial = keychain.hasUsed
                        self.isTrialActive = trialValid
                        self.isPro = trialValid
                        Prefs.trialStartDate = keychain.startDate
                        Prefs.trialEndDate = keychain.endDate
                        Prefs.hasUsedTrial = keychain.hasUsed
                        Prefs.isTrialActive = trialValid
                        if trialValid {
                            self.updateCountdownValues()
                            self.scheduleExpirationWatchdog()
                            if self.activeCountdownObservers > 0 {
                                self.startCountdownTicker()
                            }
                        } else if keychain.hasUsed {
                            self.handleTrialExpiration(notify: false)
                        }
                    }
                }
            } else if let start = cachedStart, let end = cachedEnd {
                KeychainTrialStorage.save(startDate: start, endDate: end, hasUsed: cachedHasUsed)
            }
        }
    }

    /// Charge paresseusement le profil Apple (avatar + prénom OpenDirectory) uniquement lorsque les Réglages sont ouverts.
    func loadAppleAccountProfileIfNeeded() {
        guard !hasLoadedAppleProfile else { return }
        hasLoadedAppleProfile = true
        loadAppleAccountProfile()
    }

    /// Extrait la photo de profil et le prénom du compte Apple / macOS local sans bloquer le thread principal au démarrage.
    func loadAppleAccountProfile() {
        hasLoadedAppleProfile = true
        let userName = NSUserName()
        let fallbackFull = NSFullUserName()
        self.appleAccountFirstName = Self.extractFirstName(from: fallbackFull)
            ?? (userName.prefix(1).uppercased() + userName.dropFirst())

        Task.detached(priority: .utility) { [weak self] in
            var extractedFirstName: String? = nil
            var extractedAvatarData: Data? = nil
            var extractedPicPath: String? = nil

            if let node = try? ODNode(session: .default(), type: ODNodeType(kODNodeTypeLocalNodes)),
               let record = try? node.record(withRecordType: kODRecordTypeUsers, name: userName, attributes: nil),
               let attrs = try? record.recordDetails(forAttributes: [
                    kODAttributeTypeFirstName,
                    kODAttributeTypeFullName,
                    kODAttributeTypeJPEGPhoto,
                    kODAttributeTypePicture
               ]) {
                if let firstArr = attrs[kODAttributeTypeFirstName] as? [Any],
                   let firstVal = firstArr.first as? String,
                   !firstVal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    extractedFirstName = firstVal.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if extractedFirstName == nil,
                   let fullArr = attrs[kODAttributeTypeFullName] as? [Any],
                   let fullVal = fullArr.first as? String,
                   !fullVal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    extractedFirstName = Self.extractFirstName(from: fullVal)
                }
                if let photoArr = attrs[kODAttributeTypeJPEGPhoto] as? [Any],
                   let photoData = photoArr.first as? Data {
                    extractedAvatarData = photoData
                }
                if extractedAvatarData == nil,
                   let picArr = attrs[kODAttributeTypePicture] as? [Any],
                   let picPath = picArr.first as? String {
                    extractedPicPath = picPath
                }
            }

            if extractedAvatarData == nil && extractedPicPath == nil,
               let identity = CBIdentity(name: userName, authority: .default()) {
                if let tiff = identity.image?.tiffRepresentation {
                    extractedAvatarData = tiff
                }
                if extractedFirstName == nil, !identity.fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    extractedFirstName = Self.extractFirstName(from: identity.fullName)
                }
            }

            let resolvedFirstName = extractedFirstName
            let resolvedAvatar = extractedAvatarData.flatMap { NSImage(data: $0) }
                ?? extractedPicPath.flatMap { NSImage(contentsOfFile: $0) }

            await MainActor.run { [weak self] in
                guard let self else { return }
                if let resolvedFirstName {
                    self.appleAccountFirstName = resolvedFirstName
                }
                if let resolvedAvatar {
                    self.appleAccountAvatar = resolvedAvatar
                }
            }
        }
    }

    nonisolated private static func extractFirstName(from fullName: String) -> String? {
        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let first = trimmed.components(separatedBy: .whitespacesAndNewlines).first(where: { !$0.isEmpty }) ?? trimmed
        return first
    }

    // =========================================================================
    // MARK: - Gestion de l'Essai 7 Jours & Décompte
    // =========================================================================

    /// Démarre un essai gratuit de 7 jours avec toutes les fonctionnalités Pro actives.
    func startSevenDayTrial() {
        if isProLifetime {
            return // Déjà pro permanent
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

        // Persistance indestructible dans le Keychain de macOS (survit à la désinstallation)
        KeychainTrialStorage.saveInBackground(startDate: now, endDate: end, hasUsed: true)

        updateCountdownValues()
        scheduleExpirationWatchdog()
        if activeCountdownObservers > 0 {
            startCountdownTicker()
        }

        AppNotificationManager.shared.sendTrialStartedNotification(days: 7)
        NotificationCenter.default.post(name: .trialStatusDidChange, object: nil)
        AdminManager.shared.log(category: "Licence", message: "Essai gratuit de 7 jours activé jusqu'au \(end.formatted(date: .abbreviated, time: .shortened))")
    }

    func beginCountdownObservation() {
        activeCountdownObservers += 1
        if isTrialActive && !isProLifetime {
            updateCountdownValues()
            if countdownTimer == nil {
                startCountdownTicker()
            }
        }
    }

    func endCountdownObservation() {
        activeCountdownObservers = max(0, activeCountdownObservers - 1)
        if activeCountdownObservers == 0 {
            stopCountdownTicker()
        }
    }

    private func scheduleExpirationWatchdog() {
        expirationWatchdogTask?.cancel()
        expirationWatchdogTask = nil
        guard isTrialActive, !isProLifetime, let end = trialEndDate else { return }
        expirationWatchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                let remaining = end.timeIntervalSinceNow
                if remaining <= 0 {
                    await MainActor.run { [weak self] in
                        self?.checkTrialStatus()
                    }
                    break
                }
                let step = min(remaining, 3600)
                try? await Task.sleep(for: .seconds(step))
            }
        }
    }

    /// Démarre le minuteur qui rafraîchit le compte à rebours chaque seconde uniquement lorsqu'une UI l'affiche.
    private func startCountdownTicker() {
        guard activeCountdownObservers > 0 else { return }
        countdownTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateCountdownValues()
            }
        }
        timer.tolerance = 0.25
        countdownTimer = timer
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
        let newProgress = min(1.0, max(0.0, elapsed / totalDuration))
        if abs(countdown.trialProgress - newProgress) >= 0.0005 {
            countdown.trialProgress = newProgress
        }

        let totalSeconds = Int(remaining)
        let days = totalSeconds / 86400
        let hours = (totalSeconds % 86400) / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        // Ne déclenche pas d'invalidation SwiftUI si la seconde affichée n'a pas changé (sauf changement de langue)
        let langCode = LocalizationManager.activeLanguageCode
        let expectedString: String = days > 0
            ? loc("license.countdown_days_fmt", days, hours, minutes, seconds)
            : loc("license.countdown_hms_fmt", hours, minutes, seconds)
        if countdown.trialSecondsRemaining != seconds || countdown.trialMinutesRemaining != minutes || countdown.trialHoursRemaining != hours || countdown.trialDaysRemaining != days || countdown.timeRemainingString != expectedString {
            let _ = langCode
            countdown.trialDaysRemaining = days
            countdown.trialHoursRemaining = hours
            countdown.trialMinutesRemaining = minutes
            countdown.trialSecondsRemaining = seconds
            countdown.timeRemainingString = expectedString
        }
    }

    /// Traite l'expiration de l'essai de 7 jours et remet l'application en version gratuite.
    private func handleTrialExpiration(notify: Bool = true) {
        stopCountdownTicker()
        expirationWatchdogTask?.cancel()
        expirationWatchdogTask = nil

        self.isTrialActive = false
        self.isPro = false
        countdown.timeRemainingString = loc("license.expired_status")
        countdown.trialDaysRemaining = 0
        countdown.trialHoursRemaining = 0
        countdown.trialMinutesRemaining = 0
        countdown.trialSecondsRemaining = 0
        countdown.trialProgress = 1.0

        Prefs.defaults.removeObject(forKey: PrefKey.isTrialActive)
        Prefs.defaults.removeObject(forKey: PrefKey.trialStartDate)
        Prefs.defaults.removeObject(forKey: PrefKey.trialEndDate)

        // Maintien permanent de l'état "essai consommé" dans le trousseau Keychain
        KeychainTrialStorage.saveInBackground(
            startDate: self.trialStartDate ?? Date.distantPast,
            endDate: self.trialEndDate ?? Date(),
            hasUsed: true
        )

        // Rétablissement des réglages de base si des éléments Pro étaient sélectionnés
        resetProOnlyPreferencesToFreeDefaults()

        AdminManager.shared.log(category: "Licence", message: "Essai gratuit de 7 jours expiré : retour automatique en version gratuite.")

        if notify {
            AppNotificationManager.shared.sendTrialExpiredNotification()
            NotificationCenter.default.post(name: .trialDidExpire, object: nil)
        }
        NotificationCenter.default.post(name: .trialStatusDidChange, object: nil)
        NotificationCenter.default.post(name: .launchpadVisibilityDidChange, object: nil)
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
        countdown.timeRemainingString = ""

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

    /// Annule manuellement l'essai gratuit en cours et repasse l'application en mode gratuit.
    func cancelTrial() {
        guard isTrialActive else { return }
        AdminManager.shared.log(category: "Licence", message: "Essai gratuit de 7 jours annulé par l'utilisateur.")
        deactivate()
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
        countdown.timeRemainingString = ""
        countdown.trialDaysRemaining = 0
        countdown.trialHoursRemaining = 0
        countdown.trialMinutesRemaining = 0
        countdown.trialSecondsRemaining = 0
        countdown.trialProgress = 0.0

        Prefs.isProLifetime = false
        Prefs.isTrialActive = false
        Prefs.defaults.removeObject(forKey: PrefKey.licenseKey)
        Prefs.defaults.removeObject(forKey: PrefKey.trialStartDate)
        Prefs.defaults.removeObject(forKey: PrefKey.trialEndDate)
        UserDefaults.standard.removeObject(forKey: instanceIdKey)

        expirationWatchdogTask?.cancel()
        expirationWatchdogTask = nil
        resetProOnlyPreferencesToFreeDefaults()

        NotificationCenter.default.post(name: .trialStatusDidChange, object: nil)
        NotificationCenter.default.post(name: .launchpadVisibilityDidChange, object: nil)

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

    private func resetProOnlyPreferencesToFreeDefaults() {
        if Prefs.appLogo.isProOnly {
            Prefs.defaults.set(AppLogo.noir.rawValue, forKey: PrefKey.appLogo)
            NSApp.applicationIconImage = AppLogo.noir.image
        }
        if Prefs.backgroundStyle == .liquidGlass {
            Prefs.defaults.set(AppTheme.dark.rawValue, forKey: PrefKey.backgroundStyle)
        }
        let rawIconStyle = Prefs.defaults.string(forKey: PrefKey.iconStyle) ?? "original"
        if (IconAppearanceStyle(rawValue: rawIconStyle)?.requiresPro == true) || Prefs.tintedIcons {
            Prefs.defaults.set(IconAppearanceStyle.original.rawValue, forKey: PrefKey.iconStyle)
            Prefs.defaults.set(false, forKey: PrefKey.tintedIcons)
            IconCache.shared.removeAll()
            NotificationCenter.default.post(name: .launchpadIconStyleDidChange, object: nil)
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

        KeychainTrialStorage.saveInBackground(startDate: start, endDate: end, hasUsed: true)

        updateCountdownValues()
        scheduleExpirationWatchdog()
        if activeCountdownObservers > 0 {
            startCountdownTicker()
        }
        NotificationCenter.default.post(name: .trialStatusDidChange, object: nil)
    }

    /// Simule l'expiration immédiate de l'essai de 7 jours.
    func simulateTrialExpired() {
        if isProLifetime { return }
        handleTrialExpiration(notify: true)
    }

    /// Réinitialise l'historique d'essai pour permettre de retester le tutoriel comme au premier jour (Admin).
    func resetTrialHistory() {
        deactivate()
        hasUsedTrial = false
        Prefs.hasUsedTrial = false
        KeychainTrialStorage.clearInBackground()
    }
}
