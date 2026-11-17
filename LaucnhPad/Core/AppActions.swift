import Combine
import AppKit

// MARK: - Actions sur les applications

@MainActor
enum AppActions {
    static func open(_ app: AppInfo) {
        if app.id.hasPrefix("web:") {
            NSWorkspace.shared.open(app.url)
            return
        }
        if app.id.hasPrefix("shortcut:") {
            if let shortcutName = CustomTileManager.shared.tile(for: app.id)?.target, !shortcutName.isEmpty {
                ProcessRunner.runDetached("/usr/bin/shortcuts", ["run", shortcutName])
            }
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: app.url, configuration: configuration) { _, error in
            if error != nil {
                // Fallback avec NSWorkspace.shared.open(app.url) au cas où la configuration stricte échoue
                DispatchQueue.main.async {
                    _ = NSWorkspace.shared.open(app.url)
                }
            }
        }
    }

    static func revealInFinder(_ app: AppInfo) {
        guard !app.id.hasPrefix("web:") && !app.id.hasPrefix("shortcut:") else { return }
        NSWorkspace.shared.activateFileViewerSelecting([app.url])
    }

    /// « Lire les informations » via le Finder (nécessite l'autorisation d'automatisation, comme LaunchOS).
    static func showInfo(_ app: AppInfo) {
        let path = app.url.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Finder"
            activate
            open information window of (POSIX file "\(path)" as alias)
        end tell
        """
        ProcessRunner.runDetached("/usr/bin/osascript", ["-e", script])
    }

    static func runningInstances(of app: AppInfo) -> [NSRunningApplication] {
        guard let bundleID = app.bundleID else { return [] }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    }

    static func quit(_ app: AppInfo) { runningInstances(of: app).forEach { $0.terminate() } }
    static func forceQuit(_ app: AppInfo) { runningInstances(of: app).forEach { $0.forceTerminate() } }

    static func isInDock(_ app: AppInfo) -> Bool {
        guard let tiles = CFPreferencesCopyAppValue("persistent-apps" as CFString, "com.apple.dock" as CFString) as? [[String: Any]] else { return false }
        let target = app.url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return tiles.contains { tile in
            let data = (tile["tile-data"] as? [String: Any])?["file-data"] as? [String: Any]
            let url = (data?["_CFURLString"] as? String)?.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return url == target || url == app.url.path
        }
    }

    /// Ajoute l'app au Dock (préférences com.apple.dock puis redémarrage du Dock).
    static func addToDock(_ app: AppInfo) -> Bool {
        guard !isInDock(app) else { return false }
        let url = app.url.absoluteString
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
        let entry = "<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>\(url)</string><key>_CFURLStringType</key><integer>15</integer></dict></dict></dict>"
        Task.detached {
            _ = ProcessRunner.run("/usr/bin/defaults", ["write", "com.apple.dock", "persistent-apps", "-array-add", entry])
            _ = ProcessRunner.run("/usr/bin/killall", ["Dock"])
        }
        return true
    }
}

nonisolated enum ProcessRunner {
    /// Lance un processus et attend sa fin (à appeler hors du fil principal).
    @discardableResult
    static func run(_ launchPath: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }

    static func runDetached(_ launchPath: String, _ arguments: [String]) {
        Task.detached(priority: .userInitiated) { _ = run(launchPath, arguments) }
    }
}

// MARK: - Désinstallation (app + fichiers associés)

nonisolated struct RelatedFile: Identifiable, Hashable, Sendable {
    let url: URL
    let kind: String
    let size: Int64
    let isBundle: Bool
    let selectedByDefault: Bool
    var id: String { url.path }
}

nonisolated enum UninstallScanner {
    static func scan(app: AppInfo) -> [RelatedFile] {
        var result = [RelatedFile(url: app.url, kind: loc("app_actions.type.app"), size: size(of: app.url), isBundle: true, selectedByDefault: true)]
        guard let bundleID = app.bundleID, bundleID.count >= 3, !bundleID.contains("/"), !app.isSystem else { return result }
        let manager = FileManager.default
        let library = manager.homeDirectoryForCurrentUser.appendingPathComponent("Library", isDirectory: true)
        var seen: Set<String> = [app.url.path]

        func add(_ url: URL, _ kind: String, selected: Bool = true) {
            guard url.path.hasPrefix(library.path + "/"), manager.fileExists(atPath: url.path), seen.insert(url.path).inserted else { return }
            result.append(RelatedFile(url: url, kind: kind, size: size(of: url), isBundle: false, selectedByDefault: selected))
        }
        func entries(_ relative: String) -> [URL] {
            (try? manager.contentsOfDirectory(at: library.appendingPathComponent(relative), includingPropertiesForKeys: nil)) ?? []
        }

        let exact: [(String, String)] = [
            ("Application Support/\(bundleID)", loc("app_actions.type.support")),
            ("Caches/\(bundleID)", loc("app_actions.type.caches")),
            ("Containers/\(bundleID)", loc("app_actions.type.container")),
            ("Preferences/\(bundleID).plist", loc("app_actions.type.prefs")),
            ("Saved Application State/\(bundleID).savedState", loc("app_actions.type.saved_state")),
            ("WebKit/\(bundleID)", loc("app_actions.type.webkit")),
            ("HTTPStorages/\(bundleID)", loc("app_actions.type.http")),
            ("HTTPStorages/\(bundleID).binarycookies", loc("app_actions.type.http")),
            ("Cookies/\(bundleID).binarycookies", loc("app_actions.type.cookies")),
            ("Application Scripts/\(bundleID)", loc("app_actions.type.scripts")),
            ("Logs/\(bundleID)", loc("app_actions.type.logs")),
        ]
        for (relative, kind) in exact { add(library.appendingPathComponent(relative), kind) }

        for url in entries("Preferences") where url.lastPathComponent.hasPrefix(bundleID + ".") && url.pathExtension == "plist" {
            add(url, loc("app_actions.type.prefs"))
        }
        for url in entries("Preferences/ByHost") where url.lastPathComponent.hasPrefix(bundleID + ".") {
            add(url, loc("app_actions.type.prefs"))
        }
        for url in entries("LaunchAgents") where url.lastPathComponent.hasPrefix(bundleID) {
            add(url, loc("app_actions.type.launch_agent"))
        }
        for url in entries("Containers") where url.lastPathComponent.hasPrefix(bundleID + ".") {
            add(url, loc("app_actions.type.ext_container"))
        }
        // Les conteneurs de groupe sont souvent partagés entre apps d'un même éditeur : décochés par défaut.
        for url in entries("Group Containers") where url.lastPathComponent.hasSuffix("." + bundleID) || url.lastPathComponent == bundleID {
            add(url, loc("app_actions.type.group_container"), selected: false)
        }

        // Correspondances par nom : moins sûres, donc décochées par défaut.
        let name = app.url.deletingPathExtension().lastPathComponent
        if name.count >= 3 {
            add(library.appendingPathComponent("Application Support/\(name)"), loc("app_actions.type.support"), selected: false)
            add(library.appendingPathComponent("Caches/\(name)"), loc("app_actions.type.caches"), selected: false)
            add(library.appendingPathComponent("Logs/\(name)"), loc("app_actions.type.logs"), selected: false)
        }
        return result
    }

    static func size(of url: URL) -> Int64 {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return 0 }
        if !isDirectory.boolValue {
            return (try? manager.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        }
        guard let enumerator = manager.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey], options: [], errorHandler: { _, _ in true }) else { return 0 }
        var total: Int64 = 0
        var count = 0
        for case let file as URL in enumerator {
            total += Int64((try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0)
            count += 1
            if count > 40_000 { break } // évite de bloquer sur des bundles énormes (Xcode…)
        }
        return total
    }

    /// Met les fichiers à la corbeille ; renvoie ceux qui ont échoué.
    static func trash(_ urls: [URL]) -> [URL] {
        var failures: [URL] = []
        for url in urls {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            } catch {
                failures.append(url)
            }
        }
        return failures
    }

    /// Repli : le Finder demande lui-même le mot de passe administrateur si nécessaire (apps App Store, etc.).
    static func trashViaFinder(_ url: URL) -> Bool {
        let path = url.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = "tell application \"Finder\" to delete (POSIX file \"\(path)\" as alias)"
        return ProcessRunner.run("/usr/bin/osascript", ["-e", script]) == 0 && !FileManager.default.fileExists(atPath: url.path)
    }
}

@MainActor
final class UninstallSession: ObservableObject, Identifiable {
    let app: AppInfo
    let id = UUID()
    @Published private(set) var files: [RelatedFile] = []
    @Published var selected: Set<String> = []
    @Published private(set) var scanning = true
    @Published private(set) var working = false
    private var scanTask: Task<Void, Never>?

    init(app: AppInfo) {
        self.app = app
        self.scanTask = Task { [weak self] in
            let found = await Task.detached(priority: .userInitiated) { UninstallScanner.scan(app: app) }.value
            guard let self, !Task.isCancelled else { return }
            self.files = found
            self.selected = Set(found.filter(\.selectedByDefault).map(\.id))
            self.scanning = false
        }
    }

    deinit {
        scanTask?.cancel()
    }

    var isRunning: Bool { !AppActions.runningInstances(of: app).isEmpty }
    var selectedSize: Int64 { files.filter { selected.contains($0.id) }.reduce(0) { $0 + $1.size } }

    /// Renvoie le nombre d'éléments qui n'ont pas pu être supprimés, et si l'app elle-même a été supprimée.
    func perform() async -> (failures: Int, appRemoved: Bool) {
        working = true
        defer { working = false }
        let instances = AppActions.runningInstances(of: app)
        if !instances.isEmpty {
            instances.forEach { $0.terminate() }
            for _ in 0..<30 {
                if !instances.contains(where: { !$0.isTerminated }) { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            instances.filter { !$0.isTerminated }.forEach { $0.forceTerminate() }
        }
        let targets = files.filter { selected.contains($0.id) }.map(\.url)
        let appURL = app.url
        var failures = await Task.detached(priority: .userInitiated) { UninstallScanner.trash(targets) }.value
        if failures.contains(appURL) {
            let removed = await Task.detached(priority: .userInitiated) { UninstallScanner.trashViaFinder(appURL) }.value
            if removed { failures.removeAll { $0 == appURL } }
        }
        if failures.count < targets.count { TrashSound.play() }
        return (failures.count, !failures.contains(appURL) && targets.contains(appURL))
    }
}

@MainActor
enum TrashSound {
    private static var sound: NSSound? = {
        let path = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/dock/drag to trash.aif"
        return FileManager.default.fileExists(atPath: path) ? NSSound(contentsOfFile: path, byReference: true) : nil
    }()
    static func play() { sound?.stop(); sound?.play() }
}
