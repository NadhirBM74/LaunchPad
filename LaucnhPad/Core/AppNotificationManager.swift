import Foundation
import AppKit
import UserNotifications

/// Gestionnaire centralisé des notifications système macOS avec logo de l'application intégré.
@MainActor
public final class AppNotificationManager: NSObject, UNUserNotificationCenterDelegate {
    public static let shared = AppNotificationManager()

    public enum NotificationType: String, CaseIterable {
        case welcome = "welcome"
        case proActivated = "pro_activated"
        case backupExported = "backup_exported"
        case backupRestored = "backup_restored"
        case newApps = "new_apps"
        case tip = "tip"
        case updateAvailable = "update_available"
        case adminDiagnostic = "admin_diagnostic"
        case custom = "custom"
    }

    private let tips: [String] = [
        "Maintenez une icône enfoncée ou glissez-la sur une autre pour créer automatiquement un dossier.",
        "Ajustez la translucidité de l'effet Liquid Glass directement dans Réglages > Interface.",
        "Tapez directement au clavier dès l'ouverture du LaunchPad pour chercher instantanément une app ou un fichier.",
        "Activez les coins actifs de l'écran dans Réglages > Avancé pour ouvrir LaunchPad d'un simple geste de souris.",
        "Appuyez sur ⎋ (Échap) à tout moment pour refermer instantanément le LaunchPad."
    ]
    private var tipIndex = 0

    private override init() {
        super.init()
    }

