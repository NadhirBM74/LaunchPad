import Combine
import SwiftUI
import AppKit
import LocalAuthentication

let launchpadSpace = "LaunchpadRoot"

struct CustomTileModalModel: Identifiable {
    let id = UUID()
    var kind: CustomTile.Kind
}

// MARK: - Géométrie

struct GridMetrics: Equatable {
    var size: CGSize
    var columns: Int
    var rows: Int
    var iconScale: CGFloat
    var showLabels: Bool

    var pageSize: Int { columns * rows }
    var horizontalPadding: CGFloat { max(24, min(size.width * 0.08, 200)) }
    var cellWidth: CGFloat { max(1, (size.width - horizontalPadding * 2) / CGFloat(columns)) }
    var cellHeight: CGFloat { max(1, size.height / CGFloat(rows)) }
    var labelBlock: CGFloat { showLabels ? 22 : 0 }
    var iconSize: CGFloat {
        let fit = min(cellWidth * 0.64, (cellHeight - labelBlock) * 0.86, 150)
        return max(28, min(fit * iconScale, cellWidth - 6, cellHeight - labelBlock - 4)).rounded()
    }
    var tileHeight: CGFloat { iconSize + labelBlock }

    func center(ofSlot slot: Int) -> CGPoint {
        let column = slot % columns, row = slot / columns
        return CGPoint(x: horizontalPadding + (CGFloat(column) + 0.5) * cellWidth, y: (CGFloat(row) + 0.5) * cellHeight)
    }

    func iconCenter(ofSlot slot: Int) -> CGPoint {
        var point = center(ofSlot: slot)
        point.y -= labelBlock / 2
        return point
    }

    func hit(_ point: CGPoint) -> (slot: Int, onIcon: Bool)? {
        let x = point.x - horizontalPadding
        guard x >= 0, x < cellWidth * CGFloat(columns), point.y >= 0, point.y < size.height else { return nil }
        let column = min(columns - 1, Int(x / cellWidth))
        let row = min(rows - 1, Int(point.y / cellHeight))
        let slot = row * columns + column
        let icon = iconCenter(ofSlot: slot)
        let dx = point.x - icon.x
        let dy = point.y - icon.y
        let maxRadius = iconSize * 0.42
        return (slot, (dx * dx + dy * dy) < (maxRadius * maxRadius))
    }
}

struct FolderMetrics: Equatable {
    var panelRect: CGRect
    var contentRect: CGRect
    var columns: Int
    var cellWidth: CGFloat
    var cellHeight: CGFloat
    var iconSize: CGFloat
    var labelBlock: CGFloat
    var contentHeight: CGFloat
    var scrolls: Bool

    static let header: CGFloat = 70
    static let padding: CGFloat = 26

    static func make(rootSize: CGSize, grid: GridMetrics, count: Int) -> FolderMetrics {
        let columns = max(1, min(max(count, 3), min(grid.columns, 6)))
        let cellWidth = grid.cellWidth, cellHeight = grid.cellHeight
        let rowsNeeded = max(1, Int(ceil(Double(count) / Double(columns))))
        let maxRows = max(1, Int((rootSize.height * 0.78 - header - padding) / cellHeight))
        let visibleRows = min(rowsNeeded, maxRows)
        let width = CGFloat(columns) * cellWidth + padding * 2
        let height = header + CGFloat(visibleRows) * cellHeight + padding
        let panel = CGRect(x: (rootSize.width - width) / 2, y: max(20, (rootSize.height - height) / 2), width: width, height: height)
        let content = CGRect(x: panel.minX + padding, y: panel.minY + header, width: CGFloat(columns) * cellWidth, height: CGFloat(visibleRows) * cellHeight)
        return FolderMetrics(panelRect: panel, contentRect: content, columns: columns, cellWidth: cellWidth, cellHeight: cellHeight,
                             iconSize: grid.iconSize, labelBlock: grid.labelBlock, contentHeight: CGFloat(rowsNeeded) * cellHeight,
                             scrolls: rowsNeeded > visibleRows)
    }

    var tileHeight: CGFloat { iconSize + labelBlock }

    func center(ofSlot slot: Int) -> CGPoint {
        CGPoint(x: (CGFloat(slot % columns) + 0.5) * cellWidth, y: (CGFloat(slot / columns) + 0.5) * cellHeight)
    }

    func hit(_ rootPoint: CGPoint) -> Int? {
        let x = rootPoint.x - contentRect.minX, y = rootPoint.y - contentRect.minY
        guard x >= 0, y >= 0, x < contentRect.width, y < contentRect.height else { return nil }
        return min(Int(y / cellHeight), Int(contentRect.height / cellHeight) - 1) * columns + min(columns - 1, Int(x / cellWidth))
    }
}

// MARK: - États d'interaction

enum DragSource: Equatable { case grid, folder(String) }

struct DragState {
    let id: String
    let source: DragSource
    let isFolder: Bool
    var grabOffset: CGSize
    var detached = false
}

/// Position du pointeur pendant un glisser : isolée pour ne redessiner que l'icône flottante.
@MainActor
final class DragPointer: ObservableObject {
    @Published var location: CGPoint = .zero
}

struct DialogModel: Identifiable {
    let id = UUID()
    var title: String
    var message: String
    var confirmTitle: String
    var destructive: Bool
    var action: () -> Void
}

struct RenameRequest: Identifiable {
    let id: String
    let isFolder: Bool
    var text: String
}

// MARK: - Modèle de vue

@MainActor
final class LaunchpadViewModel: ObservableObject {
    let store: LaunchpadStore
    let pointer = DragPointer()

