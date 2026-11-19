import Foundation
import AppKit
import UserNotifications
import ImageIO
import UniformTypeIdentifiers

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

    /// Prépare de façon asynchrone le logo actif de LaunchPad en PNG pour les notifications.
    nonisolated private static let logoCacheLock = NSLock()
    nonisolated(unsafe) private static var cachedLogoURLByRaw: [Int: URL] = [:]

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

        let logoRaw = Prefs.defaults.integer(forKey: PrefKey.appLogo)
        if includeLogo, let cachedLogoFileURL = Self.cachedLogoURL(forRaw: logoRaw) {
            if let attachment = try? UNNotificationAttachment(
                identifier: "launchpad-app-logo",
                url: cachedLogoFileURL,
                options: [UNNotificationAttachmentOptionsThumbnailHiddenKey: false]
            ) {
                content.attachments = [attachment]
            }
            Self.enqueueNotification(request: UNNotificationRequest(identifier: identifier, content: content, trigger: nil), title: title)
        } else if includeLogo {
            let fallbackSource = Self.sourceImage(forLogoRaw: logoRaw)
            Task.detached(priority: .utility) {
                if let fileURL = Self.writeLogoPNGInBackground(logoRaw: logoRaw, sourceImage: fallbackSource),
                   let attachment = try? UNNotificationAttachment(
                    identifier: "launchpad-app-logo",
                    url: fileURL,
                    options: [UNNotificationAttachmentOptionsThumbnailHiddenKey: false]
                   ) {
                    content.attachments = [attachment]
                }
                Self.enqueueNotification(request: UNNotificationRequest(identifier: identifier, content: content, trigger: nil), title: title)
            }
        } else {
            Self.enqueueNotification(request: UNNotificationRequest(identifier: identifier, content: content, trigger: nil), title: title)
        }
    }

    nonisolated private static func enqueueNotification(request: UNNotificationRequest, title: String) {
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

    private static func cachedLogoURL(forRaw logoRaw: Int) -> URL? {
        logoCacheLock.lock()
        let url = cachedLogoURLByRaw[logoRaw]
        logoCacheLock.unlock()
        if let url, FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        return nil
    }

    private static func sourceImage(forLogoRaw logoRaw: Int) -> NSImage? {
        let appLogo = AppLogo(rawValue: logoRaw) ?? .noir
        return appLogo.image
            ?? NSImage(named: "AppIcon")
            ?? Bundle.main.image(forResource: "AppIcon")
            ?? NSApp.applicationIconImage
    }

    nonisolated private static func writeLogoPNGInBackground(logoRaw: Int, sourceImage: NSImage?) -> URL? {
        let logoFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("LaunchPadNotificationLogo_\(logoRaw).png")
        if FileManager.default.fileExists(atPath: logoFile.path) {
            logoCacheLock.lock()
            cachedLogoURLByRaw[logoRaw] = logoFile
            logoCacheLock.unlock()
            return logoFile
        }
        guard let sourceImage else { return nil }
        let pxSize = 128
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
              ) else { return nil }
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
              let dest = CGImageDestinationCreateWithURL(logoFile as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, outCG, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        logoCacheLock.lock()
        cachedLogoURLByRaw[logoRaw] = logoFile
        logoCacheLock.unlock()
        return logoFile
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
