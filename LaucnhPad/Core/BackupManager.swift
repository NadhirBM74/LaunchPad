import AppKit
import SQLite3
import UniformTypeIdentifiers

// MARK: - Sauvegarde / restauration

nonisolated enum PrefValue: Codable, Sendable {
    case bool(Bool), int(Int), double(Double), string(String), strings([String])

    init?(_ object: Any) {
        if let number = object as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { self = .bool(number.boolValue) }
            else if CFNumberIsFloatType(number) { self = .double(number.doubleValue) }
            else { self = .int(number.intValue) }
        } else if let string = object as? String {
            self = .string(string)
        } else if let strings = object as? [String] {
            self = .strings(strings)
        } else {
            return nil
        }
    }

    var object: Any {
        switch self {
        case .bool(let value): value
        case .int(let value): value
        case .double(let value): value
        case .string(let value): value
        case .strings(let value): value
        }
    }
}

nonisolated struct BackupFile: Codable, Sendable {
    var format = "LaucnhPad.backup"
    var version = 1
    var exportDate: Date
    var layout: LayoutFile
    var preferences: [String: PrefValue]
}

nonisolated enum BackupError: LocalizedError {
    case unreadable, unsupported, databaseNotFound, databaseUnreadable(String), launchOSNotFound, launchOSEmpty
    var errorDescription: String? {
        switch self {
        case .unreadable: "Impossible de lire le fichier de sauvegarde."
        case .unsupported: "Cette version de sauvegarde n’est pas prise en charge."
        case .databaseNotFound: "Base de données du Launchpad système introuvable (elle n’existe plus depuis macOS 26)."
        case .databaseUnreadable(let detail): "Impossible d’ouvrir la base Launchpad : \(detail)"
        case .launchOSNotFound: "Aucune disposition LaunchOS trouvée sur ce Mac."
        case .launchOSEmpty: "La disposition LaunchOS ne contient aucune app installée sur ce Mac."
        }
    }
}

@MainActor
enum BackupManager {
    static func makeBackup(store: LaunchpadStore) -> BackupFile {
        var preferences: [String: PrefValue] = [:]
        for key in PrefKey.backupKeys {
            if let object = UserDefaults.standard.object(forKey: key), let value = PrefValue(object) { preferences[key] = value }
        }
        return BackupFile(exportDate: Date(), layout: store.layoutSnapshot, preferences: preferences)
    }

    static func export(store: LaunchpadStore, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(makeBackup(store: store)).write(to: url, options: .atomic)
    }

    static func read(from url: URL) throws -> BackupFile {
        guard let data = try? Data(contentsOf: url) else { throw BackupError.unreadable }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let backup = try? decoder.decode(BackupFile.self, from: data) else { throw BackupError.unreadable }
        guard backup.format == "LaucnhPad.backup", backup.version <= 1 else { throw BackupError.unsupported }
        return backup
    }

    static func restore(_ backup: BackupFile, store: LaunchpadStore) {
        for (key, value) in backup.preferences where PrefKey.backupKeys.contains(key) {
            UserDefaults.standard.set(value.object, forKey: key)
        }
        store.importLayout(backup.layout)
        store.saveNow()
    }

    static var suggestedFileName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "LaucnhPad-Sauvegarde-\(formatter.string(from: Date())).json"
    }

    /// Importe la disposition du Launchpad système (macOS ≤ 15) en rapprochant les bundle IDs.
    static func importSystemLaunchpad(store: LaunchpadStore) throws -> (apps: Int, folders: Int) {
        let imported = try SystemLaunchpadReader.read()
        var byBundle: [String: String] = [:]
        for app in store.catalog.values { if let bundleID = app.bundleID { byBundle[bundleID] = app.id } }
        var items: [LayoutItem] = []
        var appCount = 0, folderCount = 0
        for entry in imported {
            switch entry {
            case .app(let bundleID):
                if let id = byBundle[bundleID] { items.append(.app(id)); appCount += 1 }
            case .folder(let title, let bundleIDs):
                let ids = bundleIDs.compactMap { byBundle[$0] }
                guard !ids.isEmpty else { continue }
                items.append(.folder(FolderData(id: FolderData.newID(), name: title.isEmpty ? "Sans titre" : title, apps: ids)))
                appCount += ids.count
                folderCount += 1
            }
        }
        store.importLayout(LayoutFile(items: items, hidden: Array(store.hidden), customNames: store.customNames))
        store.saveNow()
        return (appCount, folderCount)
    }
}

// MARK: - Lecture de la base Launchpad système (SQLite)

