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
    private var pendingApiAssetUrl: URL?
    private var pendingAssetExtension: String = "zip"
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

    // MARK: - Mode Debug / Test Administrateur

    public func setDebugState(_ newState: UpdateState) {
        self.state = newState
        self.lastChecked = Date()
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

    /// Récupère les métadonnées de version via une architecture ultra-résiliente multi-niveaux.
    private func fetchLatestRelease() async throws -> [String: Any]? {
        // 1. TENTATIVE PRIORITAIRE CDN HAUTE DISPONIBILITÉ :
        // raw.githubusercontent.com via Fastly Varnish CDN (réponse instantanée ~30ms, sans quota d'API et immunisé contre les 502/503/504)
        let rawEndpoint = "https://raw.githubusercontent.com/\(Self.repoOwner)/\(Self.repoName)/main/version.json"
        if let rawUrl = URL(string: rawEndpoint) {
            var rawReq = URLRequest(url: rawUrl)
            rawReq.timeoutInterval = 4
            rawReq.cachePolicy = .reloadIgnoringLocalCacheData
            rawReq.setValue("LaunchPad-App/\(currentAppVersion) (Macintosh; macOS)", forHTTPHeaderField: "User-Agent")

            if let (data, response) = try? await URLSession.shared.data(for: rawReq),
               let httpResponse = response as? HTTPURLResponse,
               (200...299).contains(httpResponse.statusCode),
               let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
               let tag = json["tag_name"] as? String, !tag.isEmpty {
                return json
            }
        }

        // 2. REPLI SUR L'API REST GITHUB (AVEC RETRY ET EN-TÊTES OPTIMISÉS)
        let apiEndpoints = [
            "https://api.github.com/repos/\(Self.repoOwner)/\(Self.repoName)/releases/latest",
            "https://api.github.com/repos/\(Self.repoOwner)/\(Self.repoName)/releases?per_page=1"
        ]

        var lastHttpCode: Int = 0

        for endpoint in apiEndpoints {
            guard let url = URL(string: endpoint) else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 6
            request.cachePolicy = .useProtocolCachePolicy
            request.setValue("LaunchPad-App/\(currentAppVersion) (Macintosh; macOS)", forHTTPHeaderField: "User-Agent")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

            for attempt in 1...2 {
                do {
                    let (data, response) = try await URLSession.shared.data(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else { continue }
                    lastHttpCode = httpResponse.statusCode

                    if httpResponse.statusCode == 200 {
                        if let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                           let tag = dict["tag_name"] as? String, !tag.isEmpty {
                            return dict
                        } else if let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]],
                                  let first = arr.first,
                                  let tag = first["tag_name"] as? String, !tag.isEmpty {
                            return first
                        }
                    } else if httpResponse.statusCode == 404 {
                        return nil
                    }
                } catch {
                    // Erreur transport réseau
                }

                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: 600_000_000)
                }
            }
        }

        if lastHttpCode > 0 {
            throw NSError(domain: "UpdateManager", code: lastHttpCode, userInfo: [
                NSLocalizedDescriptionKey: "Serveur GitHub temporairement indisponible (code \(lastHttpCode))."
            ])
        } else {
            throw NSError(domain: "UpdateManager", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Connexion impossible au serveur de mise à jour. Vérifiez votre accès internet."
            ])
        }
    }

    private func performCheck(manual: Bool) async {
        do {
            guard let json = try await fetchLatestRelease() else {
                let current = currentAppVersion
                state = .upToDate(version: current)
                lastChecked = Date()
                return
            }

            guard let tagName = json["tag_name"] as? String else {
                state = .error(message: "Données de version introuvables.")
                return
            }

            let releaseNotes = (json["body"] as? String) ?? ""
            let htmlUrlString = (json["html_url"] as? String) ?? ""
            let htmlUrl = URL(string: htmlUrlString)

            // Cherche un asset .zip (prioritaire) ou .dmg
            var directAssetUrl: URL? = nil
            var directApiUrl: URL? = nil
            var detectedExt = "zip"

            if let assets = json["assets"] as? [[String: Any]] {
                for asset in assets {
                    if let name = asset["name"] as? String,
                       name.hasSuffix(".zip"),
                       let downloadStr = asset["browser_download_url"] as? String,
                       let u = URL(string: downloadStr) {
                        directAssetUrl = u
                        detectedExt = "zip"
                        if let apiStr = asset["url"] as? String {
                            directApiUrl = URL(string: apiStr)
                        }
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
                            detectedExt = "dmg"
                            if let apiStr = asset["url"] as? String {
                                directApiUrl = URL(string: apiStr)
                            }
                            break
                        }
                    }
                }
            }

            self.pendingApiAssetUrl = directApiUrl
            self.pendingAssetExtension = detectedExt

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
        AppNotificationManager.shared.sendUpdateAvailableNotification(version: version)
    }

    private func sendReadyToRestartNotification(version: String) {
        AppNotificationManager.shared.sendNotification(
            identifier: "launchpad.update.ready.\(version)",
            title: "LaunchPad — Prêt à redémarrer 🚀",
            subtitle: "Version \(version)",
            body: "La mise à jour a été téléchargée avec succès. Cliquez pour redémarrer l'application.",
            type: .updateAvailable
        )
    }

    // MARK: - Téléchargement et Préparation

    public func downloadAndInstall() {
        guard case .updateAvailable(let version, _, let downloadUrl) = state,
              let url = downloadUrl else {
            return
        }

        let ext = url.pathExtension.isEmpty ? self.pendingAssetExtension : url.pathExtension.lowercased()
        if ext != "zip" && ext != "dmg" {
            NSWorkspace.shared.open(url)
            return
        }

        state = .downloading(progress: 0.0)
        startDownloadTask(targetUrl: url, isApiFallback: false, ext: ext, version: version)
    }

    private func startDownloadTask(targetUrl: URL, isApiFallback: Bool, ext: String, version: String) {
        var request = URLRequest(url: targetUrl)
        request.setValue("LaunchPad-Updater/\(currentAppVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/octet-stream, application/zip, */*", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 60

        let session = URLSession(configuration: .default)
        let task = session.downloadTask(with: request) { [weak self] tempUrl, response, error in
            guard let self = self else { return }

            let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? 0
            let isSuccessfulHttp = (200...299).contains(httpStatus)

            var validFile = false
            if let tempUrl = tempUrl, isSuccessfulHttp, error == nil {
                let fileSize = (try? FileManager.default.attributesOfItem(atPath: tempUrl.path)[.size] as? Int64) ?? 0
                if fileSize >= 500_000 {
                    validFile = true
                }
            }

            // Si le téléchargement échoue et qu'on a une URL API alternative directe non encore tentée
            if !validFile, !isApiFallback, let fallbackApiUrl = self.pendingApiAssetUrl, fallbackApiUrl != targetUrl {
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.startDownloadTask(targetUrl: fallbackApiUrl, isApiFallback: true, ext: ext, version: version)
                }
                return
            }

            if let error = error {
                Task { @MainActor [weak self] in
                    self?.state = .error(message: "Échec du téléchargement : \(error.localizedDescription)")
                }
                return
            }

            if !isSuccessfulHttp {
                Task { @MainActor [weak self] in
                    self?.state = .error(message: "Erreur serveur GitHub (HTTP \(httpStatus)).")
                }
                return
            }

            guard let tempUrl = tempUrl, validFile else {
                Task { @MainActor [weak self] in
                    self?.state = .error(message: "L'archive téléchargée est incomplète ou corrompue.")
                }
                return
            }

            // Déplacement immédiat et synchrone avant que URLSession ne supprime tempUrl
            let fileManager = FileManager.default
            let workDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let localArchive = workDir.appendingPathComponent("update.\(ext)")

            do {
                try fileManager.createDirectory(at: workDir, withIntermediateDirectories: true)
                try fileManager.moveItem(at: tempUrl, to: localArchive)
            } catch {
                Task { @MainActor [weak self] in
                    self?.state = .error(message: "Erreur de préparation : \(error.localizedDescription)")
                }
                return
            }

            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else { return }
                await self.performInPlaceUpdate(archiveDest: localArchive, tempDir: workDir, fileExtension: ext, version: version)
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
    private nonisolated func performInPlaceUpdate(archiveDest: URL, tempDir: URL, fileExtension: String, version: String) async {
        let fileManager = FileManager.default
        let extractedAppDir = tempDir.appendingPathComponent("Extracted")

        do {
            try fileManager.createDirectory(at: extractedAppDir, withIntermediateDirectories: true)

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

            // Recherche récursive du .app extrait
            var finalNewAppURL: URL? = nil
            if let enumerator = fileManager.enumerator(at: extractedAppDir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
                for case let itemURL as URL in enumerator {
                    if itemURL.pathExtension == "app" {
                        finalNewAppURL = itemURL
                        break
                    }
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

        # Retirer tous les attributs étendus (quarantaine, provenance) sur l'application installée finale
        /usr/bin/xattr -cr "$TARGET_APP" 2>/dev/null || true

        # Re-signature avec exigence désignée stable me.LaucnhPad pour conserver les autorisations TCC (Accessibilité)
        DEV_ID=$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null | grep "Apple Development" | head -n 1 | awk -F '"' '{print $2}')
        if [ -n "$DEV_ID" ]; then
            /usr/bin/codesign --force --deep --sign "$DEV_ID" -r='designated => identifier "me.LaucnhPad"' --identifier "me.LaucnhPad" "$TARGET_APP" 2>/dev/null || true
        else
            /usr/bin/codesign --force --deep --sign - -r='designated => identifier "me.LaucnhPad"' --identifier "me.LaucnhPad" "$TARGET_APP" 2>/dev/null || true
        fi

        # Enregistrement LaunchServices
        /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f -R -trusted "$TARGET_APP" 2>/dev/null || true

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
