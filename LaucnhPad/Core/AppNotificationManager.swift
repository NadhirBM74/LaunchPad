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
        case trialStarted = "trial_started"
        case trialExpired = "trial_expired"
        case backupExported = "backup_exported"
        case backupRestored = "backup_restored"
        case newApps = "new_apps"
        case tip = "tip"
        case updateAvailable = "update_available"
        case widgetAdded = "widget_added"
        case adminDiagnostic = "admin_diagnostic"
        case custom = "custom"
    }

    private var tips: [String] {
        [
            loc("notif.tip.1"),
            loc("notif.tip.2"),
            loc("notif.tip.3"),
            loc("notif.tip.4"),
            loc("notif.tip.5")
        ]
    }
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

    private static var cachedLogoPNGByRaw: [Int: Data] = [:]

    /// Génère (et met en cache) les octets PNG 512×512 du logo actif via CoreGraphics sans utiliser `lockFocus`.
    private static func cachedLogoPNGData() -> Data? {
        let logoRaw = Prefs.defaults.integer(forKey: PrefKey.appLogo)
        if let cached = cachedLogoPNGByRaw[logoRaw] {
            return cached
        }

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

        let pxSize = 512
        var proposed = NSRect(origin: .zero, size: NSSize(width: pxSize, height: pxSize))
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: nil,
                  width: pxSize,
                  height: pxSize,
                  bitsPerComponent: 8,
                  bytesPerRow: pxSize * 4,
                  space: cs,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }
        ctx.interpolationQuality = .high
        if let srcCG = sourceImage.cgImage(forProposedRect: &proposed, context: nil, hints: [.interpolation: NSImageInterpolation.high.rawValue]) {
            ctx.draw(srcCG, in: CGRect(x: 0, y: 0, width: pxSize, height: pxSize))
        } else {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            sourceImage.draw(in: NSRect(x: 0, y: 0, width: pxSize, height: pxSize), from: .zero, operation: .sourceOver, fraction: 1.0)
            NSGraphicsContext.restoreGraphicsState()
        }

        guard let outCG = ctx.makeImage(),
              let pngData = NSBitmapImageRep(cgImage: outCG).representation(using: .png, properties: [:]) else {
            return nil
        }
        cachedLogoPNGByRaw[logoRaw] = pngData
        return pngData
    }

    /// Prépare le logo actif de LaunchPad en PNG temporaire pour l'attacher aux notifications.
    public static func prepareLogoAttachment() -> UNNotificationAttachment? {
        guard let pngData = cachedLogoPNGData() else { return nil }

        let tempDir = FileManager.default.temporaryDirectory
        let logoFile = tempDir.appendingPathComponent("LaunchPadNotificationLogo_\(UUID().uuidString).png")

        do {
            try pngData.write(to: logoFile, options: .atomic)
            let options: [AnyHashable: Any] = [
                UNNotificationAttachmentOptionsThumbnailHiddenKey: false
            ]
            return try UNNotificationAttachment(identifier: "launchpad-app-logo", url: logoFile, options: options)
        } catch {
            try? FileManager.default.removeItem(at: logoFile)
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
        let fallbackShortcut = "⌃ \(loc("hotkey.space"))"
        let shortcut = Prefs.hotKeyEnabled ? (Prefs.defaults.string(forKey: PrefKey.hotKeyDisplay) ?? fallbackShortcut) : fallbackShortcut
        sendNotification(
            identifier: "launchpad.welcome",
            title: loc("notif.welcome.title"),
            subtitle: loc("notif.welcome.sub"),
            body: loc("notif.welcome.body", shortcut),
            type: .welcome
        )
    }

    /// 2. Notification de déblocage de la version Pro
    public func sendProActivatedNotification() {
        sendNotification(
            identifier: "launchpad.pro.activated",
            title: loc("notif.pro_active.title"),
            subtitle: loc("notif.pro_active.sub"),
            body: loc("notif.pro_active.body"),
            type: .proActivated
        )
    }

    /// Notification d'activation de l'essai gratuit de 7 jours
    public func sendTrialStartedNotification(days: Int = 7) {
        sendNotification(
            identifier: "launchpad.trial.started",
            title: loc("notif.trial_started.title"),
            subtitle: loc("notif.trial_started.sub"),
            body: loc("notif.trial_started.body", days),
            type: .trialStarted
        )
    }

    /// Notification d'expiration de l'essai gratuit de 7 jours
    public func sendTrialExpiredNotification() {
        sendNotification(
            identifier: "launchpad.trial.expired",
            title: loc("notif.trial_ended.title"),
            subtitle: loc("notif.trial_ended.sub"),
            body: loc("notif.trial_ended.body"),
            type: .trialExpired
        )
    }

    /// 3. Notification de sauvegarde / restauration
    public func sendBackupCompletedNotification(isExport: Bool) {
        if isExport {
            sendNotification(
                identifier: "launchpad.backup.exported",
                title: loc("notif.backup_done.title"),
                subtitle: loc("notif.backup_done.sub"),
                body: loc("notif.backup_done.body"),
                type: .backupExported
            )
        } else {
            sendNotification(
                identifier: "launchpad.backup.restored",
                title: loc("notif.restore_done.title"),
                subtitle: loc("notif.restore_done.sub"),
                body: loc("notif.restore_done.body"),
                type: .backupRestored
            )
        }
    }

    /// 4. Notification de détection de nouvelles applications
    public func sendNewAppsDiscoveredNotification(count: Int) {
        guard count > 0 else { return }
        sendNotification(
            identifier: "launchpad.apps.discovered.\(Date().timeIntervalSince1970)",
            title: loc("notif.catalog_updated.title"),
            subtitle: loc("notif.catalog_updated.sub", count),
            body: loc("notif.catalog_updated.body", count),
            type: .newApps
        )
    }

    /// 5. Notification d'astuce de productivité (Tip)
    public func sendTipNotification() {
        let list = tips
        let tip = list[tipIndex % list.count]
        tipIndex += 1
        sendNotification(
            identifier: "launchpad.tip.\(Date().timeIntervalSince1970)",
            title: loc("notif.tip_banner.title"),
            subtitle: loc("notif.tip_banner.sub"),
            body: tip,
            type: .tip
        )
    }

    /// 6. Notification de mise à jour disponible
    public func sendUpdateAvailableNotification(version: String) {
        sendNotification(
            identifier: "launchpad.update.available.\(version)",
            title: loc("notif.update_avail.title"),
            subtitle: loc("notif.update_avail.sub", version),
            body: loc("notif.update_avail.body"),
            type: .updateAvailable
        )
    }

    /// 7. Notification de confirmation d'ajout / mise à jour de widget
    public func sendWidgetAddedNotification(widgetName: String, replacedExisting: Bool = false) {
        sendNotification(
            identifier: "launchpad.widget.added.\(Date().timeIntervalSince1970)",
            title: replacedExisting ? loc("notif.widget_updated.title") : loc("notif.widget_added.title"),
            subtitle: widgetName,
            body: replacedExisting
                ? loc("notif.widget_replaced.body", widgetName)
                : loc("notif.widget_added.body", widgetName),
            type: .widgetAdded
        )
    }

    /// 8. Notification de diagnostic administrateur
    public func sendAdminDiagnosticNotification() {
        sendNotification(
            identifier: "launchpad.admin.diagnostic",
            title: loc("notif.test_sys.title"),
            subtitle: loc("notif.test_sys.sub"),
            body: loc("notif.test_sys.body"),
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
            case .welcome, .tip, .newApps, .widgetAdded:
                NotificationCenter.default.post(name: .requestOpenLaunchpad, object: nil)
            case .proActivated, .trialStarted, .trialExpired:
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
