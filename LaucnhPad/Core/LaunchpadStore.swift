import AppKit
import Combine

// MARK: - Modèle de disposition

nonisolated struct FolderData: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var apps: [String]
    var isLocked: Bool
    var style: FolderVisualStyle
    var colorHex: String?
    var iconSymbol: String?
    var keepWhenEmpty: Bool
    var pinToLastPage: Bool

    init(
        id: String,
        name: String,
        apps: [String],
        isLocked: Bool = false,
        style: FolderVisualStyle = .frostedGlass,
        colorHex: String? = nil,
        iconSymbol: String? = nil,
        keepWhenEmpty: Bool = false,
        pinToLastPage: Bool = false
    ) {
        self.id = id
        self.name = name
        self.apps = apps
        self.isLocked = isLocked
        self.style = style
        self.colorHex = colorHex
        self.iconSymbol = iconSymbol
        self.keepWhenEmpty = keepWhenEmpty
        self.pinToLastPage = pinToLastPage
    }

    enum CodingKeys: String, CodingKey {
        case id, name, apps, isLocked, style, colorHex, iconSymbol, keepWhenEmpty, pinToLastPage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        apps = try container.decode([String].self, forKey: .apps)
        isLocked = try container.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        style = try container.decodeIfPresent(FolderVisualStyle.self, forKey: .style) ?? .frostedGlass
        colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex)
        iconSymbol = try container.decodeIfPresent(String.self, forKey: .iconSymbol)
        keepWhenEmpty = try container.decodeIfPresent(Bool.self, forKey: .keepWhenEmpty) ?? false
        pinToLastPage = try container.decodeIfPresent(Bool.self, forKey: .pinToLastPage) ?? false
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
    private(set) var runningRevision = 0
    @Published private(set) var isLoading = true
    @Published private(set) var iconsVersion = 0
    /// Incrémenté à chaque modification du catalogue ou de la visibilité (cache de recherche).
    private(set) var revision = 0

    private var hasLayoutFile = false
    private var started = false
    private var isLaunchpadVisible = false
    private var needsRunningAppsRefresh = false
    private var needsScanRefresh = false
    private var lastAppliedIconSignature = ""
    private var scanTask: Task<Void, Never>?
    private var iconPreloadTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var missingSince: [String: Date] = [:]
    private(set) var lastScan = Date.distantPast
    private let watcher = FolderWatcher()
    private let saveWriteQueue = DispatchQueue(label: "launchpad.layout.save", qos: .utility)

    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: Démarrage

    func start() {
        guard !started else { return }
        started = true
        loadFromDisk()
        lastAppliedIconSignature = currentIconSignature()
        IconCache.shared.onAsyncBatchReady = { [weak self] in
            self?.iconsVersion &+= 1
        }
        updateRunningApps()
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(runningAppsChanged), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(runningAppsChanged), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(volumesChanged), name: NSWorkspace.didMountNotification, object: nil)
        center.addObserver(self, selector: #selector(volumesChanged), name: NSWorkspace.didUnmountNotification, object: nil)
        center.addObserver(self, selector: #selector(volumesChanged), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(iconStyleNotificationReceived(_:)), name: .launchpadIconStyleDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(customIconDidChangeNotification(_:)), name: .launchpadCustomIconDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(weatherDataUpdatedNotification(_:)), name: .weatherDataDidUpdate, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(launchpadVisibilityNotification(_:)), name: .launchpadVisibilityDidChange, object: nil)
        watcher.onChange = { [weak self] in
            guard let self else { return }
            if !self.isLaunchpadVisible {
                self.needsScanRefresh = true
                return
            }
            self.scheduleRefresh()
        }
        refresh()
    }

    private func currentIconSignature() -> String {
        let style = IconCache.shared.currentAppearanceStyle
        let isPro = Prefs.defaults.bool(forKey: PrefKey.isProUnlocked)
        let tintKey = IconCache.shared.activeTintKey
        return "\(style.rawValue)|\(isPro)|\(tintKey)"
    }

    @objc private func launchpadVisibilityNotification(_ note: Notification) {
        let visible = (note.object as? Bool) ?? false
        isLaunchpadVisible = visible
        guard visible else { return }
        if needsRunningAppsRefresh {
            needsRunningAppsRefresh = false
            updateRunningApps()
        }
        if needsScanRefresh {
            needsScanRefresh = false
            refresh()
        }
        if items.contains(where: { $0.widget?.kind == .weather && $0.widget?.isEnabled == true }) {
            WeatherService.shared.refreshIfNeeded(force: false, requestLocationPermission: false)
        }
    }

    @objc private func customIconDidChangeNotification(_ note: Notification) {
        if let appID = note.object as? String {
            IconCache.shared.invalidate([appID])
        } else if let appIDs = note.object as? [String] {
            IconCache.shared.invalidate(appIDs)
        } else {
            IconCache.shared.invalidate(Array(catalog.keys))
        }
        iconsVersion &+= 1
    }

    @objc private func iconStyleNotificationReceived(_ note: Notification) {
        IconCache.shared.invalidateStyleCache()
        let force = (note.object as? String) == "force"
        let signature = currentIconSignature()
        guard force || signature != lastAppliedIconSignature else { return }
        lastAppliedIconSignature = signature
        IconCache.shared.removeStyleImages()
        iconsVersion &+= 1
        prewarmIcons(Array(catalog.keys))
    }

    @objc private func weatherDataUpdatedNotification(_ note: Notification) {
        guard let snap = note.object as? LiveWeatherSnapshot else { return }
        var copy = items
        var changed = false
        for idx in copy.indices {
            guard var w = copy[idx].widget, w.kind == .weather else { continue }
            if w.weatherCity != snap.city || w.weatherUnit != snap.unit || w.weatherTemp != snap.temp || w.weatherCondition != snap.condition || w.weatherFeelsLike != snap.feelsLike {
                w.weatherCity = snap.city
                w.weatherUnit = snap.unit
                w.weatherTemp = snap.temp
                w.weatherCondition = snap.condition
                w.weatherFeelsLike = snap.feelsLike
                copy[idx] = .widget(w)
                changed = true
            }
        }
        if changed {
            commit(copy)
        }
    }

    @objc private func runningAppsChanged() {
        guard isLaunchpadVisible else {
            needsRunningAppsRefresh = true
            return
        }
        updateRunningApps()
    }

    @objc private func volumesChanged() {
        guard isLaunchpadVisible else {
            needsScanRefresh = true
            return
        }
        scheduleRefresh(delay: 1.0)
    }

    private func updateRunningApps() {
        let ids = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        if ids != runningBundleIDs {
            runningRevision &+= 1
            runningBundleIDs = ids
        }
    }

    func isRunning(_ app: AppInfo) -> Bool {
        guard let bundleID = app.bundleID else { return false }
        return runningBundleIDs.contains(bundleID)
    }

    // MARK: Analyse

    func refreshIfStale() {
        if needsRunningAppsRefresh {
            needsRunningAppsRefresh = false
            updateRunningApps()
        }
        if needsScanRefresh || Date().timeIntervalSince(lastScan) > 30 {
            needsScanRefresh = false
            refresh()
        }
    }

    func scheduleRefresh(delay: Double = 1.5) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    /// Vide le cache de style d'icônes (en préservant les icônes personnalisées) et les régénère en arrière-plan.
    func reloadIcons() {
        IconCache.shared.invalidateStyleCache()
        lastAppliedIconSignature = currentIconSignature()
        IconCache.shared.removeStyleImages()
        iconsVersion &+= 1
        prewarmIcons(Array(catalog.keys))
    }

    /// Pré-rend en parallèle et hors thread principal toutes les icônes manquantes dans le style actif.
    private func prewarmIcons(_ candidateIDs: [String]) {
        let missingIcons = candidateIDs.filter { !IconCache.shared.contains($0) && !CustomIconManager.shared.hasOverride(for: $0) }
        guard !missingIcons.isEmpty else { return }

        // Prioriser les éléments visibles en tête de grille pour un affichage instantané
        var orderedSet = Set<String>()
        var prioritized: [String] = []
        prioritized.reserveCapacity(missingIcons.count)
        let missingLookup = Set(missingIcons)
        for item in visibleItems {
            switch item {
            case .app(let id) where missingLookup.contains(id):
                if orderedSet.insert(id).inserted { prioritized.append(id) }
            case .folder(let folder):
                for id in folder.apps.prefix(9) where missingLookup.contains(id) {
                    if orderedSet.insert(id).inserted { prioritized.append(id) }
                }
            default: break
            }
        }
        for id in missingIcons where orderedSet.insert(id).inserted {
            prioritized.append(id)
        }

        let style = IconCache.shared.currentAppearanceStyle
        let tintRGB = IconCache.shared.activeTintRGB
        let tintKey = IconCache.shared.activeTintKey
        let isPro = Prefs.defaults.bool(forKey: PrefKey.isProUnlocked)

        iconPreloadTask?.cancel()
        iconPreloadTask = Task { [weak self] in
            // Vague 1 : icônes immédiatement visibles en page 1 / premiers dossiers
            let wave1Count = min(56, prioritized.count)
            let wave1 = Array(prioritized.prefix(wave1Count))
            if !wave1.isEmpty {
                let rendered1 = await IconRenderer.renderAsync(wave1, style: style, tintRGB: tintRGB, isPro: isPro)
                guard let self, !Task.isCancelled else { return }
                IconCache.shared.store(rendered1, forStyle: style, tintKey: tintKey, isPro: isPro)
                self.iconsVersion &+= 1
            }

            // Vague 2 : icônes des pages suivantes par paquets bornés
            if prioritized.count > wave1Count {
                let chunkSize = 64
                var idx = wave1Count
                var storedAny = false
                while idx < prioritized.count {
                    guard !Task.isCancelled else { return }
                    let end = min(prioritized.count, idx + chunkSize)
                    let chunk = Array(prioritized[idx..<end])
                    let rendered = await IconRenderer.renderAsync(chunk, style: style, tintRGB: tintRGB, isPro: isPro)
                    guard !Task.isCancelled else { return }
                    if !rendered.isEmpty {
                        IconCache.shared.store(rendered, forStyle: style, tintKey: tintKey, isPro: isPro)
                        storedAny = true
                    }
                    idx = end
                }
                if let self, !Task.isCancelled, storedAny {
                    self.iconsVersion &+= 1
                }
            }
        }
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
            self.prewarmIcons(scanned.map(\.id))
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
        newCatalog.reserveCapacity(allScanned.count)
        for app in allScanned { newCatalog[app.id] = app }

        // Les icônes des apps mises à jour sont régénérées.
        let changed = allScanned.filter { prev in
            guard let old = previous[prev.id] else { return false }
            return old.bundleID != prev.bundleID || (prev.bundleModTime > 0 && old.bundleModTime != prev.bundleModTime)
        }.map(\.id)
        if !changed.isEmpty { IconCache.shared.invalidate(changed) }

        let catalogChanged = previous != newCatalog
        if catalogChanged { catalog = newCatalog }
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
            if !legacy.isEmpty {
                let rank = Dictionary(legacy.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
                let namesByID = Dictionary(uniqueKeysWithValues: fresh.map { ($0.id, displayName($0.id)) })
                fresh.sort {
                    let left = rank[$0.id] ?? Int.max, right = rank[$1.id] ?? Int.max
                    if left != right { return left < right }
                    return (namesByID[$0.id] ?? $0.name).localizedStandardCompare(namesByID[$1.id] ?? $1.name) == .orderedAscending
                }
                updated.append(contentsOf: fresh.map { LayoutItem.app($0.id) })
            } else {
                // Première initialisation : range d'abord les apps tierces, puis les dossiers Apple sur la dernière page.
                let categorized = buildDefaultCategorizedItems(from: fresh)
                updated.append(contentsOf: categorized)
            }
            hasLayoutFile = true
        } else if !fresh.isEmpty {
            let namesByID = Dictionary(uniqueKeysWithValues: fresh.map { ($0.id, displayName($0.id)) })
            fresh.sort { (namesByID[$0.id] ?? $0.name).localizedStandardCompare(namesByID[$1.id] ?? $1.name) == .orderedAscending }
            let freshItems = fresh.map { LayoutItem.app($0.id) }
            // Insérer les nouvelles applications avant les éventuels dossiers Apple épinglés en dernière page.
            if let firstPinnedIdx = updated.firstIndex(where: { $0.folder?.pinToLastPage == true }) {
                updated.insert(contentsOf: freshItems, at: firstPinnedIdx)
            } else {
                updated.append(contentsOf: freshItems)
            }
        }

        if isSubsequentScan && !fresh.isEmpty {
            AppNotificationManager.shared.sendNewAppsDiscoveredNotification(count: fresh.count)
        }

        // Migration unique : extrait toute app externe des dossiers Apple hérités et place tous les dossiers Apple en dernière page.
        let appleMigrationKey = "LaunchpadAppleFoldersLastPageMigrated_v119"
        if !newCatalog.isEmpty && !UserDefaults.standard.bool(forKey: appleMigrationKey) {
            UserDefaults.standard.set(true, forKey: appleMigrationKey)
            updated = migrateAppleFoldersToLastPage(in: updated, catalog: newCatalog)
        }

        if updated != items {
            commit(updated, save: true)
        } else if catalogChanged {
            recomputeVisible()
        }
    }

    // MARK: Accès

    func displayName(_ id: String) -> String {
        if let custom = customNames[id], !custom.isEmpty { return custom }
        if let app = catalog[id] {
            return AppleAppLocalizer.localizedName(for: app, languageCode: LocalizationManager.activeLanguageCode)
        }
        return (id as NSString).lastPathComponent
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
                return (folder.apps.isEmpty && !folder.keepWhenEmpty) ? nil : .folder(folder)
            case .widget:
                return item
            }
        }
    }

    private func computeVisibleItems(from list: [LayoutItem]) -> [LayoutItem] {
        var seenWidgetCategories = Set<WidgetCategoryGroup>()
        return list.compactMap { item in
            switch item {
            case .app(let id):
                return isVisibleApp(id) ? item : nil
            case .folder(var folder):
                let apps = folder.apps.filter(isVisibleApp)
                guard !apps.isEmpty || folder.keepWhenEmpty else { return nil }
                folder.apps = apps
                return .folder(folder)
            case .widget(let config):
                guard config.isEnabled else { return nil }
                return seenWidgetCategories.insert(config.kind.categoryGroup).inserted ? item : nil
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
        if items != newItems {
            items = newItems
        }
        recomputeVisible()
        if save { scheduleSave() }
    }

    // MARK: Réorganisation manuelle

    /// Déplace un élément de premier niveau à un index de la liste affichée.
    func moveItem(_ id: String, toVisibleIndex target: Int, afterTarget: Bool = false, unpinFromLastPage: Bool = false) {
        guard let from = items.firstIndex(where: { $0.id == id }) else { return }
        let others = visibleItems.filter { $0.id != id }
        let rawDestination: Int
        if afterTarget {
            let targetID = visibleItems.indices.contains(target) ? visibleItems[target].id : nil
            if let targetID, let anchorIdx = others.firstIndex(where: { $0.id == targetID }) {
                rawDestination = anchorIdx + 1
            } else {
                rawDestination = others.count
            }
        } else {
            rawDestination = target
        }
        let destination = max(0, min(rawDestination, others.count))
        var copy = items
        var moving = copy.remove(at: from)
        let insertionIndex: Int
        if destination == others.count {
            if let last = others.last, let index = copy.firstIndex(where: { $0.id == last.id }) {
                insertionIndex = index + 1
            } else {
                insertionIndex = copy.count
            }
        } else if let index = copy.firstIndex(where: { $0.id == others[destination].id }) {
            insertionIndex = index
        } else {
            insertionIndex = copy.count
        }
        if case .folder(var movingFolder) = moving, movingFolder.pinToLastPage {
            // Retire l'épinglage automatique si le dossier est déplacé vers une page normale ou s'il était le seul dossier épinglé déplacé avant la fin.
            let firstPinned = copy.firstIndex(where: { $0.folder?.pinToLastPage == true })
            let movedBeforePinnedGroup = firstPinned.map { insertionIndex < $0 } ?? (insertionIndex < copy.count)
            if unpinFromLastPage || movedBeforePinnedGroup {
                movingFolder.pinToLastPage = false
                moving = .folder(movingFolder)
            }
        }
        copy.insert(moving, at: insertionIndex)
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
            if !folder.apps.contains(appID) {
                folder.apps.append(appID)
            }
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
        folder.name = trimmed.isEmpty ? loc("folder.untitled") : trimmed
        var copy = items
        copy[index] = .folder(folder)
        commit(copy)
    }

    func updateFolderCustomization(
        _ folderID: String,
        style: FolderVisualStyle,
        colorHex: String?,
        iconSymbol: String?
    ) {
        guard let index = items.firstIndex(where: { $0.id == folderID }),
              case .folder(var folder) = items[index] else { return }
        folder.style = style
        folder.colorHex = colorHex
        folder.iconSymbol = iconSymbol
        var copy = items
        copy[index] = .folder(folder)
        commit(copy)
    }

    func toggleAppInFolder(_ appID: String, folderID: String) {
        guard let folderIndex = items.firstIndex(where: { $0.id == folderID }),
              case .folder(var folder) = items[folderIndex] else { return }
        var copy = items

        if folder.apps.contains(appID) {
            folder.apps.removeAll { $0 == appID }
            folder.keepWhenEmpty = true
            copy[folderIndex] = .folder(folder)
            copy.insert(.app(appID), at: min(folderIndex + 1, copy.count))
        } else {
            // Retire l'app de son emplacement actuel (grille ou autre dossier)
            for idx in copy.indices.reversed() where idx != folderIndex {
                switch copy[idx] {
                case .app(let id) where id == appID:
                    copy.remove(at: idx)
                case .folder(var otherFolder) where otherFolder.apps.contains(appID):
                    otherFolder.apps.removeAll { $0 == appID }
                    if otherFolder.apps.isEmpty && !otherFolder.keepWhenEmpty {
                        copy.remove(at: idx)
                    } else {
                        copy[idx] = .folder(otherFolder)
                    }
                default:
                    break
                }
            }
            if let newFolderIdx = copy.firstIndex(where: { $0.id == folderID }),
               case .folder(var updatedFolder) = copy[newFolderIdx] {
                if !updatedFolder.apps.contains(appID) {
                    updatedFolder.apps.append(appID)
                }
                copy[newFolderIdx] = .folder(updatedFolder)
            }
        }
        commit(copy)
    }

    @discardableResult
    func createCustomFolder(
        name: String? = nil,
        style: FolderVisualStyle = .frostedGlass,
        colorHex: String? = nil,
        iconSymbol: String? = nil,
        apps: [String] = []
    ) -> String {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let folder = FolderData(
            id: FolderData.newID(),
            name: trimmed.isEmpty ? loc("folder.default_name") : trimmed,
            apps: apps,
            isLocked: false,
            style: style,
            colorHex: colorHex,
            iconSymbol: iconSymbol,
            keepWhenEmpty: true
        )
        var copy = items
        if !apps.isEmpty {
            let set = Set(apps)
            copy.removeAll { item in
                if let id = item.appID { return set.contains(id) }
                return false
            }
        }
        copy.insert(.folder(folder), at: 0)
        commit(copy)
        return folder.id
    }

    func syncWidgetConfig(_ updatedConfig: CustomWidgetConfig) {
        var copy = items
        var changed = false
        for idx in copy.indices {
            if case .widget(let current) = copy[idx], current.kind == updatedConfig.kind {
                var merged = updatedConfig
                merged.id = current.id
                merged.size = current.size
                merged.isEnabled = true
                if merged != current {
                    copy[idx] = .widget(merged)
                    changed = true
                }
            }
        }
        if changed {
            commit(copy)
        }
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
        var copy = items
        copy[index] = .folder(folder)
        commit(copy)
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

        // Pré-calcul des noms affichés (évite N log N appels localisés durant le tri)
        var namesByID: [String: String] = [:]
        namesByID.reserveCapacity(catalog.count)
        for id in catalog.keys {
            namesByID[id] = displayName(id)
        }

        let needsDates = (rule == .dateAddedNewest || rule == .dateAddedOldest || rule == .lastUsedRecent || rule == .lastUsedOldest)
        let metadataDates = needsDates ? AppScanner.metadataDates(for: Array(catalog.keys)) : [:]

        let byName: (String, String) -> Bool = { a, b in
            (namesByID[a] ?? a).localizedStandardCompare(namesByID[b] ?? b) == .orderedAscending
        }
        let appOrder: (String, String) -> Bool = { [unowned self] a, b in
            self.compare(a, b, rule: rule, namesByID: namesByID, metadataDates: metadataDates)
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
            result = widgets + arrange(apps: loose.map { .app($0) }, folders: folders.map { .folder($0) }, placement: placement, namesByID: namesByID)
        } else {
            var storedFoldersByID: [String: FolderData] = [:]
            for case .folder(let folder) in items {
                storedFoldersByID[folder.id] = folder
            }
            var apps: [String] = []
            var folders: [FolderData] = []
            for item in visibleItems {
                switch item {
                case .app(let id): apps.append(id)
                case .folder(let visible):
                    guard var stored = storedFoldersByID[visible.id] else { continue }
                    if sortFolderContents { stored.apps.sort(by: appOrder) }
                    folders.append(stored)
                case .widget:
                    break
                }
            }
            apps.sort(by: appOrder)
            folders.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            result = widgets + arrange(apps: apps.map { .app($0) }, folders: folders.map { .folder($0) }, placement: placement, namesByID: namesByID)
        }
        commit(result + invisible)
    }

    private func arrange(apps: [LayoutItem], folders: [LayoutItem], placement: FolderPlacement, namesByID: [String: String]) -> [LayoutItem] {
        switch placement {
        case .before: return folders + apps
        case .after: return apps + folders
        case .mixed:
            return (folders + apps).sorted { a, b in
                let na: String = {
                    switch a {
                    case .app(let id): return namesByID[id] ?? displayName(id)
                    case .folder(let folder): return folder.name
                    case .widget(let config): return config.kind.title
                    }
                }()
                let nb: String = {
                    switch b {
                    case .app(let id): return namesByID[id] ?? displayName(id)
                    case .folder(let folder): return folder.name
                    case .widget(let config): return config.kind.title
                    }
                }()
                return na.localizedStandardCompare(nb) == .orderedAscending
            }
        }
    }

    private func compare(
        _ a: String,
        _ b: String,
        rule: SortRule,
        namesByID: [String: String],
        metadataDates: [String: (added: Date?, lastUsed: Date?)]
    ) -> Bool {
        let nameA = namesByID[a] ?? a
        let nameB = namesByID[b] ?? b
        func dates(_ l: Date?, _ r: Date?, newestFirst: Bool) -> Bool {
            switch (l, r) {
            case let (l?, r?): return l == r ? nameA.localizedStandardCompare(nameB) == .orderedAscending : (newestFirst ? l > r : l < r)
            case (nil, nil): return nameA.localizedStandardCompare(nameB) == .orderedAscending
            case (nil, _): return false
            case (_, nil): return true
            }
        }
        switch rule {
        case .nameAscending, .category: return nameA.localizedStandardCompare(nameB) == .orderedAscending
        case .nameDescending: return nameA.localizedStandardCompare(nameB) == .orderedDescending
        case .dateAddedNewest: return dates(metadataDates[a]?.added ?? catalog[a]?.dateAdded, metadataDates[b]?.added ?? catalog[b]?.dateAdded, newestFirst: true)
        case .dateAddedOldest: return dates(metadataDates[a]?.added ?? catalog[a]?.dateAdded, metadataDates[b]?.added ?? catalog[b]?.dateAdded, newestFirst: false)
        case .lastUsedRecent: return dates(metadataDates[a]?.lastUsed ?? catalog[a]?.lastUsed, metadataDates[b]?.lastUsed ?? catalog[b]?.lastUsed, newestFirst: true)
        case .lastUsedOldest: return dates(metadataDates[a]?.lastUsed ?? catalog[a]?.lastUsed, metadataDates[b]?.lastUsed ?? catalog[b]?.lastUsed, newestFirst: false)
        }
    }

    /// Réinitialise : classe les applications Apple dans des dossiers par utilisation et affiche les autres par ordre alphabétique.
    func resetLayout() {
        let widgets = items.filter { $0.isWidget }
        let categorized = buildDefaultCategorizedItems(from: Array(catalog.values))
        commit(widgets + categorized)
    }

    /// Regroupe toutes les applications Apple dans des dossiers thématiques (Utilitaires, Productivité, Multimédia, Internet, Jeux).
    func organizeAppleAppsIntoFolders() {
        let widgets = items.filter { $0.isWidget }
        let categorized = buildDefaultCategorizedItems(from: Array(catalog.values))
        commit(widgets + categorized)
    }

    private static let appleUtilityIDs: Set<String> = [
        "com.apple.terminal", "com.apple.activitymonitor", "com.apple.diskutility",
        "com.apple.console", "com.apple.keychainaccess", "com.apple.systemprofiler",
        "com.apple.systempreferences", "com.apple.preferences.softwareupdate",
        "com.apple.screenshot.launcher", "com.apple.screencapture",
        "com.apple.audio.audiomidisetup", "com.apple.bluetoothfileexchange",
        "com.apple.colorsyncutility", "com.apple.digitalcolormeter", "com.apple.grapher",
        "com.apple.migrationassistant", "com.apple.scripteditor2",
        "com.apple.voiceoverutility", "com.apple.airport.airportutility",
        "com.apple.print.printerproxy", "com.apple.printcenter", "com.apple.automator",
        "com.apple.shortcuts", "com.apple.backup.launcher", "com.apple.bootcampassistant"
    ]
    private static let appleProductivityIDs: Set<String> = [
        "com.apple.notes", "com.apple.reminders", "com.apple.ical", "com.apple.addressbook",
        "com.apple.textedit", "com.apple.preview", "com.apple.calculator", "com.apple.clock",
        "com.apple.dictionary", "com.apple.stickies", "com.apple.fontbook", "com.apple.freeform",
        "com.apple.iwork.pages", "com.apple.iwork.numbers", "com.apple.iwork.keynote",
        "com.apple.passwords"
    ]
    private static let appleMediaIDs: Set<String> = [
        "com.apple.music", "com.apple.tv", "com.apple.podcasts", "com.apple.ibooksx",
        "com.apple.photos", "com.apple.quicktimeplayerx", "com.apple.photobooth",
        "com.apple.image_capture", "com.apple.voicememos", "com.apple.imovieapp",
        "com.apple.garageband10"
    ]
    private static let appleInternetIDs: Set<String> = [
        "com.apple.safari", "com.apple.mail", "com.apple.mobilesms", "com.apple.facetime",
        "com.apple.maps", "com.apple.weather", "com.apple.stocks", "com.apple.news",
        "com.apple.home", "com.apple.findmy", "com.apple.appstore"
    ]
    private static let appleGameIDs: Set<String> = [
        "com.apple.chess", "com.apple.games"
    ]

    private func buildDefaultCategorizedItems(from apps: [AppInfo]) -> [LayoutItem] {
        let utilitiesName = loc("category.utilities")
        let productivityName = loc("category.productivity")
        let mediaName = loc("category.media")
        let internetName = loc("category.internet_home")
        let gamesName = loc("category.games")

        var utilitiesApps: [AppInfo] = []
        var productivityApps: [AppInfo] = []
        var mediaApps: [AppInfo] = []
        var internetApps: [AppInfo] = []
        var gamesApps: [AppInfo] = []
        var otherApps: [AppInfo] = []

        for app in apps {
            let bid = app.normalizedBundleID ?? ""
            let isUtilitiesPath = app.id.contains("/Utilities/")
            // Seules les véritables applications Apple (com.apple.*, hors web apps Safari) entrent dans les dossiers Apple.
            let isSystemApple = bid.hasPrefix("com.apple.")
                && !bid.hasPrefix("com.apple.Safari.WebApp")
                && !bid.hasPrefix("com.apple.WebApp")

            guard isSystemApple else {
                otherApps.append(app)
                continue
            }

            if Self.appleUtilityIDs.contains(bid) || isUtilitiesPath {
                utilitiesApps.append(app)
            } else if Self.appleProductivityIDs.contains(bid) {
                productivityApps.append(app)
            } else if Self.appleMediaIDs.contains(bid) {
                mediaApps.append(app)
            } else if Self.appleInternetIDs.contains(bid) {
                internetApps.append(app)
            } else if Self.appleGameIDs.contains(bid) {
                gamesApps.append(app)
            } else {
                utilitiesApps.append(app)
            }
        }

        let namesByID = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, displayName($0.id)) })
        func sortedIDs(_ list: [AppInfo]) -> [String] {
            list.sorted {
                (namesByID[$0.id] ?? $0.name).localizedStandardCompare(namesByID[$1.id] ?? $1.name) == .orderedAscending
            }.map(\.id)
        }

        var result: [LayoutItem] = []

        // 1. Toutes les applications externes d'abord (remplissent les premières pages).
        result.append(contentsOf: sortedIDs(otherApps).map { .app($0) })

        // 2. Tous les dossiers Apple regroupés ensuite sur la dernière page (verre translucide cohérent avec le thème).
        let folderSpecs: [(String, FolderVisualStyle, [AppInfo])] = [
            (internetName, .frostedGlass, internetApps),
            (productivityName, .frostedGlass, productivityApps),
            (mediaName, .frostedGlass, mediaApps),
            (utilitiesName, .frostedGlass, utilitiesApps),
            (gamesName, .frostedGlass, gamesApps)
        ]

        for (name, style, groupApps) in folderSpecs where !groupApps.isEmpty {
            let folder = FolderData(
                id: UUID().uuidString,
                name: name,
                apps: sortedIDs(groupApps),
                style: style,
                iconSymbol: nil,
                pinToLastPage: true
            )
            result.append(.folder(folder))
        }

        return result
    }

    /// Migre les anciens dossiers système (souvent remplis d'apps tierces ou placés en page 1)
    /// en préservant les widgets et les dossiers personnalisés de l'utilisateur.
    private func migrateAppleFoldersToLastPage(in currentItems: [LayoutItem], catalog: [String: AppInfo]) -> [LayoutItem] {
        let appleSystemFolderKeys: Set<String> = [
            "utilitaires", "utilities", "utilidades", "dienstprogramme", "utility", "utilitarios",
            "productivite", "productivity", "productividad", "produktivitat", "produttivita", "produtividade",
            "multimedia", "media", "medien",
            "internet & maison", "internet & home", "internet y hogar", "internet e casa",
            "jeux", "games", "juegos", "spiele", "giochi", "jogos"
        ]

        func normalizedFolderKey(_ name: String) -> String {
            name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var widgets: [LayoutItem] = []
        var customFolders: [LayoutItem] = []
        var claimedByCustomFolder = Set<String>()

        for item in currentItems {
            switch item {
            case .widget:
                widgets.append(item)
            case .folder(let folder):
                if !appleSystemFolderKeys.contains(normalizedFolderKey(folder.name)) {
                    customFolders.append(item)
                    claimedByCustomFolder.formUnion(folder.apps)
                }
            case .app:
                break
            }
        }

        let remainingApps = catalog.values.filter { !claimedByCustomFolder.contains($0.id) }
        let categorized = buildDefaultCategorizedItems(from: remainingApps)
        return widgets + customFolders + categorized
    }

    private func suggestedFolderName(for ids: [String]) -> String {
        let keys = Set(ids.compactMap { catalog[$0]?.categoryKey })
        if keys.count == 1, let key = keys.first, ids.allSatisfy({ catalog[$0]?.categoryKey != nil }) {
            return CategoryNames.title(for: key)
        }
        return loc("folder.untitled")
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
            if vIdx < assigned.count {
                if assigned[vIdx] == desiredPage {
                    return insert(newItem, atVisibleIndex: vIdx, in: copy, visibleBase: visibleBase)
                }
                if assigned[vIdx] > desiredPage {
                    break
                }
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

    func widget(in category: WidgetCategoryGroup) -> CustomWidgetConfig? {
        items.compactMap(\.widget).first { $0.kind.categoryGroup == category }
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
        let targetCategory = enabledConfig.kind.categoryGroup

        // Un seul widget maximum par catégorie (Musique, Météo, Calendrier, Horloge, etc.)
        let replacedKinds = items.compactMap(\.widget)
            .filter { $0.kind.categoryGroup == targetCategory && $0.id != enabledConfig.id }
            .map(\.kind)
        let baseWithoutSameCategory = items.filter { item in
            guard let existingWidget = item.widget else { return true }
            return existingWidget.kind.categoryGroup != targetCategory
        }

        let copy: [LayoutItem]
        if let targetPage {
            copy = insertItemOnPage(
                newItem,
                into: baseWithoutSameCategory,
                targetPage: targetPage,
                columns: columns,
                rows: rows
            )
        } else if let target = targetIndex {
            let visibleBase = computeVisibleItems(from: baseWithoutSameCategory)
            copy = insert(newItem, atVisibleIndex: min(max(0, target), visibleBase.count), in: baseWithoutSameCategory, visibleBase: visibleBase)
        } else {
            copy = insertItemOnPage(
                newItem,
                into: baseWithoutSameCategory,
                targetPage: 0,
                columns: columns,
                rows: rows
            )
        }

        if GridLayoutEngine.canLayout(items: computeVisibleItems(from: copy), columns: columns, rows: rows) {
            for oldKind in replacedKinds where WidgetManager.shared.isEnabled(oldKind) {
                WidgetManager.shared.toggleWidget(oldKind)
            }
            WidgetManager.shared.updateSize(for: enabledConfig.kind, size: enabledConfig.size)
            if enabledConfig.kind.categoryGroup == .music {
                WidgetManager.shared.updateMusicAppearance(for: enabledConfig.kind, appearance: enabledConfig.musicAppearance)
            }
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
        if let kind = WidgetKind(rawValue: id), WidgetManager.shared.isEnabled(kind) {
            WidgetManager.shared.toggleWidget(kind)
        }
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
            var seenCategories = Set<WidgetCategoryGroup>()
            items = file.items.filter { item in
                guard let w = item.widget else { return true }
                return seenCategories.insert(w.kind.categoryGroup).inserted
            }
            hidden = Set(file.hidden)
            customNames = file.customNames
            hasLayoutFile = true

            // Si des widgets étaient activés dans WidgetManager mais ne sont pas encore dans la grille,
            // on les insère au début pour un accueil fluide sans bug de superposition.
            if LicenseManager.shared.isPro && !items.contains(where: { $0.isWidget }) {
                var insertedCategories = Set<WidgetCategoryGroup>()
                let enabledConfigs = WidgetManager.shared.widgets
                    .filter { $0.isEnabled }
                    .sorted { $0.order < $1.order }
                    .filter { insertedCategories.insert($0.kind.categoryGroup).inserted }
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
        saveWriteQueue.async {
            do {
                let directory = url.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                let data = try encoder.encode(snapshot)
                try data.write(to: url, options: .atomic)
            } catch {
                NSLog("LaucnhPad: échec d'enregistrement de la disposition: \(error.localizedDescription)")
            }
        }
    }
}