nonisolated enum SystemLaunchpadReader {
    enum Entry { case app(String), folder(String, [String]) }

    static var databaseURL: URL? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard confstr(_CS_DARWIN_USER_DIR, &buffer, buffer.count) > 0 else { return nil }
        let directory = String(cString: buffer)
        let url = URL(fileURLWithPath: directory).appendingPathComponent("com.apple.dock.launchpad/db/db")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func read() throws -> [Entry] {
        guard let url = databaseURL else { throw BackupError.databaseNotFound }
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            throw BackupError.databaseUnreadable("ouverture impossible")
        }
        defer { sqlite3_close(db) }

        struct Row { let id: Int64; let uuid: String; let type: Int64; let parent: Int64; let ordering: Int64 }
        var rows: [Row] = []
        var apps: [Int64: String] = [:]
        var groups: [Int64: String] = [:]

        func query(_ sql: String, _ body: (OpaquePointer) -> Void) throws {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                throw BackupError.databaseUnreadable(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(statement) }
            while sqlite3_step(statement) == SQLITE_ROW { body(statement) }
        }
        func text(_ statement: OpaquePointer, _ column: Int32) -> String {
            guard let pointer = sqlite3_column_text(statement, column) else { return "" }
            return String(cString: pointer)
        }

        try query("SELECT rowid, uuid, type, parent_id, ordering FROM items") { s in
            rows.append(Row(id: sqlite3_column_int64(s, 0), uuid: text(s, 1), type: sqlite3_column_int64(s, 2),
                            parent: sqlite3_column_int64(s, 3), ordering: sqlite3_column_int64(s, 4)))
        }
        try query("SELECT item_id, bundleid FROM apps") { s in apps[sqlite3_column_int64(s, 0)] = text(s, 1) }
        try query("SELECT item_id, title FROM groups") { s in groups[sqlite3_column_int64(s, 0)] = text(s, 1) }

        var children: [Int64: [Row]] = [:]
        for row in rows where row.id != row.parent { children[row.parent, default: []].append(row) }
        for key in children.keys { children[key]?.sort { $0.ordering < $1.ordering } }

        guard let root = rows.first(where: { $0.uuid == "ROOTPAGE" })
                ?? rows.filter({ $0.type == 1 }).max(by: { (children[$0.id]?.count ?? 0) < (children[$1.id]?.count ?? 0) }) else {
            throw BackupError.databaseUnreadable("racine introuvable")
        }

        func appsUnder(_ id: Int64, depth: Int = 0) -> [String] {
            guard depth < 6 else { return [] }
            return (children[id] ?? []).flatMap { row -> [String] in
                if let bundleID = apps[row.id] { return [bundleID] }
                return appsUnder(row.id, depth: depth + 1)
            }
        }

        var result: [Entry] = []
        func walk(_ id: Int64, depth: Int = 0) {
            guard depth < 6 else { return }
            for row in children[id] ?? [] {
                if let bundleID = apps[row.id] {
                    result.append(.app(bundleID))
                } else if let title = groups[row.id] {
                    result.append(.folder(title, appsUnder(row.id)))
                } else {
                    walk(row.id, depth: depth + 1) // pages
                }
            }
        }
        walk(root.id)
        return result
    }
}

// MARK: - Panneaux de fichiers

@MainActor
enum BackupPanels {
    /// Au-dessus du Launchpad et des réglages (qui peuvent être au-dessus de la barre des menus).
    static let overlayLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 4)

    static func raise(_ panel: NSSavePanel) {
        panel.level = overlayLevel
    }

    static func chooseExportURL() -> URL? {
        let panel = NSSavePanel()
        panel.title = "Exporter la sauvegarde"
        panel.message = "Choisissez où enregistrer le fichier de sauvegarde"
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = BackupManager.suggestedFileName
        raise(panel)
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseImportURL() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Importer une sauvegarde"
        panel.message = "Sélectionnez un fichier de sauvegarde LaucnhPad"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        raise(panel)
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Ajouter un dossier d’applications"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        raise(panel)
        return panel.runModal() == .OK ? panel.url : nil
    }
}

// MARK: - Import de la disposition LaunchOS (même ordre, mêmes dossiers, mêmes pages)

