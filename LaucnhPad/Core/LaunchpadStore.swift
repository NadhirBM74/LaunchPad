import AppKit
import Combine

// MARK: - Modèle de disposition

nonisolated struct FolderData: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var apps: [String]
    var isLocked: Bool

    init(id: String, name: String, apps: [String], isLocked: Bool = false) {
        self.id = id
        self.name = name
        self.apps = apps
        self.isLocked = isLocked
    }

    enum CodingKeys: String, CodingKey {
        case id, name, apps, isLocked
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        apps = try container.decode([String].self, forKey: .apps)
        isLocked = try container.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
    }

    static func newID() -> String { "folder:" + UUID().uuidString }
}

nonisolated enum LayoutItem: Codable, Hashable, Identifiable, Sendable {
    case app(String)
    case folder(FolderData)
    case widget(CustomWidgetConfig)

    var id: String {
        switch self {
        case .app(let path): path
        case .folder(let folder): folder.id
        case .widget(let config): config.id
        }
    }
    var appID: String? { if case .app(let id) = self { return id }; return nil }
    var folder: FolderData? { if case .folder(let folder) = self { return folder }; return nil }
    var widget: CustomWidgetConfig? { if case .widget(let config) = self { return config }; return nil }
    var isFolder: Bool { folder != nil }
    var isWidget: Bool { widget != nil }

    func span(columns: Int, rows: Int) -> (cols: Int, rows: Int) {
        switch self {
        case .app, .folder:
            return (1, 1)
        case .widget(let config):
            return config.size.span(maxColumns: columns, maxRows: rows)
        }
    }

    var slotCount: Int {
        switch self {
        case .app, .folder:
            return 1
        case .widget(let config):
            return config.size.slotCount
        }
    }
}

nonisolated struct LayoutFile: Codable, Sendable {
    var version = 1
    var items: [LayoutItem]
    var hidden: [String]
    var customNames: [String: String]
}

// MARK: - Store

@MainActor
final class LaunchpadStore: ObservableObject {
    @Published private(set) var catalog: [String: AppInfo] = [:]
    /// Disposition enregistrée (peut contenir des apps absentes ou masquées : elles restent à leur place).
    @Published private(set) var items: [LayoutItem] = []
    /// Disposition affichée (uniquement les apps présentes et visibles).
    @Published private(set) var visibleItems: [LayoutItem] = []
    @Published private(set) var hidden: Set<String> = []
    @Published private(set) var customNames: [String: String] = [:]
    @Published private(set) var runningBundleIDs: Set<String> = []
    @Published private(set) var isLoading = true
    @Published private(set) var iconsVersion = 0
    /// Incrémenté à chaque modification du catalogue ou de la visibilité (cache de recherche).
    private(set) var revision = 0

    private var hasLayoutFile = false
    private var started = false
    private var scanTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var missingSince: [String: Date] = [:]
    private(set) var lastScan = Date.distantPast
    private let watcher = FolderWatcher()

    // MARK: Démarrage