    @Published var query = "" { didSet { if query != oldValue { queryChanged(from: oldValue) } } }
    @Published private(set) var page = 0
    @Published private(set) var lastPage = 0
    @Published var pageOffset: CGFloat = 0
    var scrollOffset: CGFloat {
        let width = metrics?.size.width ?? 1200
        return pageOffset + CGFloat(page) * width
    }
    @Published private(set) var editing = false
    @Published private(set) var optionHeld = false
    @Published private(set) var openFolderID: String?
    @Published private(set) var folderFaded = false
    @Published private(set) var selection: Set<String> = []
    @Published private(set) var keyboardIndex: Int?
    @Published private(set) var drag: DragState?
    @Published private(set) var mergeTargetID: String?
    @Published var dialog: DialogModel?
    @Published var rename: RenameRequest?
    @Published var uninstall: UninstallSession?
    @Published var customTileModal: CustomTileModalModel?
    @Published var showWidgetGallery: Bool = false
    @Published var showTutorial: Bool = false
    @Published var tutorialStepIndex: Int = 0
    @Published private(set) var favoritesRevision = 0
    @Published private(set) var toast: String?
    @MainActor static var isLaunchpadVisible = false
    @Published private(set) var isPanelVisible = false
    @Published private(set) var appeared = false

    func setPanelVisible(_ visible: Bool) {
        Self.isLaunchpadVisible = visible
        if isPanelVisible != visible {
            isPanelVisible = visible
        }
    }
    /// 0 = caché, 1 = affiché (animée ou suivie au doigt pendant le pincement).
    let presentation = PresentationState()
    @Published private(set) var focusToken = 0
    @Published private(set) var topInset: CGFloat = 0

    var textInputActive = false
    private var newFolderID: String?
    var metrics: GridMetrics? {
        didSet {
            guard let m = metrics else { return }
            if oldValue == nil || oldValue?.size.width != m.size.width {
                pageOffset = -CGFloat(page) * m.size.width
            }
        }
    }
    var folderMetrics: FolderMetrics?
    var gridOrigin: CGPoint = .zero
    var onClose: (_ launchedApp: Bool) -> Void = { _ in }
    var onOpenSettings: () -> Void = {}
    @Published var isAuthenticatingBiometrics = false
    var onBiometricAuthChange: ((Bool) -> Void)?

    // MARK: - Flou d'arrière-plan des Réglages et Aperçu de la taille des icônes
    @Published public private(set) var isSettingsOpen = false
    @Published public private(set) var isIconScalePreviewing = false
    @Published public private(set) var settingsBlurIntensity: Double = 0.0

    public var settingsBlurRadius: CGFloat {
        CGFloat(14.0 * settingsBlurIntensity)
    }

    public var settingsScrimOpacity: Double {
        0.20 * settingsBlurIntensity
    }

    private var cancellables = Set<AnyCancellable>()

    private struct PressState {
        let id: String
        var dragging = false
        var longPressFired = false
    }

    private var press: PressState?
    private var folderSnapshot: FolderData?
    private var pageBeforeSearch = 0
    private var longPressTask: Task<Void, Never>?
    private var reorderTask: Task<Void, Never>?
    private var pendingReorderKey: String?
    private var pendingReorderAction: (() -> Void)?
    private var mergeTask: Task<Void, Never>?
    private var mergeCandidate: String?
    private var edgeTask: Task<Void, Never>?
    private var edgeDirection = 0
    private var toastTask: Task<Void, Never>?
    private var scrollAccumulator: CGFloat = 0
    private var scrollSamples: [(time: TimeInterval, delta: CGFloat)] = []
    private var lastWheel = Date.distantPast
    private var searchCacheKey = ""
    private var searchCacheRevision = -1
    private var searchCache: [LayoutItem] = []

    init(store: LaunchpadStore) {
        self.store = store

        NotificationCenter.default.publisher(for: .settingsVisibilityDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                let visible = (note.object as? Bool) ?? false
                self?.setSettingsOpen(visible)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .iconScalePreviewDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                let previewing = (note.object as? Bool) ?? false
                self?.setIconScalePreviewing(previewing)
            }
            .store(in: &cancellables)
    }

    func setSettingsOpen(_ open: Bool) {
        guard isSettingsOpen != open else { return }
        isSettingsOpen = open
        if !open {
            isIconScalePreviewing = false
        }
        updateSettingsBlur(animated: true)
    }

    func setIconScalePreviewing(_ previewing: Bool) {
        guard isIconScalePreviewing != previewing else { return }
        isIconScalePreviewing = previewing
        updateSettingsBlur(animated: true)
    }

    private func updateSettingsBlur(animated: Bool) {
        let targetIntensity: Double = (isSettingsOpen && !isIconScalePreviewing) ? 1.0 : 0.0
        let reduceMotion = Prefs.reduceMotion
        if !animated || reduceMotion {
            settingsBlurIntensity = targetIntensity
        } else {
            let duration: Double = isSettingsOpen ? (isIconScalePreviewing ? 0.22 : 0.26) : 0.22
            withAnimation(.easeInOut(duration: duration)) {
                settingsBlurIntensity = targetIntensity
            }
        }
    }


    // MARK: Données affichées

    var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isSearching: Bool { !trimmedQuery.isEmpty }
    var displayItems: [LayoutItem] { isSearching ? searchResults : store.visibleItems }
    var pageSize: Int { metrics?.pageSize ?? Prefs.pageSize }
    // Cache de disposition pour éviter le recalcul lourd de la matrice à chaque pixel de défilement ou survol
    private var cachedLayoutMetrics: GridMetrics?
    private var cachedLayoutItems: [LayoutItem]?
    private var cachedStoreRevision: Int = -1
    private var cachedIsSearching: Bool = false
    private var cachedSearchKey: String = ""
    private var cachedPlacedItems: [PlacedItem] = []
    private var cachedPageCount: Int = 1
    private var cachedPlacedLookup: [String: PlacedItem] = [:]
    private var cachedSlotLookup: [Int: PlacedItem] = [:]

    var pageCount: Int {
        guard let m = metrics else { return max(1, (displayItems.count + pageSize - 1) / pageSize) }
        _ = placedDisplayItems(metrics: m)
        return cachedPageCount
    }