/// Lit la base Core Data de LaunchOS (~/Library/Application Support/LaunchOS/LaunchOS.sqlite) :
/// ZGROUPENTITY = une case de la grille (app seule ou dossier) triée par page puis ordre,
/// ZAPPENTITY = les apps de chaque case, triées par ordre.
nonisolated enum LaunchOSReader {
    struct App: Sendable {
        let path: String
        let bundleID: String?
        let alias: String?
        let hidden: Bool
    }
    enum Entry: Sendable { case app(App), folder(String, [App]) }

    static var databaseURL: URL? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/LaunchOS/LaunchOS.sqlite")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func read() throws -> [Entry] {
        guard let source = databaseURL else { throw BackupError.launchOSNotFound }
        // Copie de la base (+ journal WAL) : on ne touche jamais aux fichiers de LaunchOS, même s'il est ouvert.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("LaunchOSImport-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let copy = folder.appendingPathComponent("LaunchOS.sqlite")
        for suffix in ["", "-wal", "-shm"] {
            let from = URL(fileURLWithPath: source.path + suffix)
            if FileManager.default.fileExists(atPath: from.path) {
                try FileManager.default.copyItem(at: from, to: URL(fileURLWithPath: copy.path + suffix))
            }
        }

        var db: OpaquePointer?
        guard sqlite3_open_v2(copy.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let db else {
            throw BackupError.databaseUnreadable("ouverture impossible")
        }
        defer { sqlite3_close(db) }

        func query(_ sql: String, _ body: (OpaquePointer) -> Void) throws {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                throw BackupError.databaseUnreadable(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(statement) }
            while sqlite3_step(statement) == SQLITE_ROW { body(statement) }
        }
        func text(_ statement: OpaquePointer, _ column: Int32) -> String? {
            guard let pointer = sqlite3_column_text(statement, column) else { return nil }
            let value = String(cString: pointer)
            return value.isEmpty ? nil : value
        }

        struct Group { let id: Int64; let isFolder: Bool; let name: String }
        var groups: [Group] = []
        var appsByGroup: [Int64: [App]] = [:]

        try query("SELECT Z_PK, ZISFOLDER, ZNAME FROM ZGROUPENTITY ORDER BY ZPAGE, ZORDER") { s in
            groups.append(Group(id: sqlite3_column_int64(s, 0), isFolder: sqlite3_column_int64(s, 1) != 0, name: text(s, 2) ?? ""))
        }
        try query("SELECT ZGROUP, ZURL, ZBUNDLEID, ZALIAS, ZHIDDEN FROM ZAPPENTITY ORDER BY ZGROUP, ZORDER") { s in
            guard let urlString = text(s, 1), let url = URL(string: urlString), url.isFileURL else { return }
            let app = App(path: url.standardizedFileURL.path, bundleID: text(s, 2), alias: text(s, 3),
                          hidden: sqlite3_column_int64(s, 4) != 0)
            appsByGroup[sqlite3_column_int64(s, 0), default: []].append(app)
        }

        return groups.compactMap { group in
            guard let apps = appsByGroup[group.id], !apps.isEmpty else { return nil }
            if group.isFolder { return .folder(group.name, apps) }
            return apps.count == 1 ? .app(apps[0]) : .folder(group.name, apps)
        }
    }
}

extension BackupManager {
    /// Reprend exactement la disposition de LaunchOS (ordre, dossiers, noms personnalisés, apps masquées).
    static func importLaunchOS(store: LaunchpadStore, dryRun: Bool = false) throws -> (apps: Int, folders: Int) {
        let entries = try LaunchOSReader.read()
        func key(_ path: String) -> String { path.precomposedStringWithCanonicalMapping.lowercased() }
        var byPath: [String: String] = [:]
        var byBundle: [String: String] = [:]
        for app in store.catalog.values {
            byPath[key(app.id)] = app.id
            byPath[key(app.resolvedPath)] = app.id
            byPath[key(app.url.resolvingSymlinksInPath().path)] = app.id
            if let bundleID = app.bundleID, byBundle[bundleID] == nil { byBundle[bundleID] = app.id }
        }
        var hidden = store.hidden
        var customNames = store.customNames
        func resolve(_ app: LaunchOSReader.App) -> String? {
            let resolvedPath = URL(fileURLWithPath: app.path).resolvingSymlinksInPath().path
            guard let id = byPath[key(app.path)] ?? byPath[key(resolvedPath)] ?? app.bundleID.flatMap({ byBundle[$0] }) else { return nil }
            if app.hidden { hidden.insert(id) }
            if let alias = app.alias { customNames[id] = alias }
            return id
        }

        var items: [LayoutItem] = []
        var appCount = 0, folderCount = 0
        for entry in entries {
            switch entry {
            case .app(let app):
                if let id = resolve(app) { items.append(.app(id)); appCount += 1 }
            case .folder(let name, let apps):
                let ids = apps.compactMap(resolve)
                guard !ids.isEmpty else { continue }
                items.append(.folder(FolderData(id: FolderData.newID(), name: name.isEmpty ? "Sans titre" : name, apps: ids)))
                appCount += ids.count
                folderCount += 1
            }
        }
        guard appCount > 0 else { throw BackupError.launchOSEmpty }
        if dryRun { return (appCount, folderCount) }
        store.importLayout(LayoutFile(items: items, hidden: Array(hidden), customNames: customNames))
        store.saveNow()
        return (appCount, folderCount)
    }
}
