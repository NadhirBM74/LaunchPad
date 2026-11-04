import Foundation
import SwiftUI
import AppKit
import UserNotifications
import Combine

/// Représente l'état du système de mise à jour.
public enum UpdateState: Equatable, Sendable {
    case idle
    case checking
    case upToDate(version: String)
    case updateAvailable(version: String, notes: String, downloadUrl: URL?)
    case downloading(progress: Double)
    case readyToRestart(version: String)
    case installing
    case error(message: String)

    public static func == (lhs: UpdateState, rhs: UpdateState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.checking, .checking), (.installing, .installing):
            return true
        case (.upToDate(let v1), .upToDate(let v2)):
            return v1 == v2
        case (.updateAvailable(let v1, _, _), .updateAvailable(let v2, _, _)):
            return v1 == v2
        case (.downloading(let p1), .downloading(let p2)):
            return abs(p1 - p2) < 0.001
        case (.readyToRestart(let v1), .readyToRestart(let v2)):
            return v1 == v2
        case (.error(let m1), .error(let m2)):
            return m1 == m2
        default:
            return false
        }
    }
}

/// Gestionnaire central des mises à jour logicielles avec auto-installation.
@MainActor
public final class UpdateManager: NSObject, ObservableObject {
    public static let shared = UpdateManager()

    public static let repoOwner = "NadhirBM74"
    public static let repoName = "LaunchPad"