    func placedDisplayItems(metrics m: GridMetrics) -> [PlacedItem] {
        let searching = isSearching
        let q = searching ? trimmedQuery : ""
        let rev = store.revision

        if let cachedM = cachedLayoutMetrics, cachedM == m,
           cachedIsSearching == searching,
           cachedStoreRevision == rev,
           (!searching || cachedSearchKey == q) {
            return cachedPlacedItems
        }

        let currentItems = displayItems
        if let cachedM = cachedLayoutMetrics, cachedM == m,
           let cachedI = cachedLayoutItems, cachedI == currentItems {
            cachedIsSearching = searching
            cachedStoreRevision = rev
            cachedSearchKey = q
            return cachedPlacedItems
        }
        let result = GridLayoutEngine.computeLayout(items: currentItems, columns: m.columns, rows: m.rows, metrics: m)
        cachedLayoutMetrics = m
        cachedLayoutItems = currentItems
        cachedIsSearching = searching
        cachedStoreRevision = rev
        cachedSearchKey = q
        cachedPlacedItems = result
        var maxPageIndex = 0
        var lookup: [String: PlacedItem] = [:]
        var slotLookup: [Int: PlacedItem] = [:]
        lookup.reserveCapacity(result.count)
        slotLookup.reserveCapacity(result.count * 4)
        for item in result {
            if item.page > maxPageIndex { maxPageIndex = item.page }
            lookup[item.id] = item
            let pShift = item.page << 16
            for r in item.row..<(item.row + item.rowSpan) {
                let rShift = r << 8
                for c in item.col..<(item.col + item.colSpan) {
                    slotLookup[pShift | rShift | c] = item
                }
            }
        }
        cachedPageCount = max(1, maxPageIndex + 1)
        cachedPlacedLookup = lookup
        cachedSlotLookup = slotLookup
        return result
    }

    func placedItem(for id: String) -> PlacedItem? {
        guard let m = metrics else { return nil }
        _ = placedDisplayItems(metrics: m)
        return cachedPlacedLookup[id]
    }

    func placedItemAt(page: Int, col: Int, row: Int) -> PlacedItem? {
        guard let m = metrics else { return nil }
        _ = placedDisplayItems(metrics: m)
        return cachedSlotLookup[(page << 16) | (row << 8) | col]
    }

    var columns: Int { metrics?.columns ?? Prefs.columns }
    var rows: Int { metrics?.rows ?? Prefs.rows }

    var isPresentingModal: Bool { dialog != nil || rename != nil || uninstall != nil || customTileModal != nil || showTutorial }
    var showsDeleteBadges: Bool { (editing || optionHeld) && !isSearching }

    var overlayFolder: FolderData? {
        guard let id = openFolderID else { return nil }
        return store.visibleFolder(id) ?? folderSnapshot
    }

    var searchResults: [LayoutItem] {
        let text = trimmedQuery
        if text == searchCacheKey, store.revision == searchCacheRevision { return searchCache }
        let fold: (String) -> String = { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }
        let needle = fold(text)
        let includeHidden = Prefs.showHiddenInSearch
        var scored: [(score: Int, name: String, id: String)] = []
        for app in store.catalog.values where includeHidden || !store.hidden.contains(app.id) {
            let display = store.displayName(app.id)
            let name = (display == app.name) ? app.normalizedName : fold(display)
            let words = name.split(whereSeparator: { " -._".contains($0) })
            let initials = String(words.compactMap(\.first))
            let score: Int?
            if name.hasPrefix(needle) { score = 0 }
            else if words.contains(where: { $0.hasPrefix(needle) }) { score = 1 }
            else if name.contains(needle) { score = 2 }
            else if needle.count >= 2, initials.hasPrefix(needle) { score = 3 }
            else if app.normalizedName.contains(needle) { score = 4 }
            else if needle.count >= 3, let bundle = app.normalizedBundleID, bundle.contains(needle) { score = 5 }
            else { score = nil }
            if let score { scored.append((score, display, app.id)) }
        }
        scored.sort { $0.score == $1.score ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : $0.score < $1.score }
        searchCache = scored.map { LayoutItem.app($0.id) }
        searchCacheKey = text
        searchCacheRevision = store.revision
        return searchCache
    }

    private func queryChanged(from old: String) {
        let wasSearching = !old.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if isSearching, !wasSearching { pageBeforeSearch = page }
        if isSearching {
            if openFolderID != nil { closeFolder() }
            page = 0
            keyboardIndex = 0
        } else {
            page = min(pageBeforeSearch, max(0, pageCount - 1))
            keyboardIndex = nil
        }
        lastPage = page
        let width = metrics?.size.width ?? 1200
        pageOffset = -CGFloat(page) * width
        editing = false
        optionHeld = false
        selection.removeAll()
    }

    // MARK: Cycle de vie

    func prepareForShow(topInset: CGFloat, resetPage: Bool) {
        self.topInset = topInset
        if resetPage {
            page = 0
            lastPage = 0
        } else {
            page = min(page, max(0, pageCount - 1))
            lastPage = page
        }
        let width = metrics?.size.width ?? 1200
        pageOffset = -CGFloat(page) * width
        resetTransientState()
        appeared = false
        focusToken &+= 1
        updateSettingsBlur(animated: false)
    }

    func setAppeared(_ value: Bool) {
        appeared = value
        let target: Double = value ? 1 : 0
        if Prefs.reduceMotion {
            setPresentation(target)
        } else {
            // Comme le Launchpad de macOS : les icônes arrivent en zoom arrière, le fond apparaît en fondu.
            withAnimation(value ? .spring(response: 0.42, dampingFraction: 0.86) : .easeIn(duration: Self.hideDuration)) {
                presentation.progress = target
            }
        }
    }

    static let hideDuration = 0.2

