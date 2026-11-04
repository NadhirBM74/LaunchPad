import Foundation
import Combine
import AppKit

/// Gestionnaire de la licence et de l'état Freemium de l'application.
///
/// Deux états sont pris en charge :
/// - **Version gratuite** : fonctionnalités de base actives, thèmes Sombre et Verre flouté.
/// - **Version Pro** : débloquée par clé de licence, inclut le thème Liquid Glass, la sauvegarde complète, etc.
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

    private init() {
        self.isPro = Prefs.isProUnlocked
        self.licenseKey = Prefs.licenseKey
    }

    // =========================================================================
    // MARK: - Validation de licence (Prototype & Production)
    // =========================================================================
    //
    // ⚠️ NOTE DE DÉMONSTRATION / ARCHITECTURE :
    // Le code "1234" ci-dessous est un code de test temporaire pour le prototypage.
    // Il ne constitue PAS une protection de licence sécurisée pour la production.
    //
    // OÙ ET COMMENT REMPLACER CETTE VÉRIFICATION EN PRODUCTION :
    // -------------------------------------------------------------------------
    // 1. Remplacer le test local `trimmed == "1234"` ci-dessous par un appel API réseau :
    //    Exemple :
    //    ```swift
    //    let url = URL(string: "https://api.votre-domaine.com/v1/license/verify")!
    //    var request = URLRequest(url: url)
    //    request.httpMethod = "POST"
    //    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    //    request.httpBody = try? JSONEncoder().encode(["license_key": trimmed, "machine_id": SystemInfo.hardwareUUID])
    //    let (data, response) = try await URLSession.shared.data(for: request)
    //    // Analyser la signature cryptographique (ex: Ed25519) et le statut renvoyé par le serveur
    //    ```
    // 2. Intégrer votre plateforme de vente (Gumroad, LemonSqueezy, Stripe ou serveur dédié).
    // 3. Stocker le jeton de validation retourné de façon chiffrée dans le Trousseau d'accès (macOS Keychain)
    //    au lieu d'un simple booléen dans UserDefaults.
    // =========================================================================

    /// Valide une clé de licence saisie par l'utilisateur.
    /// - Parameter code: La clé saisie dans les paramètres.
    /// - Returns: Un tuple contenant le statut de succès et un message explicatif pour l'interface.
    @discardableResult
    func validate(code: String) -> (success: Bool, message: String) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            return (false, loc("license.err_empty"))
        }

        // --- DÉBUT DU BLOC À REMPLACER PAR VOTRE VÉRIFICATION SERVEUR ---
        if trimmed == "1234" {
            isPro = true
            licenseKey = trimmed
            return (true, loc("license.success"))
        } else {
            return (false, loc("license.err_invalid"))
        }
        // --- FIN DU BLOC TEMPORAIRE ---
    }

    /// Réinitialise l'application en version gratuite (permet de retester facilement les deux états).
    func deactivate() {
        isPro = false
        licenseKey = ""
        if Prefs.appLogo.isProOnly {
            Prefs.defaults.set(AppLogo.noir.rawValue, forKey: PrefKey.appLogo)
            NSApp.applicationIconImage = AppLogo.noir.image
        }
    }
}