    @Published public private(set) var state: UpdateState = .idle
    @Published public private(set) var lastChecked: Date? {
        didSet {
            if let lastChecked {
                UserDefaults.standard.set(lastChecked, forKey: "LaunchpadLastUpdateCheckDate")
            }
        }
    }
    @Published public var autoCheckEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoCheckEnabled, forKey: PrefKey.autoCheckUpdates)
        }
    }

    private var activeDownloadTask: URLSessionDownloadTask?
    private var downloadObservation: NSKeyValueObservation?
    private var notificationDelegateProxy: NotificationDelegateProxy?
    private var stagedUpdateContext: (tempDir: URL, newAppURL: URL, targetAppPath: String)?

    override private init() {
        if UserDefaults.standard.object(forKey: PrefKey.autoCheckUpdates) == nil {
            self.autoCheckEnabled = true
        } else {
            self.autoCheckEnabled = UserDefaults.standard.bool(forKey: PrefKey.autoCheckUpdates)
        }
        self.lastChecked = UserDefaults.standard.object(forKey: "LaunchpadLastUpdateCheckDate") as? Date
        super.init()

        setupNotifications()
    }

    // MARK: - Notifications macOS

    private func setupNotifications() {
        let proxy = NotificationDelegateProxy { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleNotificationClick()
            }
        }
        self.notificationDelegateProxy = proxy
        let center = UNUserNotificationCenter.current()
        center.delegate = proxy
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private func handleNotificationClick() {
        NotificationCenter.default.post(name: .openSettingsTab, object: SettingsPanel.SettingsTab.about)
    }

    // MARK: - Vérification des mises à jour

    /// Démarre la vérification des mises à jour.
    /// - Parameter manual: Si `true`, affiche directement l'état dans l'UI même si aucune màj n'est trouvée.
    public func checkForUpdates(manual: Bool = false) {
        guard state != .checking else { return }
        state = .checking

        Task {
            await performCheck(manual: manual)
        }
    }

    private func performCheck(manual: Bool) async {
        let endpoint = "https://api.github.com/repos/\(Self.repoOwner)/\(Self.repoName)/releases/latest"
        guard let url = URL(string: endpoint) else {
            state = .error(message: "URL de mise à jour invalide.")
            return
        }

        var request = URLRequest(url: url)
        request.setValue("LaunchPad-App", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                state = .error(message: "Réponse serveur invalide.")
                return
            }

            if httpResponse.statusCode == 404 {
                let current = currentAppVersion
                state = .upToDate(version: current)
                lastChecked = Date()
                return
            }

            guard httpResponse.statusCode == 200 else {
                state = .error(message: "Serveur GitHub : code \(httpResponse.statusCode).")
                return
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else {
                state = .error(message: "Données de version introuvables.")
                return
            }

            let releaseNotes = (json["body"] as? String) ?? ""
            let htmlUrlString = (json["html_url"] as? String) ?? ""
            let htmlUrl = URL(string: htmlUrlString)

            // Cherche un asset .zip (prioritaire) ou .dmg
            var directAssetUrl: URL? = nil
            if let assets = json["assets"] as? [[String: Any]] {
                for asset in assets {
                    if let name = asset["name"] as? String,
                       name.hasSuffix(".zip"),
                       let downloadStr = asset["browser_download_url"] as? String,
                       let u = URL(string: downloadStr) {
                        directAssetUrl = u
                        break
                    }
                }
                if directAssetUrl == nil {
                    for asset in assets {
                        if let name = asset["name"] as? String,
                           name.hasSuffix(".dmg"),
                           let downloadStr = asset["browser_download_url"] as? String,
                           let u = URL(string: downloadStr) {
                            directAssetUrl = u
                            break
                        }
                    }
                }
            }

            let currentVersion = currentAppVersion
            let cleanRemoteVersion = tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))

            let isNewer = cleanRemoteVersion.compare(currentVersion, options: .numeric) == .orderedDescending

            lastChecked = Date()

            if isNewer {
                let targetUrl = directAssetUrl ?? htmlUrl
                state = .updateAvailable(version: cleanRemoteVersion, notes: releaseNotes, downloadUrl: targetUrl)
                if !manual {
                    sendSystemNotification(version: cleanRemoteVersion)
                }
            } else {
                state = .upToDate(version: currentVersion)
            }
        } catch {
            state = .error(message: error.localizedDescription)
        }
    }

    public var currentAppVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    public var currentBuildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    // MARK: - Envoi des notifications macOS

    private func sendSystemNotification(version: String) {
        let content = UNMutableNotificationContent()
        content.title = "LaunchPad — Mise à jour disponible 🚀"
        content.subtitle = "Version \(version)"
        content.body = "Une nouvelle version est disponible. Ouvrez les Réglages > À propos pour l'installer."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "launchpad.update.available.\(version)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[UpdateManager] Erreur notification: \(error)")
            }
        }
    }

    private func sendReadyToRestartNotification(version: String) {
        let content = UNMutableNotificationContent()
        content.title = "LaunchPad — Mise à jour téléchargée 🚀"
        content.subtitle = "Version \(version)"
        content.body = "L'application a bien été téléchargée. Cliquez sur « Redémarrer l'application » pour finaliser l'installation."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "launchpad.update.ready.\(version)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[UpdateManager] Erreur notification: \(error)")
            }
        }
    }

    // MARK: - Téléchargement et Préparation

    public func downloadAndInstall() {
        guard case .updateAvailable(let version, _, let downloadUrl) = state,
              let url = downloadUrl else {
            return
        }

        // Si l'URL n'est ni zip ni dmg, on l'ouvre dans le navigateur
        let ext = url.pathExtension.lowercased()
        if ext != "zip" && ext != "dmg" {
            NSWorkspace.shared.open(url)
            return
        }

        state = .downloading(progress: 0.0)

        let session = URLSession(configuration: .default)
        let task = session.downloadTask(with: url) { [weak self] tempUrl, response, error in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let error {
                    self.state = .error(message: "Échec du téléchargement : \(error.localizedDescription)")
                    return
                }

                guard let tempUrl else {
                    self.state = .error(message: "Fichier temporaire manquant.")
                    return
                }

                Task.detached(priority: .userInitiated) {
                    await self.performInPlaceUpdate(archiveUrl: tempUrl, fileExtension: ext, version: version)
                }
            }
        }

        self.downloadObservation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            Task { @MainActor [weak self] in
                self?.state = .downloading(progress: progress.fractionCompleted)
            }
        }

        self.activeDownloadTask = task
        task.resume()
    }

    /// Extrait la nouvelle application et prépare le remplacement
    private nonisolated func performInPlaceUpdate(archiveUrl: URL, fileExtension: String, version: String) async {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let extractedAppDir = tempDir.appendingPathComponent("Extracted")

        do {
            try fileManager.createDirectory(at: extractedAppDir, withIntermediateDirectories: true)

            // Déplacement de l'archive téléchargée vers le dossier de travail temporaire
            let archiveDest = tempDir.appendingPathComponent("update.\(fileExtension)")
            try fileManager.moveItem(at: archiveUrl, to: archiveDest)

            if fileExtension == "zip" {
                // Extraction via ditto pour préserver les permissions et signatures
                let ditto = Process()
                ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                ditto.arguments = ["-x", "-k", archiveDest.path, extractedAppDir.path]
                try ditto.run()
                ditto.waitUntilExit()
            } else if fileExtension == "dmg" {
                // Montage silencieux du DMG pour extraire le .app
                let mountPoint = tempDir.appendingPathComponent("MountPoint")
                try fileManager.createDirectory(at: mountPoint, withIntermediateDirectories: true)

                let hdiutil = Process()
                hdiutil.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                hdiutil.arguments = ["attach", archiveDest.path, "-mountpoint", mountPoint.path, "-nobrowse", "-readonly", "-quiet"]
                try hdiutil.run()
                hdiutil.waitUntilExit()

                // Copie du LaunchPad.app monté
                let mountedApp = mountPoint.appendingPathComponent("LaunchPad.app")
                if fileManager.fileExists(atPath: mountedApp.path) {
                    let destApp = extractedAppDir.appendingPathComponent("LaunchPad.app")
                    let ditto = Process()
                    ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                    ditto.arguments = [mountedApp.path, destApp.path]
                    try ditto.run()
                    ditto.waitUntilExit()
                }

                // Démontage
                let detach = Process()
                detach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                detach.arguments = ["detach", mountPoint.path, "-quiet"]
                try? detach.run()
                detach.waitUntilExit()
            }

            // Recherche du .app extrait
            var finalNewAppURL: URL? = nil
            let items = (try? fileManager.contentsOfDirectory(at: extractedAppDir, includingPropertiesForKeys: nil)) ?? []
            for item in items {
                if item.pathExtension == "app" {
                    finalNewAppURL = item
                    break
                }
            }

            guard let newAppURL = finalNewAppURL else {
                await MainActor.run {
                    self.state = .error(message: "L'application extraite est introuvable dans l'archive.")
                }
                return
            }

            // Détermine l'emplacement cible
            var targetAppPath = Bundle.main.bundleURL.path
            // Si on exécute depuis un DMG (/Volumes/...), depuis Xcode/DerivedData ou un dossier temporaire, on installe dans /Applications/LaunchPad.app
            if targetAppPath.hasPrefix("/Volumes/") || targetAppPath.contains("DerivedData") || targetAppPath.contains("/var/folders/") || !fileManager.fileExists(atPath: targetAppPath) {
                targetAppPath = "/Applications/LaunchPad.app"
            }

            // Mise à jour de l'état : l'application est bien téléchargée et prête à être redémarrée par l'utilisateur
            await MainActor.run {
                self.stagedUpdateContext = (tempDir, newAppURL, targetAppPath)
                self.state = .readyToRestart(version: version)
                self.sendReadyToRestartNotification(version: version)
            }
        } catch {
            await MainActor.run {
                self.state = .error(message: "Erreur d'installation : \(error.localizedDescription)")
            }
        }
    }

    /// Applique la mise à jour, supprime l'ancienne version et relance la nouvelle
    public func applyUpdateAndRelaunch() {
        guard let context = stagedUpdateContext else {
            state = .error(message: "Aucune mise à jour prête à installer.")
            return
        }

        state = .installing

        let currentPID = ProcessInfo.processInfo.processIdentifier
        let scriptURL = context.tempDir.appendingPathComponent("relaunch.sh")
        let scriptContent = """
        #!/bin/bash
        exec > /tmp/launchpad_updater.log 2>&1
        set -x

        PID=\(currentPID)
        NEW_APP="\(context.newAppURL.path)"
        TARGET_APP="\(context.targetAppPath)"
        TEMP_DIR="\(context.tempDir.path)"

        # Attente polie max 3 secondes de la fermeture de l'ancien processus
        COUNT=0
        while kill -0 "$PID" 2>/dev/null; do
            sleep 0.2
            COUNT=$((COUNT + 1))
            if [ $COUNT -ge 15 ]; then
                echo "Force killing hanging PID $PID"
                kill -9 "$PID" 2>/dev/null || true
                break
            fi
        done

        # Retirer la quarantaine macOS sur la nouvelle app
        /usr/bin/xattr -r -d com.apple.quarantine "$NEW_APP" 2>/dev/null || true

        # Remplacement atomique de l'application (suppression de l'ancienne version)
        rm -rf "$TARGET_APP"
        /usr/bin/ditto "$NEW_APP" "$TARGET_APP"

        # Retirer la quarantaine macOS sur l'application installée finale
        /usr/bin/xattr -r -d com.apple.quarantine "$TARGET_APP" 2>/dev/null || true

        # Petite pause pour s'assurer que macOS a libéré les verrous de fichiers
        sleep 0.5

        # Relance de la nouvelle version
        /usr/bin/open "$TARGET_APP" || /usr/bin/open -n "$TARGET_APP"

        # Nettoyage des fichiers temporaires téléchargés
        rm -rf "$TEMP_DIR"
        """

        do {
            try scriptContent.write(to: scriptURL, atomically: true, encoding: .utf8)

            // Rendre le script exécutable
            let chmod = Process()
            chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
            chmod.arguments = ["+x", scriptURL.path]
            try chmod.run()
            chmod.waitUntilExit()

            // Lancement du script de mise à jour totalement détaché en arrière-plan
            let relaunchProcess = Process()
            relaunchProcess.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
            relaunchProcess.arguments = ["/bin/bash", scriptURL.path]
            try relaunchProcess.run()

            // Fermeture immédiate de l'application
            NSApp.terminate(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                exit(0)
            }
        } catch {
            state = .error(message: "Erreur lors du redémarrage : \(error.localizedDescription)")
        }
    }

    public func cancelDownload() {
        activeDownloadTask?.cancel()
        activeDownloadTask = nil
        downloadObservation = nil
        state = .idle
    }
}

// MARK: - Proxy Notification Delegate

private final class NotificationDelegateProxy: NSObject, UNUserNotificationCenterDelegate, Sendable {
    private let onOpen: @Sendable () -> Void

    init(onOpen: @escaping @Sendable () -> Void) {
        self.onOpen = onOpen
        super.init()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        onOpen()
        completionHandler()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }
}
