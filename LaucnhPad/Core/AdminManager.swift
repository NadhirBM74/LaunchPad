import Foundation
import Combine
import SwiftUI
import AppKit

/// Gestionnaire central du Mode Administrateur et de la console de tests.
@MainActor
public final class AdminManager: ObservableObject {
    public static let shared = AdminManager()

    /// Identifiants autorisés par défaut (insensible à la casse pour le nom d'utilisateur)
    public static let defaultUsername = "admin"
    public static let defaultPassword = "1234"

    @Published public private(set) var isAuthenticated: Bool = false
    @Published public private(set) var authenticatedUser: String = ""
    @Published public var testLogs: [AdminLogEntry] = []

    public struct AdminLogEntry: Identifiable, Sendable {
        public let id = UUID()
        public let timestamp: Date
        public let category: String
        public let message: String
        public let isSuccess: Bool

        public init(category: String, message: String, isSuccess: Bool = true) {
            self.timestamp = Date()
            self.category = category
            self.message = message
            self.isSuccess = isSuccess
        }
    }

    private init() {
        log(category: "Système", message: "Initialisation du gestionnaire Admin")
    }

    /// Authentification avec nom d'utilisateur et mot de passe
    @discardableResult
    public func authenticate(username: String, password: String) -> (success: Bool, message: String) {
        let trimmedUser = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedPass = password.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedUser.isEmpty, !trimmedPass.isEmpty else {
            log(category: "Auth", message: "Échec de connexion : champs vides", isSuccess: false)
            return (false, "Veuillez saisir un nom d'utilisateur et un mot de passe.")
        }

        // Autorise 'admin' / '1234'
        if (trimmedUser == "admin" || trimmedUser == "root") && (trimmedPass == "1234") {
            isAuthenticated = true
            authenticatedUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
            log(category: "Auth", message: "Connexion réussie en tant que '\(authenticatedUser)'", isSuccess: true)
            return (true, "Connexion réussie au mode Administrateur.")
        } else {
            log(category: "Auth", message: "Identifiants invalides pour l'utilisateur '\(username)'", isSuccess: false)
            return (false, "Nom d'utilisateur ou mot de passe incorrect. (Par défaut : admin / 1234)")
        }
    }

    /// Déconnexion du mode administrateur
    public func logout() {
        let prevUser = authenticatedUser
        isAuthenticated = false
        authenticatedUser = ""
        log(category: "Auth", message: "Déconnexion de l'administrateur '\(prevUser)'", isSuccess: true)
    }

    /// Ouvre la fenêtre / le menu du Centre de Test
    public func openTestCenter() {
        NotificationCenter.default.post(name: .openAdminTestCenter, object: nil)
        log(category: "TestCenter", message: "Ouverture du Centre de Test & Diagnostics")
    }

    /// Ajoute une entrée dans le journal de bord de l'administrateur
    public func log(category: String, message: String, isSuccess: Bool = true) {
        let entry = AdminLogEntry(category: category, message: message, isSuccess: isSuccess)
        testLogs.insert(entry, at: 0)
        if testLogs.count > 100 {
            testLogs.removeLast()
        }
    }

    /// Vide le journal de bord
    public func clearLogs() {
        testLogs.removeAll()
        log(category: "Système", message: "Journal de bord effacé")
    }
}