    func start() {
        guard !started else { return }
        started = true
        loadFromDisk()
        updateRunningApps()
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(runningAppsChanged), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(runningAppsChanged), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(volumesChanged), name: NSWorkspace.didMountNotification, object: nil)
        center.addObserver(self, selector: #selector(volumesChanged), name: NSWorkspace.didUnmountNotification, object: nil)
        center.addObserver(self, selector: #selector(volumesChanged), name: NSWorkspace.didWakeNotification, object: nil)
        watcher.onChange = { [weak self] in self?.scheduleRefresh() }
        refresh()
    }

    @objc private func runningAppsChanged() { updateRunningApps() }
    @objc private func volumesChanged() { scheduleRefresh(delay: 1.0) }

    private func updateRunningApps() {
        let ids = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        if ids != runningBundleIDs { runningBundleIDs = ids }
    }

    func isRunning(_ app: AppInfo) -> Bool {
        guard let bundleID = app.bundleID else { return false }
        return runningBundleIDs.contains(bundleID)
    }

    // MARK: Analyse

    func refreshIfStale() {
        if Date().timeIntervalSince(lastScan) > 30 { refresh() }
    }

    func scheduleRefresh(delay: Double = 1.5) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    /// Vide le cache d'icônes et les régénère (changement de style d'icône).
    func reloadIcons() {
        IconCache.shared.removeAll()
        iconsVersion &+= 1
        refresh()
    }

    func refresh() {
        scanTask?.cancel()
        let sources = Prefs.allSources
        scanTask = Task { [weak self] in
            let scanned = await Task.detached(priority: .userInitiated) { AppScanner.scan(sources: sources) }.value
            guard let self, !Task.isCancelled else { return }
            self.apply(scanned)
            self.lastScan = Date()
            self.watcher.watch(sources.map(AppScanner.expand).filter { FileManager.default.fileExists(atPath: $0) })

            let missingIcons = scanned.map(\.id).filter { !IconCache.shared.contains($0) }
            guard !missingIcons.isEmpty else { return }
            let original = IconCache.shared.useOriginalColors
            let rendered = await Task.detached(priority: .utility) { IconRenderer.render(missingIcons, original: original) }.value
            guard !Task.isCancelled else { return }
            IconCache.shared.store(rendered)
            self.iconsVersion &+= 1
        }
    }

    private func apply(_ scanned: [AppInfo]) {
        defer { if isLoading { isLoading = false } }
        // Sécurité : une analyse vide (volume indisponible…) ne doit jamais effacer la disposition.
        guard !scanned.isEmpty else { return }

        let customApps = CustomTileManager.shared.tiles.map { CustomTileManager.shared.asAppInfo(tile: $0) }
        let allScanned = scanned + customApps

        let previous = catalog
        var newCatalog: [String: AppInfo] = [:]
        for app in allScanned { newCatalog[app.id] = app }

        // Les icônes des apps mises à jour sont régénérées.
        let changed = allScanned.filter { previous[$0.id] != nil && previous[$0.id]?.bundleID != $0.bundleID }.map(\.id)
        if !changed.isEmpty { IconCache.shared.invalidate(changed) }

        if previous != newCatalog { catalog = newCatalog }
        var updated = items

        // Les apps disparues restent 60 s dans la disposition (mise à jour en cours, etc.) avant d'être retirées.
        let now = Date()
        let placed = Set(allPlacedAppIDs(in: updated))
        var toPrune = Set<String>()
        for id in placed where newCatalog[id] == nil {
            if let since = missingSince[id] {
                if now.timeIntervalSince(since) > 60 { toPrune.insert(id) }
            } else {
                missingSince[id] = now
            }
        }
        for id in placed where newCatalog[id] != nil { missingSince[id] = nil }
        if !toPrune.isEmpty {
            updated = removing(toPrune, from: updated)
            toPrune.forEach { missingSince[$0] = nil }
        }

        // Nouvelles apps : ajoutées à la fin (ou ordre historique au premier lancement).
        let known = Set(allPlacedAppIDs(in: updated))
        var fresh = allScanned.filter { !known.contains($0.id) }
        let isSubsequentScan = hasLayoutFile && !previous.isEmpty
        if !hasLayoutFile {
            let legacy = UserDefaults.standard.stringArray(forKey: "LaunchpadSavedAppOrder") ?? []
            let rank = Dictionary(legacy.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
            fresh.sort {
                let left = rank[$0.id] ?? Int.max, right = rank[$1.id] ?? Int.max
                return left == right ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : left < right
            }
            hasLayoutFile = true
        } else {
            fresh.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        updated.append(contentsOf: fresh.map { LayoutItem.app($0.id) })

        if isSubsequentScan && !fresh.isEmpty {
            AppNotificationManager.shared.sendNewAppsDiscoveredNotification(count: fresh.count)
        }

        if updated != items || previous != newCatalog {
            commit(updated, save: updated != items)
        }
    }

    // MARK: Accès

    func displayName(_ id: String) -> String {
        if let custom = customNames[id], !custom.isEmpty { return custom }
        return catalog[id]?.name ?? (id as NSString).lastPathComponent
    }

    func isVisibleApp(_ id: String) -> Bool { catalog[id] != nil && !hidden.contains(id) }

    func visibleFolder(_ id: String) -> FolderData? {
        visibleItems.lazy.compactMap(\.folder).first { $0.id == id }
    }

    func storedFolder(containing appID: String) -> FolderData? {
        items.lazy.compactMap(\.folder).first { $0.apps.contains(appID) }
    }

    var hiddenApps: [AppInfo] {
        hidden.compactMap { catalog[$0] }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var allVisibleApps: [AppInfo] {
        allPlacedAppIDs(in: visibleItems).compactMap { catalog[$0] }
    }

    private func allPlacedAppIDs(in list: [LayoutItem]) -> [String] {
        list.flatMap { item -> [String] in
            switch item {
            case .app(let id): [id]
            case .folder(let folder): folder.apps
            case .widget: []
            }
        }
    }

    private func removing(_ ids: Set<String>, from list: [LayoutItem]) -> [LayoutItem] {
        list.compactMap { item in
            switch item {
            case .app(let id):
                return ids.contains(id) ? nil : item
            case .folder(var folder):
                folder.apps.removeAll { ids.contains($0) }
                return folder.apps.isEmpty ? nil : .folder(folder)
            case .widget:
                return item
            }
        }
    }

    private func computeVisibleItems(from list: [LayoutItem]) -> [LayoutItem] {
        list.compactMap { item in
            switch item {
            case .app(let id):
                return isVisibleApp(id) ? item : nil
            case .folder(let folder):
                let apps = folder.apps.filter(isVisibleApp)
                return apps.isEmpty ? nil : .folder(FolderData(id: folder.id, name: folder.name, apps: apps, isLocked: folder.isLocked))
            case .widget(let config):
                return config.isEnabled ? item : nil
            }
        }
    }

    private func recomputeVisible() {
        let computed = computeVisibleItems(from: items)
        if computed != visibleItems {
            visibleItems = computed
            revision &+= 1
        }
    }

    private func commit(_ newItems: [LayoutItem], save: Bool = true) {
        items = newItems
        recomputeVisible()
        if save { scheduleSave() }
    }

    // MARK: Réorganisation manuelle

    /// Déplace un élément de premier niveau à un index de la liste affichée.
    func moveItem(_ id: String, toVisibleIndex target: Int) {
        guard let from = items.firstIndex(where: { $0.id == id }) else { return }
        let others = visibleItems.filter { $0.id != id }
        let destination = max(0, min(target, others.count))
        var copy = items
        let moving = copy.remove(at: from)
        if destination == others.count {
            if let last = others.last, let index = copy.firstIndex(where: { $0.id == last.id }) {
                copy.insert(moving, at: index + 1)
            } else {
                copy.append(moving)
            }
        } else if let index = copy.firstIndex(where: { $0.id == others[destination].id }) {
            copy.insert(moving, at: index)
        } else {
            copy.append(moving)
        }
        if copy != items { commit(copy) }
    }

    /// Fusionne une app dans une autre app (nouveau dossier) ou dans un dossier existant.
    @discardableResult
    func merge(_ draggedID: String, onto targetID: String) -> String? {
        guard draggedID != targetID else { return nil }
        var copy = items
        guard let draggedIndex = copy.firstIndex(where: { $0.id == draggedID }),
              case .app(let appID) = copy[draggedIndex] else { return nil }
        copy.remove(at: draggedIndex)
        guard let targetIndex = copy.firstIndex(where: { $0.id == targetID }) else { return nil }
        switch copy[targetIndex] {
        case .app(let targetApp):
            let folder = FolderData(id: FolderData.newID(), name: suggestedFolderName(for: [targetApp, appID]), apps: [targetApp, appID])
            copy[targetIndex] = .folder(folder)
            commit(copy)
            return folder.id
        case .folder(var folder):
            folder.apps.append(appID)
            copy[targetIndex] = .folder(folder)
            commit(copy)
            return folder.id
        case .widget:
            return nil
        }
    }

    /// Crée un dossier à partir d'une sélection multiple (apps de premier niveau).
    @discardableResult
    func makeFolder(from ids: [String]) -> String? {
        let selected = Set(ids)
        let appIDs = items.compactMap { item -> String? in
            guard let id = item.appID, selected.contains(id), isVisibleApp(id) else { return nil }
            return id
        }
        guard appIDs.count >= 2, let firstIndex = items.firstIndex(where: { $0.appID == appIDs[0] }) else { return nil }
        let folder = FolderData(id: FolderData.newID(), name: suggestedFolderName(for: appIDs), apps: appIDs)
        var copy = items
        copy[firstIndex] = .folder(folder)
        let others = Set(appIDs.dropFirst())
        copy.removeAll { item in
            if let id = item.appID { return others.contains(id) }
            return false
        }
        commit(copy)
        return folder.id
    }

    /// Sort une app d'un dossier et la place juste après celui-ci.
    func removeFromFolder(_ appID: String, folderID: String) {
        guard let folderIndex = items.firstIndex(where: { $0.id == folderID }),
              case .folder(var folder) = items[folderIndex] else { return }
        var copy = items
        folder.apps.removeAll { $0 == appID }
        let remainingVisible = folder.apps.filter(isVisibleApp)
        var replacement: [LayoutItem]
        if remainingVisible.count >= 2 {
            replacement = [.folder(folder)]
        } else {
            // Comme Launchpad : un dossier qui n'a plus qu'une app disparaît.
            replacement = folder.apps.map { LayoutItem.app($0) }
        }
        copy.replaceSubrange(folderIndex...folderIndex, with: replacement)
        copy.insert(.app(appID), at: min(folderIndex + replacement.count, copy.count))
        commit(copy)
    }

    func moveInFolder(_ appID: String, folderID: String, toVisibleIndex target: Int) {
        guard let folderIndex = items.firstIndex(where: { $0.id == folderID }),
              case .folder(var folder) = items[folderIndex],
              let from = folder.apps.firstIndex(of: appID) else { return }
        let others = folder.apps.filter { $0 != appID && isVisibleApp($0) }
        let destination = max(0, min(target, others.count))
        folder.apps.remove(at: from)
        if destination == others.count {
            if let last = others.last, let index = folder.apps.firstIndex(of: last) {
                folder.apps.insert(appID, at: index + 1)
            } else {
                folder.apps.append(appID)
            }
        } else if let index = folder.apps.firstIndex(of: others[destination]) {
            folder.apps.insert(appID, at: index)
        } else {
            folder.apps.append(appID)
        }
        var copy = items
        copy[folderIndex] = .folder(folder)
        if copy != items { commit(copy) }
    }

    func renameFolder(_ folderID: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = items.firstIndex(where: { $0.id == folderID }), case .folder(var folder) = items[index] else { return }
        folder.name = trimmed.isEmpty ? "Sans titre" : trimmed
        var copy = items
        copy[index] = .folder(folder)
        commit(copy)
    }

    func ungroup(_ folderID: String) {
        guard let index = items.firstIndex(where: { $0.id == folderID }), case .folder(let folder) = items[index] else { return }
        var copy = items
        copy.replaceSubrange(index...index, with: folder.apps.map { LayoutItem.app($0) })
        commit(copy)
    }

    func ungroupAll() {
        commit(items.flatMap { item -> [LayoutItem] in
            switch item {
            case .app: [item]
            case .folder(let folder): folder.apps.map { LayoutItem.app($0) }
            case .widget: [item]
            }
        })
    }

    // MARK: Masquer / renommer / retirer

    func hide(_ ids: [String]) {
        var ids = ids
        // Masquer un dossier masque toutes ses apps.
        ids = ids.flatMap { id -> [String] in
            if let folder = items.lazy.compactMap(\.folder).first(where: { $0.id == id }) { return folder.apps }
            return [id]
        }
        hidden.formUnion(ids)
        commit(items)
    }

    func unhide(_ id: String) {
        hidden.remove(id)
        if !allPlacedAppIDs(in: items).contains(id) {
            commit(items + [.app(id)])
        } else {
            commit(items)
        }
    }

    func setCustomName(_ id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == catalog[id]?.name {
            customNames[id] = nil
        } else {
            customNames[id] = trimmed
        }
        commit(items)
    }

    /// Après une désinstallation : on retire définitivement l'app de la disposition.
    func forget(_ ids: [String]) {
        let set = Set(ids)
        hidden.subtract(set)
        set.forEach {
            customNames[$0] = nil
            catalog[$0] = nil
            if $0.hasPrefix("web:") || $0.hasPrefix("shortcut:") {
                CustomTileManager.shared.removeTile(id: $0)
            }
        }
        commit(removing(set, from: items))
    }

    /// Verrouille ou déverrouille un dossier par Touch ID (fonctionnalité Pro).
    @discardableResult
    func toggleFolderLock(_ id: String) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }),
              case .folder(var folder) = items[index] else { return false }
        folder.isLocked.toggle()
        items[index] = .folder(folder)
        commit(items)
        return folder.isLocked
    }

    /// Ajoute un signet Web ou un Raccourci Apple personnalisé (fonctionnalité Pro).
    func addCustomTile(_ tile: CustomTile) {
        let app = CustomTileManager.shared.asAppInfo(tile: tile)
        catalog[app.id] = app
        var updated = items
        if !updated.contains(where: { $0.id == tile.id }) {
            updated.append(.app(tile.id))
        }
        commit(updated)
        _ = IconCache.shared.icon(for: tile.id)
    }

    /// Supprime un signet Web ou un Raccourci Apple personnalisé.
    func removeCustomTile(_ id: String) {
        CustomTileManager.shared.removeTile(id: id)
        forget([id])
        saveNow()
    }

    // MARK: Réorganisation automatique (« Reorganize Layout » de LaunchOS)

    func reorganize(rule: SortRule, placement: FolderPlacement, sortFolderContents: Bool) {
        let invisible = items.filter { item in
            if let id = item.appID { return !isVisibleApp(id) }
            if let folder = item.folder { return folder.apps.allSatisfy { !isVisibleApp($0) } }
            return false
        }

        let byName: (String, String) -> Bool = { [unowned self] a, b in
            self.displayName(a).localizedStandardCompare(self.displayName(b)) == .orderedAscending
        }
        let appOrder: (String, String) -> Bool = { [unowned self] a, b in
            self.compare(a, b, rule: rule)
        }

        let widgets = visibleItems.filter { $0.isWidget }
        var result: [LayoutItem]
        if rule == .category {
            var groups: [String: [String]] = [:]
            var loose: [String] = []
            for app in allVisibleApps {
                if let key = app.categoryKey { groups[key, default: []].append(app.id) } else { loose.append(app.id) }
            }
            var folders: [FolderData] = []
            for (key, apps) in groups {
                if apps.count >= 2 {
                    folders.append(FolderData(id: FolderData.newID(), name: CategoryNames.title(for: key), apps: apps.sorted(by: byName)))
                } else {
                    loose.append(contentsOf: apps)
                }
            }
            folders.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            loose.sort(by: byName)
            result = widgets + arrange(apps: loose.map { .app($0) }, folders: folders.map { .folder($0) }, placement: placement)
        } else {
            var apps: [String] = []
            var folders: [FolderData] = []
            for item in visibleItems {
                switch item {
                case .app(let id): apps.append(id)
                case .folder(let visible):
                    guard var stored = items.lazy.compactMap(\.folder).first(where: { $0.id == visible.id }) else { continue }
                    if sortFolderContents { stored.apps.sort(by: appOrder) }
                    folders.append(stored)
                case .widget:
                    break
                }
            }
            apps.sort(by: appOrder)
            folders.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            result = widgets + arrange(apps: apps.map { .app($0) }, folders: folders.map { .folder($0) }, placement: placement)
        }
        commit(result + invisible)
    }

    private func arrange(apps: [LayoutItem], folders: [LayoutItem], placement: FolderPlacement) -> [LayoutItem] {
        switch placement {
        case .before: return folders + apps
        case .after: return apps + folders
        case .mixed:
            return (folders + apps).sorted { a, b in
                sortName(a).localizedStandardCompare(sortName(b)) == .orderedAscending
            }
        }
    }

    private func sortName(_ item: LayoutItem) -> String {
        switch item {
        case .app(let id): displayName(id)
        case .folder(let folder): folder.name
        case .widget(let config): config.kind.title
        }
    }

    private func compare(_ a: String, _ b: String, rule: SortRule) -> Bool {
        let left = catalog[a], right = catalog[b]
        func dates(_ l: Date?, _ r: Date?, newestFirst: Bool) -> Bool {
            switch (l, r) {
            case let (l?, r?): return l == r ? displayName(a).localizedStandardCompare(displayName(b)) == .orderedAscending : (newestFirst ? l > r : l < r)
            case (nil, nil): return displayName(a).localizedStandardCompare(displayName(b)) == .orderedAscending
            case (nil, _): return false
            case (_, nil): return true
            }
        }
        switch rule {
        case .nameAscending, .category: return displayName(a).localizedStandardCompare(displayName(b)) == .orderedAscending
        case .nameDescending: return displayName(a).localizedStandardCompare(displayName(b)) == .orderedDescending
        case .dateAddedNewest: return dates(left?.dateAdded, right?.dateAdded, newestFirst: true)
        case .dateAddedOldest: return dates(left?.dateAdded, right?.dateAdded, newestFirst: false)
        case .lastUsedRecent: return dates(left?.lastUsed, right?.lastUsed, newestFirst: true)
        case .lastUsedOldest: return dates(left?.lastUsed, right?.lastUsed, newestFirst: false)
        }
    }

    /// Réinitialise : toutes les apps par ordre alphabétique, sans dossier, en préservant les widgets.
    func resetLayout() {
        let widgets = items.filter { $0.isWidget }
        let apps = catalog.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        commit(widgets + apps.map { .app($0.id) })
    }

    private func suggestedFolderName(for ids: [String]) -> String {
        let keys = Set(ids.compactMap { catalog[$0]?.categoryKey })
        if keys.count == 1, let key = keys.first, ids.allSatisfy({ catalog[$0]?.categoryKey != nil }) {
            return CategoryNames.title(for: key)
        }
        return "Sans titre"
    }

    // MARK: Import / export

    var layoutSnapshot: LayoutFile {
        LayoutFile(items: items, hidden: hidden.sorted(), customNames: customNames)
    }

    /// Remplace la disposition (sauvegarde ou Launchpad système). Les chemins inconnus sont
    /// rapprochés par nom de bundle pour les transferts entre Mac.
    func importLayout(_ file: LayoutFile) {
        var byName: [String: String] = [:]
        for app in catalog.values { byName[app.url.lastPathComponent.lowercased()] = app.id }
        func map(_ id: String) -> String {
            if catalog[id] != nil { return id }
            return byName[(id as NSString).lastPathComponent.lowercased()] ?? id
        }
        var seen = Set<String>()
        let mapped: [LayoutItem] = file.items.compactMap { item in
            switch item {
            case .app(let id):
                let target = map(id)
                return seen.insert(target).inserted ? .app(target) : nil
            case .folder(var folder):
                folder.apps = folder.apps.map(map).filter { seen.insert($0).inserted }
                return folder.apps.isEmpty ? nil : .folder(folder)
            case .widget:
                return item
            }
        }
        hidden = Set(file.hidden.map(map))
        customNames = Dictionary(file.customNames.map { (map($0.key), $0.value) }, uniquingKeysWith: { first, _ in first })
        let placed = Set(allPlacedAppIDs(in: mapped))
        let missing = catalog.values.filter { !placed.contains($0.id) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { LayoutItem.app($0.id) }
        commit(mapped + missing)
    }

    // MARK: - Gestion des Widgets dans la Grille

    /// Insère un élément (widget) de sorte que `GridLayoutEngine` l'affiche sur `targetPage`.
    private func insertItemOnPage(
        _ newItem: LayoutItem,
        into baseItems: [LayoutItem],
        targetPage: Int,
        preferredVisibleIndex: Int? = nil,
        columns: Int,
        rows: Int
    ) -> [LayoutItem] {
        var copy = baseItems
        copy.removeAll { $0.id == newItem.id }
        let visibleBase = computeVisibleItems(from: copy)

        guard !visibleBase.isEmpty else {
            copy.append(newItem)
            return copy
        }

        if targetPage <= 0 && preferredVisibleIndex == nil {
            if let firstVisibleID = visibleBase.first?.id,
               let destIndex = copy.firstIndex(where: { $0.id == firstVisibleID }) {
                copy.insert(newItem, at: destIndex)
            } else {
                copy.insert(newItem, at: 0)
            }
            return copy
        }

        let basePages = GridLayoutEngine.pageAssignments(items: visibleBase, columns: columns, rows: rows)
        let maxBasePage = basePages.max() ?? 0
        let desiredPage = max(0, min(targetPage, maxBasePage))

        // Si un index préféré (ex: redimensionnement sur place) est fourni, on cherche l'emplacement
        // le plus proche sur `desiredPage` en reculant puis en avançant.
        if let preferred = preferredVisibleIndex {
            let clampedPref = max(0, min(preferred, visibleBase.count))
            let firstOnPage = basePages.firstIndex(where: { $0 == desiredPage }) ?? 0
            let lastOnPage = basePages.lastIndex(where: { $0 == desiredPage }).map { $0 + 1 } ?? visibleBase.count

            var candidateIndices: [Int] = []
            // D'abord en reculant depuis la position actuelle jusqu'au début de la page courante
            if clampedPref >= firstOnPage {
                for idx in stride(from: min(clampedPref, lastOnPage), through: firstOnPage, by: -1) {
                    candidateIndices.append(idx)
                }
            }
            // Puis les autres indices de la page courante si nécessaire
            if firstOnPage <= lastOnPage {
                for idx in firstOnPage...min(lastOnPage, visibleBase.count) where !candidateIndices.contains(idx) {
                    candidateIndices.append(idx)
                }
            }

            for vIdx in candidateIndices {
                var trialVisible = visibleBase
                trialVisible.insert(newItem, at: vIdx)
                let assigned = GridLayoutEngine.pageAssignments(items: trialVisible, columns: columns, rows: rows)
                if vIdx < assigned.count && assigned[vIdx] == desiredPage {
                    return insert(newItem, atVisibleIndex: vIdx, in: copy, visibleBase: visibleBase)
                }
            }
        }

        // Recherche du premier emplacement qui positionne effectivement le widget sur `desiredPage`
        let startSearch = basePages.firstIndex(where: { $0 >= desiredPage }) ?? visibleBase.count
        for vIdx in startSearch...visibleBase.count {
            var trialVisible = visibleBase
            trialVisible.insert(newItem, at: vIdx)
            let assigned = GridLayoutEngine.pageAssignments(items: trialVisible, columns: columns, rows: rows)
            if vIdx < assigned.count && assigned[vIdx] == desiredPage {
                return insert(newItem, atVisibleIndex: vIdx, in: copy, visibleBase: visibleBase)
            }
        }

        // Repli si la page cible était la dernière
        copy.append(newItem)
        return copy
    }

    private func insert(
        _ newItem: LayoutItem,
        atVisibleIndex vIdx: Int,
        in copy: [LayoutItem],
        visibleBase: [LayoutItem]
    ) -> [LayoutItem] {
        var result = copy
        if vIdx < visibleBase.count,
           let destIndex = result.firstIndex(where: { $0.id == visibleBase[vIdx].id }) {
            result.insert(newItem, at: destIndex)
        } else if let lastVisible = visibleBase.last,
                  let lastIndex = result.firstIndex(where: { $0.id == lastVisible.id }) {
            result.insert(newItem, at: lastIndex + 1)
        } else {
            result.append(newItem)
        }
        return result
    }

    @discardableResult
    func addWidget(
        _ config: CustomWidgetConfig,
        onPage targetPage: Int? = nil,
        atVisibleIndex targetIndex: Int? = nil,
        columns: Int = 7,
        rows: Int = 5
    ) -> Bool {
        let span = config.size.span(maxColumns: columns, maxRows: rows)
        guard span.cols <= columns && span.rows <= rows else { return false }

        var enabledConfig = config
        enabledConfig.isEnabled = true
        let newItem = LayoutItem.widget(enabledConfig)

        let copy: [LayoutItem]
        if let targetPage {
            copy = insertItemOnPage(
                newItem,
                into: items,
                targetPage: targetPage,
                columns: columns,
                rows: rows
            )
        } else if let target = targetIndex {
            var temp = items
            temp.removeAll { $0.id == enabledConfig.id }
            let visibleBase = computeVisibleItems(from: temp)
            copy = insert(newItem, atVisibleIndex: min(max(0, target), visibleBase.count), in: temp, visibleBase: visibleBase)
        } else {
            copy = insertItemOnPage(
                newItem,
                into: items,
                targetPage: 0,
                columns: columns,
                rows: rows
            )
        }

        if GridLayoutEngine.canLayout(items: computeVisibleItems(from: copy), columns: columns, rows: rows) {
            WidgetManager.shared.updateSize(for: enabledConfig.kind, size: enabledConfig.size)
            if !WidgetManager.shared.isEnabled(enabledConfig.kind) {
                WidgetManager.shared.toggleWidget(enabledConfig.kind)
            }
            commit(copy)
            return true
        } else {
            return false
        }
    }

    @discardableResult
    func updateWidgetSize(_ widgetID: String, to newSize: WidgetSize, columns: Int, rows: Int) -> Bool {
        guard let idx = items.firstIndex(where: { $0.id == widgetID }),
              case .widget(var config) = items[idx] else { return false }

        let previousSize = config.size
        guard previousSize != newSize else { return true }

        let span = newSize.span(maxColumns: columns, maxRows: rows)
        guard span.cols <= columns && span.rows <= rows else {
            return false
        }

        // Page actuelle du widget avant son redimensionnement
        let currentVisible = computeVisibleItems(from: items)
        let currentPages = GridLayoutEngine.pageAssignments(items: currentVisible, columns: columns, rows: rows)
        let currentVisibleIdx = currentVisible.firstIndex(where: { $0.id == widgetID })
        let originalPage: Int = {
            if let vIdx = currentVisibleIdx, vIdx < currentPages.count {
                return currentPages[vIdx]
            }
            return 0
        }()

        config.size = newSize
        let updatedItem = LayoutItem.widget(config)

        var trial = items
        trial[idx] = updatedItem

        // Vérifie si le widget reste bien sur sa page d'origine après redimensionnement
        let trialVisible = computeVisibleItems(from: trial)
        let trialPages = GridLayoutEngine.pageAssignments(items: trialVisible, columns: columns, rows: rows)
        let staysOnSamePage: Bool = {
            if let vIdx = trialVisible.firstIndex(where: { $0.id == widgetID }), vIdx < trialPages.count {
                return trialPages[vIdx] == originalPage
            }
            return false
        }()

        if !staysOnSamePage {
            // Si la nouvelle taille (ex: Moyen 2x1 ou Vertical 2x4) débordait en fin de page,
            // on repositionne le widget sur la même page (`originalPage`) au plus près de sa position.
            trial = insertItemOnPage(
                updatedItem,
                into: items,
                targetPage: originalPage,
                preferredVisibleIndex: currentVisibleIdx,
                columns: columns,
                rows: rows
            )
        }

        if GridLayoutEngine.canLayout(items: computeVisibleItems(from: trial), columns: columns, rows: rows) {
            WidgetManager.shared.updateSize(for: config.kind, size: newSize)
            commit(trial)
            return true
        } else {
            return false
        }
    }

    func removeWidget(_ id: String) {
        var copy = items
        copy.removeAll { $0.id == id }
        commit(copy)
    }

    func removeWidget(_ kind: WidgetKind) {
        removeWidget(kind.rawValue)
    }

    func updateWidgetConfig(_ config: CustomWidgetConfig) {
        var copy = items
        if let idx = copy.firstIndex(where: { $0.id == config.id }) {
            copy[idx] = .widget(config)
            commit(copy)
        }
    }

    // MARK: Persistance (JSON dans Application Support)

    private var layoutURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "LaucnhPad", isDirectory: true)
            .appendingPathComponent("layout.json")
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: layoutURL) else { return }
        do {
            let file = try JSONDecoder().decode(LayoutFile.self, from: data)
            items = file.items
            hidden = Set(file.hidden)
            customNames = file.customNames
            hasLayoutFile = true

            // Si des widgets étaient activés dans WidgetManager mais ne sont pas encore dans la grille,
            // on les insère au début pour un accueil fluide sans bug de superposition.
            if LicenseManager.shared.isPro && !items.contains(where: { $0.isWidget }) {
                let enabledConfigs = WidgetManager.shared.widgets.filter { $0.isEnabled }.sorted { $0.order < $1.order }
                if !enabledConfigs.isEmpty {
                    items.insert(contentsOf: enabledConfigs.map { LayoutItem.widget($0) }, at: 0)
                }
            }
        } catch {
            // Fichier corrompu : on le met de côté au lieu de l'écraser silencieusement.
            let backup = layoutURL.deletingLastPathComponent().appendingPathComponent("layout-corrompu-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: layoutURL, to: backup)
        }
    }

    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        saveTask?.cancel()
        guard hasLayoutFile || !items.isEmpty else { return }
        let snapshot = layoutSnapshot
        let url = layoutURL
        hasLayoutFile = true
        Task.detached(priority: .utility) {
            do {
                let directory = url.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(snapshot)
                try data.write(to: url, options: .atomic)
            } catch {
                NSLog("LaucnhPad: échec d'enregistrement de la disposition: \(error.localizedDescription)")
            }
        }
    }
}