    /// Configure le centre de notifications et s'enregistre comme délégué principal.
    public func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        requestAuthorization()
    }

    /// Demande l'autorisation d'affichage des notifications à macOS si nécessaire.
    public func requestAuthorization(completion: (@Sendable (Bool) -> Void)? = nil) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                print("[AppNotificationManager] Erreur d'autorisation : \(error)")
            }
            completion?(granted)
        }
    }

    /// Prépare le logo actif de LaunchPad en PNG temporaire pour l'attacher aux notifications.
    public static func prepareLogoAttachment() -> UNNotificationAttachment? {
        let tempDir = FileManager.default.temporaryDirectory
        let uniqueName = "LaunchPadNotificationLogo_\(UUID().uuidString).png"
        let logoFile = tempDir.appendingPathComponent(uniqueName)

        let logoRaw = Prefs.defaults.integer(forKey: PrefKey.appLogo)
        let appLogo = AppLogo(rawValue: logoRaw) ?? .noir
        let sourceImage: NSImage
        if let img = appLogo.image {
            sourceImage = img
        } else if let img = NSImage(named: "AppIcon") {
            sourceImage = img
        } else if let img = Bundle.main.image(forResource: "AppIcon") {
            sourceImage = img
        } else if let img = NSApp.applicationIconImage {
            sourceImage = img
        } else {
            return nil
        }

        // Rendu net haute définition en 512x512
        let targetSize = NSSize(width: 512, height: 512)
        let finalImage = NSImage(size: targetSize)
        finalImage.lockFocus()
        sourceImage.draw(in: NSRect(origin: .zero, size: targetSize),
                         from: NSRect(origin: .zero, size: sourceImage.size),
                         operation: .sourceOver,
                         fraction: 1.0)
        finalImage.unlockFocus()

        guard let tiffData = finalImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }

        do {
            try pngData.write(to: logoFile, options: .atomic)
            let options: [AnyHashable: Any] = [
                UNNotificationAttachmentOptionsThumbnailHiddenKey: false
            ]
            return try UNNotificationAttachment(identifier: "launchpad-app-logo", url: logoFile, options: options)
        } catch {
            print("[AppNotificationManager] Impossible de créer l'attachement du logo : \(error)")
            return nil
        }
    }

    /// Envoie une notification système native avec le logo LaunchPad inclus en miniature.
    public func sendNotification(
        identifier: String = UUID().uuidString,
        title: String,
        subtitle: String? = nil,
        body: String,
        type: NotificationType = .custom,
        sound: UNNotificationSound? = .default,
        includeLogo: Bool = true
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        if let subtitle, !subtitle.isEmpty { content.subtitle = subtitle }
        content.body = body
        content.sound = sound
        content.userInfo = ["type": type.rawValue]

        if includeLogo, let attachment = Self.prepareLogoAttachment() {
            content.attachments = [attachment]
        }

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[AppNotificationManager] Erreur envoi notification : \(error)")
            } else {
                Task { @MainActor in
                    AdminManager.shared.log(category: "Notification", message: "Notification '\(title)' transmise à macOS avec succès")
                }
            }
        }
    }

    // MARK: - Notifications Métier Utiles

    /// 1. Notification de Bienvenue & Prise en main
    public func sendWelcomeNotification() {
        let shortcut = Prefs.hotKeyEnabled ? (Prefs.defaults.string(forKey: PrefKey.hotKeyDisplay) ?? "⌃ Espace") : "⌃ Espace"
        sendNotification(
            identifier: "launchpad.welcome",
            title: "Bienvenue sur LaunchPad 🚀",
            subtitle: "Votre lanceur nouvelle génération",
            body: "Appuyez sur \(shortcut) ou pincez votre trackpad pour afficher instantanément toutes vos applications.",
            type: .welcome
        )
    }

    /// 2. Notification de déblocage de la version Pro
    public func sendProActivatedNotification() {
        sendNotification(
            identifier: "launchpad.pro.activated",
            title: "LaunchPad Pro Activé ✨",
            subtitle: "Toutes les fonctionnalités sont débloquées",
            body: "Profitez du thème Liquid Glass personnalisable, des widgets interactifs, des icônes exclusives et du multi-fenêtre !",
            type: .proActivated
        )
    }

    /// 3. Notification de sauvegarde / restauration
    public func sendBackupCompletedNotification(isExport: Bool) {
        if isExport {
            sendNotification(
                identifier: "launchpad.backup.exported",
                title: "Sauvegarde Réussie 💾",
                subtitle: "Organisation d'applications enregistrée",
                body: "Votre grille, vos dossiers et la disposition de vos widgets ont été exportés avec succès.",
                type: .backupExported
            )
        } else {
            sendNotification(
                identifier: "launchpad.backup.restored",
                title: "Restauration Terminée 🔄",
                subtitle: "Organisation restaurée avec succès",
                body: "Vos applications et widgets ont été réorganisés selon votre sauvegarde précédente.",
                type: .backupRestored
            )
        }
    }

    /// 4. Notification de détection de nouvelles applications
    public func sendNewAppsDiscoveredNotification(count: Int) {
        guard count > 0 else { return }
        let s = count > 1 ? "s" : ""
        sendNotification(
            identifier: "launchpad.apps.discovered.\(Date().timeIntervalSince1970)",
            title: "Catalogue mis à jour 📦",
            subtitle: "\(count) nouvelle\(s) application\(s)",
            body: "\(count) nouvelle\(s) application\(s) installée\(s) détectée\(s) et prête\(s) au lancement dans votre LaunchPad.",
            type: .newApps
        )
    }

    /// 5. Notification d'astuce de productivité (Tip)
    public func sendTipNotification() {
        let tip = tips[tipIndex % tips.count]
        tipIndex += 1
        sendNotification(
            identifier: "launchpad.tip.\(Date().timeIntervalSince1970)",
            title: "Astuce LaunchPad 💡",
            subtitle: "Le saviez-vous ?",
            body: tip,
            type: .tip
        )
    }

    /// 6. Notification de mise à jour disponible
    public func sendUpdateAvailableNotification(version: String) {
        sendNotification(
            identifier: "launchpad.update.available.\(version)",
            title: "Mise à jour disponible 🚀",
            subtitle: "Version \(version)",
            body: "Une nouvelle version avec améliorations et correctifs est disponible au téléchargement.",
            type: .updateAvailable
        )
    }

    /// 7. Notification de diagnostic administrateur
    public func sendAdminDiagnosticNotification() {
        sendNotification(
            identifier: "launchpad.admin.diagnostic",
            title: "Diagnostic Système LaunchPad 🛠️",
            subtitle: "Tous les sous-systèmes sont opérationnels",
            body: "Moteur de rendu 120 FPS actif, animations optimisées, cache mémoire valide.",
            type: .adminDiagnostic
        )
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Affiche la bannière même si LaunchPad est au premier plan
    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge, .list])
    }

    /// Action au clic sur la notification
    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let rawType = response.notification.request.content.userInfo["type"] as? String
        let type = NotificationType(rawValue: rawType ?? "")

        Task { @MainActor in
            switch type {
            case .welcome, .tip, .newApps:
                NotificationCenter.default.post(name: .requestOpenLaunchpad, object: nil)
            case .proActivated:
                NotificationCenter.default.post(name: .openSettingsTab, object: SettingsPanel.SettingsTab.license)
            case .backupExported, .backupRestored:
                NotificationCenter.default.post(name: .openSettingsTab, object: SettingsPanel.SettingsTab.advanced)
            case .updateAvailable:
                NotificationCenter.default.post(name: .openSettingsTab, object: SettingsPanel.SettingsTab.about)
            case .adminDiagnostic:
                NotificationCenter.default.post(name: .openAdminTestCenter, object: nil)
            case .custom, .none:
                NotificationCenter.default.post(name: .requestOpenLaunchpad, object: nil)
            }
        }
        completionHandler()
    }
}