    /// Progression pilotée au doigt (pincement), sans animation implicite.
    func setPresentation(_ value: Double) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { presentation.progress = min(max(value, 0), 1) }
    }

    func updateTopInset(_ value: CGFloat) {
        if topInset != value { topInset = value }
    }

    func setEditing(_ value: Bool) {
        guard editing != value else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            editing = value
        }
    }

    #if DEBUG
    func debugSetEditing(_ value: Bool) { editing = value }
    #endif

    /// Mode fenêtre : zone (coordonnées du panneau) où le Launchpad est dessiné ; nil = plein écran.
    @Published private(set) var windowRect: CGRect?

    func updateWindowRect(_ rect: CGRect?) {
        if windowRect != rect { windowRect = rect }
    }

    func didHide() {
        resetTransientState()
        if !query.isEmpty { query = "" }
        if Prefs.returnToFirstPage == 0 {
            page = 0
            lastPage = 0
            pageOffset = 0
        }
        if !isSettingsOpen {
            settingsBlurIntensity = 0.0
        }
    }

    private func resetTransientState() {
        [longPressTask, reorderTask, mergeTask, edgeTask].forEach { $0?.cancel() }
        press = nil
        drag = nil
        pendingReorderKey = nil
        pendingReorderAction = nil
        mergeCandidate = nil
        mergeTargetID = nil
        edgeDirection = 0
        editing = false
        optionHeld = false
        openFolderID = nil
        folderFaded = false
        folderSnapshot = nil
        selection.removeAll()
        keyboardIndex = nil
        dialog = nil
        rename = nil
        uninstall = nil
        customTileModal = nil
        textInputActive = false
    }

    func close(launchedApp: Bool = false) { onClose(launchedApp) }
    func focusSearch() { focusToken &+= 1 }

    func motion(_ animation: Animation) -> Animation? { Prefs.reduceMotion ? nil : animation }

    // MARK: Pagination

    func setPage(_ value: Int, keepKeyboardSelection: Bool = false) {
        let clamped = min(max(value, 0), pageCount - 1)
        let changed = clamped != page
        let oldPage = page
        lastPage = oldPage
        page = clamped
        let width = metrics?.size.width ?? 1200
        let targetOffset = -CGFloat(clamped) * width

        if Prefs.reduceMotion {
            pageOffset = targetOffset
            lastPage = clamped
        } else {
            withAnimation(motion(.spring(response: 0.38, dampingFraction: 0.86))) {
                pageOffset = targetOffset
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                guard let self else { return }
                self.lastPage = self.page
            }
        }
        if changed, !keepKeyboardSelection, keyboardIndex != nil {
            keyboardIndex = min(clamped * pageSize, max(0, displayItems.count - 1))
        }
    }

    private func rubberBand(_ offset: CGFloat) -> CGFloat {
        if (page == 0 && offset > 0) || (page >= pageCount - 1 && offset < 0) { return offset * 0.25 }
        return offset
    }

    private func finishPaging(offset: CGFloat, velocity: CGFloat) {
        let width = metrics?.size.width ?? 1200
        var target = page
        if offset < -width * 0.15 || velocity < -650 { target += 1 }
        else if offset > width * 0.15 || velocity > 650 { target -= 1 }
        setPage(target)
    }

    func backgroundDragChanged(_ translation: CGFloat) {
        guard drag == nil, openFolderID == nil else { return }
        let width = metrics?.size.width ?? 1200
        let baseOffset = -CGFloat(page) * width
        pageOffset = baseOffset + rubberBand(translation)
    }

    func backgroundDragEnded(_ translation: CGFloat, predicted: CGFloat) {
        guard drag == nil, openFolderID == nil else { return }
        finishPaging(offset: rubberBand(translation), velocity: (predicted - translation) * 3)
    }

    /// Défilement à deux doigts (suivi interactif, comme le « paged drag » de LaunchOS) ou molette.
    func handleScroll(_ event: NSEvent) -> Bool {
        guard openFolderID == nil, drag == nil, !isPresentingModal else { return false }
        let hasPhases = event.phase != [] || event.momentumPhase != []
        if event.hasPreciseScrollingDeltas, hasPhases {
            if event.momentumPhase != [] { return true }
            let delta = abs(event.scrollingDeltaX) >= abs(event.scrollingDeltaY) ? event.scrollingDeltaX : event.scrollingDeltaY
            let now = ProcessInfo.processInfo.systemUptime
            let width = metrics?.size.width ?? 1200
            let baseOffset = -CGFloat(page) * width
            switch event.phase {
            case .began, .mayBegin:
                scrollAccumulator = 0
                scrollSamples.removeAll()
            case .changed:
                scrollAccumulator += delta * CGFloat(Prefs.scrollSensitivity)
                scrollSamples.append((now, delta * CGFloat(Prefs.scrollSensitivity)))
                scrollSamples.removeAll { now - $0.time > 0.1 }
                pageOffset = baseOffset + rubberBand(scrollAccumulator)
            case .ended, .cancelled:
                let recent = scrollSamples.filter { now - $0.time <= 0.1 }
                let velocity = recent.reduce(0) { $0 + $1.delta } / 0.1
                let offset = rubberBand(scrollAccumulator)
                scrollAccumulator = 0
                scrollSamples.removeAll()
                finishPaging(offset: offset, velocity: velocity)
            default:
                break
            }
            return true
        }
        let delta = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.scrollingDeltaX
        guard delta != 0 else { return true }
        if Date().timeIntervalSince(lastWheel) > 0.28 {
            lastWheel = Date()
            setPage(page + (delta < 0 ? 1 : -1))
        }
        return true
    }

    // MARK: Clavier

    func handleKeyDown(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case ",": onOpenSettings(); return true
            case "w", "q": close(); return true
            case "f": focusSearch(); return true
            default: return false
            }
        }
        if event.keyCode == 53 { escape(); return true }
        if isPresentingModal || textInputActive { return false }
        switch event.keyCode {
        case 36, 76: activateKeyboardSelection(); return true
        case 123: moveSelection(dx: -1, dy: 0); return true
        case 124: moveSelection(dx: 1, dy: 0); return true
        case 125: moveSelection(dx: 0, dy: 1); return true
        case 126: moveSelection(dx: 0, dy: -1); return true
        default: return false
        }
    }

    func handleFlags(_ flags: NSEvent.ModifierFlags) {
        let held = flags.contains(.option) && !flags.contains(.command) && !flags.contains(.control)
            && !isSearching && !textInputActive && !isPresentingModal
        if held != optionHeld { withAnimation(.easeOut(duration: 0.15)) { optionHeld = held } }
    }

    func escape() {
        if showTutorial { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showTutorial = false }; focusSearch() }
        else if uninstall != nil, uninstall?.working == false { uninstall = nil; focusSearch() }
        else if customTileModal != nil { customTileModal = nil; focusSearch() }
        else if rename != nil { rename = nil; textInputActive = false; focusSearch() }
        else if dialog != nil { dialog = nil }
        else if openFolderID != nil { closeFolder() }
        else if editing || optionHeld { withAnimation(.easeOut(duration: 0.2)) { editing = false; optionHeld = false } }
        else if !selection.isEmpty { selection.removeAll() }
        else if !query.isEmpty { query = "" }
        else { close() }
    }

    private func moveSelection(dx: Int, dy: Int) {
        let items = displayItems
        guard !items.isEmpty else { return }
        guard let current = keyboardIndex else {
            if dy == 0, !isSearching { setPage(page + dx); return }
            keyboardIndex = min(page * pageSize, items.count - 1)
            return
        }
        let columns = metrics?.columns ?? Prefs.columns
        let next = min(max(current + dx + dy * columns, 0), items.count - 1)
        keyboardIndex = next
        let targetPage = next / pageSize
        if targetPage != page { setPage(targetPage, keepKeyboardSelection: true) }
    }

    private func activateKeyboardSelection() {
        let items = displayItems
        if let index = keyboardIndex, index < items.count { activate(items[index]) }
        else if isSearching, let first = items.first { activate(first) }
    }

    // MARK: Ouverture

    func activate(_ item: LayoutItem) {
        switch item {
        case .app(let id):
            guard let app = store.catalog[id] else { return }
            AppActions.open(app)
            close(launchedApp: true)
        case .folder(let folder):
            openFolder(folder.id)
        case .widget:
            break
        }
    }

    func openFolder(_ id: String) {
        guard let folder = store.visibleFolder(id) else { return }
        if folder.isLocked {
            authenticateWithTouchID(reason: "Déverrouiller le dossier « \(folder.name) »") { [weak self] success in
                guard let self else { return }
                if success {
                    self.performOpenFolder(id)
                } else {
                    self.showToast("Authentification requise pour ouvrir ce dossier")
                }
            }
        } else {
            performOpenFolder(id)
        }
    }

    private func performOpenFolder(_ id: String) {
        folderSnapshot = store.visibleFolder(id)
        keyboardIndex = nil
        withAnimation(motion(.spring(response: 0.36, dampingFraction: 0.86))) {
            openFolderID = id
            folderFaded = false
        }
    }

    func authenticateWithTouchID(reason: String, completion: @escaping @MainActor @Sendable (Bool) -> Void) {
        let context = LAContext()
        context.localizedCancelTitle = "Annuler"
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            isAuthenticatingBiometrics = true
            onBiometricAuthChange?(true)
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { [weak self] success, _ in
                guard let self else { return }
                Task { @MainActor in
                    self.isAuthenticatingBiometrics = false
                    self.onBiometricAuthChange?(false)
                    completion(success)
                }
            }
        } else {
            completion(true)
        }
    }

    func closeFolder(refocusSearch: Bool = true) {
        withAnimation(motion(.spring(response: 0.32, dampingFraction: 0.9))) {
            openFolderID = nil
            folderFaded = false
        }
        folderSnapshot = nil
        textInputActive = false
        if refocusSearch { focusSearch() }
    }

    func backgroundClicked() {
        if isSettingsOpen {
            NotificationCenter.default.post(name: .settingsVisibilityDidChange, object: false)
            return
        }
        if openFolderID != nil { closeFolder() }
        else if editing { withAnimation(.easeOut(duration: 0.2)) { editing = false } }
        else if !selection.isEmpty { selection.removeAll() }
        else { close() }
    }

    // MARK: Pointeur (clic, appui long, glisser) — un seul geste par icône

    var canDrag: Bool { !isSearching && !isPresentingModal }

    func pointerChanged(_ item: LayoutItem, source: DragSource, value: DragGesture.Value) {
        if press?.id != item.id {
            guard drag == nil else { return }
            press = PressState(id: item.id)
            startLongPress(item.id)
        }
        guard var current = press else { return }
        if current.dragging {
            updateDrag(to: value.location)
            return
        }
        guard hypot(value.translation.width, value.translation.height) > 5 else { return }
        longPressTask?.cancel()
        guard canDrag else { return }
        current.dragging = true
        press = current
        beginDrag(item, source: source, value: value)
    }

    func pointerEnded(_ item: LayoutItem, source: DragSource, value: DragGesture.Value) {
        longPressTask?.cancel()
        guard let current = press, current.id == item.id else { return }
        press = nil
        if current.dragging { endDrag(); return }
        if current.longPressFired { return }
        click(item, source: source)
    }

    /// SwiftUI peut annuler un geste sans appeler onEnded : on nettoie l'état.
    func pointerCancelled(_ id: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let current = self.press, current.id == id else { return }
            self.press = nil
            self.longPressTask?.cancel()
            if current.dragging { self.endDrag() }
        }
    }

    private func startLongPress(_ id: String) {
        longPressTask?.cancel()
        longPressTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(550))
            guard let self, !Task.isCancelled, var current = self.press, current.id == id, !current.dragging else { return }
            current.longPressFired = true
            self.press = current
            if !self.isSearching { withAnimation(.easeOut(duration: 0.2)) { self.editing = true } }
        }
    }

    private func click(_ item: LayoutItem, source: DragSource) {
        if NSEvent.modifierFlags.contains(.command), source == .grid, !isSearching {
            if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
            return
        }
        if editing, item.appID != nil {
            withAnimation(.easeOut(duration: 0.2)) { editing = false }
            return
        }
        selection.removeAll()
        activate(item)
    }

    // MARK: Glisser-déposer

    private func iconCenter(for id: String, source: DragSource) -> CGPoint? {
        switch source {
        case .grid:
            guard let m = metrics, let placed = placedItem(for: id) else { return nil }
            return CGPoint(x: placed.center.x + CGFloat(placed.page) * m.size.width + pageOffset + gridOrigin.x,
                           y: placed.center.y + gridOrigin.y)
        case .folder:
            guard let fm = folderMetrics, let index = overlayFolder?.apps.firstIndex(of: id) else { return nil }
            let point = fm.center(ofSlot: index)
            return CGPoint(x: fm.contentRect.minX + point.x, y: fm.contentRect.minY + point.y - fm.labelBlock / 2)
        }
    }

    private func beginDrag(_ item: LayoutItem, source: DragSource, value: DragGesture.Value) {
        let center = iconCenter(for: item.id, source: source) ?? value.startLocation
        pointer.location = value.location
        drag = DragState(id: item.id, source: source, isFolder: item.isFolder,
                         grabOffset: CGSize(width: value.startLocation.x - center.x, height: value.startLocation.y - center.y))
        selection.removeAll()
        keyboardIndex = nil
        if !editing { withAnimation(.easeOut(duration: 0.2)) { editing = true } }
        updateDrag(to: value.location)
    }

    private func updateDrag(to location: CGPoint) {
        guard let state = drag else { return }
        pointer.location = location
        switch state.source {
        case .grid:
            gridHover(location)
        case .folder(let folderID):
            if state.detached {
                gridHover(location)
            } else if let fm = folderMetrics, fm.panelRect.insetBy(dx: -12, dy: -12).contains(location) {
                folderHover(location, folderID: folderID)
            } else {
                detach(from: folderID)
            }
        }
    }

    private func gridHover(_ location: CGPoint) {
        guard let m = metrics, let state = drag else { return }
        if location.x < 40 { scheduleEdge(-1) }
        else if location.x > m.size.width - 40 { scheduleEdge(1) }
        else { cancelEdge() }

        let local = CGPoint(x: location.x - gridOrigin.x, y: location.y - gridOrigin.y)
        guard let hit = m.hit(local) else { cancelMerge(); cancelReorder(); return }
        let items = store.visibleItems
        guard let draggedIndex = items.firstIndex(where: { $0.id == state.id }) else { return }

        let placedItems = placedDisplayItems(metrics: m)
        let hitCol = hit.slot % m.columns
        let hitRow = hit.slot / m.columns
        let targetPlaced = placedItemAt(page: page, col: hitCol, row: hitRow)
        let isDraggedWidget = state.id.hasPrefix("widget:") || items[draggedIndex].isWidget
        let isTargetWidget = targetPlaced?.isWidget == true

        if hit.onIcon, let targetPlaced, targetPlaced.id != state.id, !state.isFolder, !isDraggedWidget, !isTargetWidget {
            cancelReorder()
            scheduleMerge(targetPlaced.id)
            return
        }
        cancelMerge()

        if let targetPlaced {
            guard targetPlaced.id != state.id else { cancelReorder(); return }
            guard let targetIdx = items.firstIndex(where: { $0.id == targetPlaced.id }) else { return }
            guard targetIdx != draggedIndex else { cancelReorder(); return }
            let id = state.id
            scheduleReorder(key: "grid-\(targetIdx)") { [weak self] in
                self?.store.moveItem(id, toVisibleIndex: targetIdx)
            }
        } else {
            let pageItems = placedItems.filter { $0.page == page }
            if let last = pageItems.last, let targetIdx = items.firstIndex(where: { $0.id == last.id }), targetIdx != draggedIndex {
                let id = state.id
                scheduleReorder(key: "grid-end-\(targetIdx)") { [weak self] in
                    self?.store.moveItem(id, toVisibleIndex: targetIdx)
                }
            }
        }
    }

    private func folderHover(_ location: CGPoint, folderID: String) {
        guard let fm = folderMetrics, !fm.scrolls, let state = drag,
              let folder = store.visibleFolder(folderID), let slot = fm.hit(location) else { cancelReorder(); return }
        let desired = min(slot, folder.apps.count - 1)
        guard let current = folder.apps.firstIndex(of: state.id), desired != current else { cancelReorder(); return }
        let id = state.id
        scheduleReorder(key: "folder-\(desired)") { [weak self] in
            self?.store.moveInFolder(id, folderID: folderID, toVisibleIndex: desired)
        }
    }

    private func detach(from folderID: String) {
        guard var state = drag else { return }
        cancelReorder()
        cancelMerge()
        folderSnapshot = overlayFolder
        withAnimation(motion(.easeOut(duration: 0.22))) {
            store.removeFromFolder(state.id, folderID: folderID)
            folderFaded = true
        }
        state.detached = true
        drag = state
        if let m = metrics, let index = store.visibleItems.firstIndex(where: { $0.id == state.id }) {
            setPage(index / m.pageSize)
        }
    }

    private func endDrag() {
        cancelEdge()
        reorderTask?.cancel()
        if let action = pendingReorderAction {
            withAnimation(motion(.spring(response: 0.3, dampingFraction: 0.85))) { action() }
        }
        pendingReorderKey = nil
        pendingReorderAction = nil
        mergeTask?.cancel()
        guard let state = drag else { return }
        // Comme sur iPhone : lâcher une app sur une autre crée un dossier (même si le survol a été bref).
        let target = state.isFolder ? nil : (mergeTargetID ?? mergeCandidate)
        let targetWasApp = target.map { id in store.visibleItems.first { $0.id == id }?.isFolder == false } ?? false
        var createdFolder: String?
        if let target {
            withAnimation(motion(.spring(response: 0.35, dampingFraction: 0.8))) {
                let folderID = store.merge(state.id, onto: target)
                if targetWasApp { createdFolder = folderID }
            }
        }
        mergeTargetID = nil
        mergeCandidate = nil
        withAnimation(motion(.spring(response: 0.3, dampingFraction: 0.85))) { drag = nil }
        if state.detached { closeFolder(refocusSearch: createdFolder == nil) }
        store.scheduleSave()

        // Nouveau dossier : il s'ouvre aussitôt avec son nom prêt à être modifié.
        if let createdFolder {
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(280))
                guard let self, self.drag == nil, self.openFolderID == nil, self.appeared,
                      self.store.visibleFolder(createdFolder) != nil else { return }
                self.newFolderID = createdFolder
                self.openFolder(createdFolder)
            }
        }
    }

    /// Le dossier vient d'être créé par glisser-déposer : son titre doit recevoir le focus.
    func consumeNewFolder(_ id: String) -> Bool {
        guard newFolderID == id else { return false }
        newFolderID = nil
        return true
    }

    private func scheduleReorder(key: String, _ action: @escaping () -> Void) {
        guard pendingReorderKey != key else { return }
        pendingReorderKey = key
        pendingReorderAction = action
        reorderTask?.cancel()
        reorderTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(110))
            guard let self, !Task.isCancelled, self.drag != nil, let action = self.pendingReorderAction else { return }
            self.pendingReorderKey = nil
            self.pendingReorderAction = nil
            withAnimation(self.motion(.spring(response: 0.32, dampingFraction: 0.82))) { action() }
        }
    }

    private func cancelReorder() {
        reorderTask?.cancel()
        pendingReorderKey = nil
        pendingReorderAction = nil
    }

    private func scheduleMerge(_ targetID: String) {
        guard mergeCandidate != targetID else { return }
        mergeCandidate = targetID
        if mergeTargetID != nil { withAnimation { mergeTargetID = nil } }
        mergeTask?.cancel()
        mergeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(240))
            guard let self, !Task.isCancelled, self.mergeCandidate == targetID, self.drag != nil else { return }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { self.mergeTargetID = targetID }
        }
    }

    private func cancelMerge() {
        mergeTask?.cancel()
        mergeCandidate = nil
        if mergeTargetID != nil { withAnimation(.easeOut(duration: 0.15)) { mergeTargetID = nil } }
    }

    private func scheduleEdge(_ direction: Int) {
        guard edgeDirection != direction else { return }
        edgeDirection = direction
        edgeTask?.cancel()
        edgeTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(600))
                guard let self, !Task.isCancelled, self.drag != nil else { return }
                let target = self.page + direction
                guard target >= 0, target < self.pageCount else { return }
                self.setPage(target)
                self.gridHover(self.pointer.location)
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
    }

    private func cancelEdge() {
        edgeTask?.cancel()
        edgeDirection = 0
    }

    // MARK: Actions (menu contextuel)

    func requestUninstall(_ app: AppInfo) {
        if app.id.hasPrefix("web:") || app.id.hasPrefix("shortcut:") {
            requestDeleteCustomTile(id: app.id, title: app.name)
            return
        }
        guard app.isRemovable else { return }
        if !LicenseManager.shared.isPro {
            showProUpgradeAlert(
                feature: "Désinstallation complète",
                description: "La désinstallation complète (suppression de l'application et de tous ses fichiers résiduels : caches, préférences, conteneurs) est réservée à la version Pro.\n\nActivez votre licence avec le code 1234 dans les Réglages pour débloquer cette fonctionnalité."
            )
            return
        }
        uninstall = UninstallSession(app: app)
    }

    func requestUninstall(for item: LayoutItem) {
        guard let id = item.appID else { return }
        if id.hasPrefix("web:") || id.hasPrefix("shortcut:") {
            let title = store.catalog[id]?.name ?? store.displayName(id)
            requestDeleteCustomTile(id: id, title: title)
            return
        }
        guard let app = store.catalog[id] else { return }
        requestUninstall(app)
    }

    func requestDeleteCustomTile(id: String, title: String) {
        let isWeb = id.hasPrefix("web:")
        let typeName = isWeb ? loc("overlay.web_bookmark") : loc("overlay.apple_shortcut")
        dialog = DialogModel(
            title: "\(loc("menu.delete_from_launchpad")) « \(title) » ?",
            message: "\(typeName) — \(loc("menu.delete_from_launchpad"))",
            confirmTitle: loc("menu.delete_from_launchpad"),
            destructive: true,
            action: { [weak self] in
                self?.removeCustomTile(id)
            }
        )
    }

    // MARK: - Fonctionnalités Pro

    func showProUpgradeAlert(feature: String, description: String) {
        dialog = DialogModel(
            title: feature,
            message: description,
            confirmTitle: loc("license.validate_button"),
            destructive: false,
            action: { [weak self] in
                self?.openSettingsForLicense()
            }
        )
    }

    func openSettingsForLicense() {
        SettingsPanel.targetTab = .license
        onOpenSettings()
    }

    // Touch ID Dossiers
    func toggleFolderLock(_ folder: FolderData) {
        if !LicenseManager.shared.isPro {
            showProUpgradeAlert(
                feature: loc("pro_alert.touchid_title"),
                description: loc("pro_alert.touchid_msg")
            )
            return
        }

        if !folder.isLocked {
            let newState = store.toggleFolderLock(folder.id)
            if newState {
                showToast(loc("toast.touchid_locked", folder.name))
            }
        } else {
            authenticateWithTouchID(reason: "Touch ID : \(folder.name)") { [weak self] success in
                guard let self else { return }
                if success {
                    _ = self.store.toggleFolderLock(folder.id)
                    self.showToast(loc("toast.touchid_removed", folder.name))
                } else {
                    self.showToast(loc("toast.auth_required"))
                }
            }
        }
    }

    // Barre de favoris
    var favoriteApps: [AppInfo] {
        _ = favoritesRevision
        return Prefs.favoriteAppIDs.compactMap { store.catalog[$0] }
    }

    func isFavorite(_ id: String) -> Bool {
        _ = favoritesRevision
        return Prefs.favoriteAppIDs.contains(id)
    }

    func toggleFavorite(_ id: String) {
        if !LicenseManager.shared.isPro {
            showProUpgradeAlert(
                feature: loc("pro_alert.favorites_title"),
                description: loc("pro_alert.favorites_msg")
            )
            return
        }

        var ids = Prefs.favoriteAppIDs
        let appName = store.displayName(id)
        if let idx = ids.firstIndex(of: id) {
            ids.remove(at: idx)
            showToast(loc("toast.favorite_removed", appName))
        } else {
            ids.append(id)
            showToast(loc("toast.favorite_added", appName))
        }
        Prefs.favoriteAppIDs = ids
        favoritesRevision &+= 1
        objectWillChange.send()
    }

    // Signets Web & Raccourcis Apple
    func requestAddWebBookmark() {
        if !LicenseManager.shared.isPro {
            showProUpgradeAlert(
                feature: loc("pro_alert.custom_tile_title"),
                description: loc("pro_alert.custom_tile_msg")
            )
            return
        }
        customTileModal = CustomTileModalModel(kind: .web)
    }

    func requestAddShortcut() {
        if !LicenseManager.shared.isPro {
            showProUpgradeAlert(
                feature: loc("pro_alert.custom_tile_title"),
                description: loc("pro_alert.custom_tile_msg")
            )
            return
        }
        customTileModal = CustomTileModalModel(kind: .shortcut)
    }

    func addCustomTile(title: String, target: String, kind: CustomTile.Kind, symbol: String, colorHex: String) {
        let tile = CustomTileManager.shared.addTile(title: title, target: target, kind: kind, symbol: symbol, colorHex: colorHex)
        store.addCustomTile(tile)
        customTileModal = nil
        showToast(loc("toast.tile_added", title))
    }

    func removeCustomTile(_ id: String) {
        selection.remove(id)
        store.removeCustomTile(id)
        searchCache = []
        searchCacheKey = ""
        showToast(loc("toast.tile_removed"))
    }

    func confirmUninstall() {
        guard let session = uninstall, !session.working else { return }
        Task { [weak self] in
            let result = await session.perform()
            guard let self else { return }
            self.uninstall = nil
            if result.appRemoved {
                withAnimation(self.motion(.spring(response: 0.3, dampingFraction: 0.85))) { self.store.forget([session.app.id]) }
            }
            if result.failures > 0 {
                self.showToast(loc("toast.delete_failed", result.failures))
            } else if result.appRemoved {
                self.showToast(loc("toast.app_trashed", session.app.name))
            }
            self.store.scheduleRefresh()
            self.focusSearch()
        }
    }

    func requestForceQuit(_ app: AppInfo) {
        dialog = DialogModel(title: "Forcer « \(app.name) » à quitter ?",
                             message: "Les modifications non enregistrées seront perdues.",
                             confirmTitle: "Forcer à quitter", destructive: true) { AppActions.forceQuit(app) }
    }

    func requestRename(id: String, isFolder: Bool) {
        let current = isFolder ? (store.visibleFolder(id)?.name ?? "") : store.displayName(id)
        rename = RenameRequest(id: id, isFolder: isFolder, text: current)
    }

    func commitRename(_ text: String) {
        guard let request = rename else { return }
        if request.isFolder { store.renameFolder(request.id, to: text) } else { store.setCustomName(request.id, to: text) }
        rename = nil
        textInputActive = false
        focusSearch()
    }

    func hide(_ ids: [String]) {
        withAnimation(motion(.spring(response: 0.3, dampingFraction: 0.85))) { store.hide(ids) }
        selection.removeAll()
        showToast(ids.count > 1 ? "Éléments masqués — réaffichez-les depuis Réglages › Apps" : "Masqué — réaffichez-le depuis Réglages › Apps")
    }

    func makeFolderFromSelection() {
        let ids = displayItems.map(\.id).filter { selection.contains($0) }
        withAnimation(motion(.spring(response: 0.35, dampingFraction: 0.85))) { _ = store.makeFolder(from: ids) }
        selection.removeAll()
    }

    func removeFromFolder(_ appID: String, folderID: String) {
        withAnimation(motion(.spring(response: 0.3, dampingFraction: 0.85))) { store.removeFromFolder(appID, folderID: folderID) }
        if store.visibleFolder(folderID) == nil { closeFolder() }
    }

    func ungroup(_ folderID: String) {
        if openFolderID == folderID { closeFolder() }
        withAnimation(motion(.spring(response: 0.3, dampingFraction: 0.85))) { store.ungroup(folderID) }
    }

    func addToDock(_ app: AppInfo) {
        showToast(AppActions.addToDock(app) ? "« \(app.name) » ajoutée au Dock" : "« \(app.name) » est déjà dans le Dock")
    }

    func showInfo(_ app: AppInfo) {
        AppActions.showInfo(app)
        close(launchedApp: true)
    }

    func reveal(_ app: AppInfo) {
        AppActions.revealInFinder(app)
        close(launchedApp: true)
    }

    func requestReorganize() {
        let rule = SortRule(rawValue: Prefs.defaults.string(forKey: PrefKey.reorganizeRule) ?? "") ?? .nameAscending
        let placement = FolderPlacement(rawValue: Prefs.defaults.string(forKey: PrefKey.folderPlacement) ?? "") ?? .before
        let sortFolders = Prefs.defaults.bool(forKey: PrefKey.sortFolderContents)
        dialog = DialogModel(title: "Réorganiser la disposition ?",
                             message: "Règle : \(rule.title).\nLa disposition actuelle sera remplacée. Pensez à exporter une sauvegarde depuis les réglages.",
                             confirmTitle: "Réorganiser", destructive: false) { [weak self] in
            guard let self else { return }
            withAnimation(self.motion(.spring(response: 0.4, dampingFraction: 0.86))) {
                self.store.reorganize(rule: rule, placement: placement, sortFolderContents: sortFolders)
            }
            self.setPage(0)
        }
    }

    func showToast(_ text: String) {
        withAnimation(.easeOut(duration: 0.2)) { toast = text }
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.25)) { self.toast = nil }
        }
    }
}

// MARK: - Progression d'apparition (animation d'ouverture / fermeture, suivie au doigt)

@MainActor
final class PresentationState: ObservableObject {
    @Published var progress: Double = 0
}
