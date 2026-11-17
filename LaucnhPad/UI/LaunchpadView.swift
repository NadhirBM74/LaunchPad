import Combine
import SwiftUI
import AppKit

// MARK: - Mise en page globale

struct RootLayout {
    let size: CGSize
    let searchCenterX: CGFloat
    let searchCenterY: CGFloat
    let gridOrigin: CGPoint
    let grid: GridMetrics
    let dotsX: CGFloat
    let dotsY: CGFloat
    let favoritesDockY: CGFloat
    let hasFavorites: Bool
    let hasWidgets: Bool
    let widgetPosition: WidgetPosition
    let widgetBannerCenterY: CGFloat

    init(size: CGSize, topInset: CGFloat, columns: Int, rows: Int, iconScale: CGFloat, showLabels: Bool, hasFavorites: Bool = false, hasWidgets: Bool = false, leftShelfWidth: CGFloat = 0, widgetPosition: WidgetPosition = .leftSide, isBannerCollapsed: Bool = false) {
        self.size = size
        self.hasFavorites = hasFavorites
        self.hasWidgets = false
        self.widgetPosition = .leftSide
        self.widgetBannerCenterY = 0

        let searchTop = max(topInset + 12, size.height * 0.035 + 10)
        searchCenterY = searchTop + 18
        searchCenterX = size.width / 2
        dotsX = size.width / 2

        let gridTop = searchTop + 36 + max(18, size.height * 0.03)
        let bottomArea = hasFavorites ? max(96, size.height * 0.13) : max(60, size.height * 0.08)
        let gridHeight = max(160, size.height - gridTop - bottomArea)

        grid = GridMetrics(size: CGSize(width: size.width, height: gridHeight), columns: columns, rows: rows,
                           iconScale: iconScale, showLabels: showLabels)
        gridOrigin = CGPoint(x: 0, y: gridTop)

        if hasFavorites {
            dotsY = gridTop + gridHeight + 14
            favoritesDockY = size.height - 36
        } else {
            dotsY = gridTop + gridHeight + bottomArea * 0.45
            favoritesDockY = 0
        }
    }
}

// MARK: - Vue racine

struct LaunchpadRootView: View {
    @ObservedObject var vm: LaunchpadViewModel
    @ObservedObject var store: LaunchpadStore
    let wallpaper: WallpaperProvider

    @AppStorage(PrefKey.columns) private var columns = 7
    @AppStorage(PrefKey.rows) private var rows = 5
    @AppStorage(PrefKey.iconScale) private var iconScale = 1.0
    @AppStorage(PrefKey.showLabels) private var showLabels = true
    @AppStorage(PrefKey.backgroundOpacity) private var backgroundOpacity = 0.35
    @AppStorage(PrefKey.backgroundStyle) private var backgroundStyle: BackgroundStyle = .liquidGlass
    @AppStorage(PrefKey.liquidGlassIntensity) private var liquidGlassIntensity = 0.85
    @AppStorage(PrefKey.showRunningIndicator) private var showRunning = true
    @AppStorage(PrefKey.showFavoritesBar) private var showFavoritesBar = true
    @AppStorage(PrefKey.tintedIcons) private var tintedIcons = false
    @AppStorage(PrefKey.tintedIconColor) private var tintedIconColor = "accent"
    @AppStorage(PrefKey.reduceMotion) private var reduceMotionPreference = false
    @ObservedObject private var widgetManager = WidgetManager.shared
    @ObservedObject private var licenseManager = LicenseManager.shared
    @ObservedObject private var locManager = LocalizationManager.shared
    @ObservedObject private var permissionManager = PermissionManager.shared
    @ObservedObject private var customIconManager = CustomIconManager.shared
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @FocusState private var searchFocused: Bool

    private var reduceMotion: Bool { reduceMotionPreference || systemReduceMotion }

    private var activeTintColor: Color? {
        guard tintedIcons && licenseManager.isPro else { return nil }
        switch tintedIconColor {
        case "accent": return Color.accentColor
        case "graphite": return Color(white: 0.8)
        case "purple": return Color(red: 0.72, green: 0.45, blue: 0.98)
        case "orange": return Color(red: 1.0, green: 0.58, blue: 0.15)
        case "mint": return Color(red: 0.25, green: 0.82, blue: 0.65)
        case "rose": return Color(red: 1.0, green: 0.35, blue: 0.55)
        case "gold": return Color(red: 0.98, green: 0.80, blue: 0.25)
        case "blue": return Color(red: 0.20, green: 0.60, blue: 1.0)
        default: return Color.accentColor
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let full = proxy.size
            let windowRect = vm.windowRect
            let rect = windowRect ?? CGRect(origin: .zero, size: full)
            ZStack(alignment: .topLeading) {
                if windowRect != nil {
                    // Mode fenêtre : un clic en dehors de la fenêtre ferme le Launchpad.
                    Color.black.opacity(0.12)
                        .contentShape(Rectangle())
                        .onTapGesture { vm.close() }
                        .frame(width: full.width, height: full.height)
                        .modifier(PresentationEffect(state: vm.presentation, style: .fade))
                }
                launchpad(size: rect.size, windowed: windowRect != nil)
                    .shadow(color: .black.opacity(windowRect != nil ? 0.45 : 0), radius: 30, y: 14)
                    .offset(x: rect.minX, y: rect.minY)
            }
            .frame(width: full.width, height: full.height, alignment: .topLeading)
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
    }

    private func launchpad(size: CGSize, windowed: Bool) -> some View {
        let hasFavorites = licenseManager.isPro && showFavoritesBar && !vm.favoriteApps.isEmpty
        let layout = RootLayout(size: size, topInset: vm.topInset, columns: min(max(columns, 3), 12),
                                rows: min(max(rows, 2), 9), iconScale: iconScale, showLabels: showLabels,
                                hasFavorites: hasFavorites)
        return ZStack(alignment: .topLeading) {
            if vm.isPanelVisible {
                LaunchpadBackground(wallpaper: wallpaper, style: backgroundStyle, dimming: backgroundOpacity, liquidGlassIntensity: liquidGlassIntensity)
                    .equatable()
                    .frame(width: size.width, height: size.height)
                    .modifier(PresentationEffect(state: vm.presentation, style: .fade))
                backgroundInteraction
                    .frame(width: size.width, height: size.height)
                content(layout)
                    .modifier(PresentationEffect(state: vm.presentation, style: .zoom))

                SettingsDimmingOverlay(chrome: vm.settingsChrome)
                    .frame(width: size.width, height: size.height)
                if let state = vm.drag {
                    if let widgetConfig = store.visibleItems.compactMap(\.widget).first(where: { $0.id == state.id }) {
                        let placed = vm.placedItem(for: state.id)
                        FloatingDragWidget(pointer: vm.pointer, config: widgetConfig, grabOffset: state.grabOffset, targetSize: placed?.frameSize)
                            .frame(width: size.width, height: size.height)
                    } else {
                        FloatingDragIcon(pointer: vm.pointer, model: tileModel(for: state.id), size: layout.grid.iconSize,
                                         grabOffset: state.grabOffset, merging: vm.mergeTargetID != nil)
                            .frame(width: size.width, height: size.height)
                    }
                }
                if let folder = vm.overlayFolder {
                    FolderOverlayView(vm: vm, store: store, folder: folder, grid: layout.grid, rootSize: size,
                                      showLabels: showLabels, showRunning: showRunning, reduceMotion: reduceMotion)
                        .frame(width: size.width, height: size.height)
                        .modifier(PresentationEffect(state: vm.presentation, style: .zoom))
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
                LaunchpadOverlays(vm: vm)
                    .frame(width: size.width, height: size.height)
                    .modifier(PresentationEffect(state: vm.presentation, style: .fade))
                if vm.showWidgetGallery {
                    WidgetGalleryModal(vm: vm, store: store, rootSize: size)
                        .frame(width: size.width, height: size.height)
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))
                }
                if let customAppID = customIconManager.activePickerAppID {
                    ZStack {
                        Color.black.opacity(0.48)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                customIconManager.activePickerAppID = nil
                            }
                        AppCustomIconPickerSheet(
                            appID: customAppID,
                            appName: store.displayName(customAppID),
                            isPresented: Binding(
                                get: { customIconManager.activePickerAppID != nil },
                                set: { if !$0 { customIconManager.activePickerAppID = nil } }
                            )
                        )
                    }
                    .frame(width: size.width, height: size.height)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    .zIndex(500)
                }
            } else {
                Color.clear
                    .frame(width: size.width, height: size.height)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: windowed ? 26 : 0, style: .continuous))
        .overlay {
            if windowed {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(
                        backgroundStyle == .liquidGlass
                            ? LinearGradient(colors: [Color.white.opacity(0.45), Color.white.opacity(0.10), Color.white.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [Color.white.opacity(0.18), Color.white.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1
                    )
                    .modifier(PresentationEffect(state: vm.presentation, style: .fade))
                    .allowsHitTesting(false)
            }
        }
        .coordinateSpace(.named(launchpadSpace))
        .onChange(of: layout.grid, initial: true) { _, grid in
            vm.metrics = grid
            vm.gridOrigin = layout.gridOrigin
        }
        .onChange(of: vm.focusToken, initial: true) { _, _ in focusSearch() }
        .onChange(of: backgroundStyle) { _, _ in wallpaper.refresh() }
    }

    private func focusSearch() {
        DispatchQueue.main.async { searchFocused = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { searchFocused = true }
    }

    // MARK: Fond cliquable (fermer, glisser pour changer de page, menu principal)

    private var backgroundInteraction: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture { vm.backgroundClicked() }
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { vm.backgroundDragChanged($0.translation.width) }
                    .onEnded { vm.backgroundDragEnded($0.translation.width, predicted: $0.predictedEndTranslation.width) }
            )
            .contextMenu { mainMenuItems }
    }

    @ViewBuilder
    private var mainMenuItems: some View {
        Button(loc("menu.settings")) { vm.onOpenSettings() }
        Button("Galerie de widgets…") { vm.showWidgetGallery = true }
        Button("Nouveau dossier…") {
            let folderID = store.createCustomFolder(name: "Nouveau dossier", style: .frostedGlass)
            vm.openFolder(folderID)
        }
        Button(loc("menu.reorganize")) { vm.requestReorganize() }
        Button(loc("menu.refresh")) { store.refresh() }
        Divider()
        Button("\(loc("menu.add_web"))\(licenseManager.isPro ? "" : " (Pro)")") { vm.requestAddWebBookmark() }
        Button("\(loc("menu.add_shortcut"))\(licenseManager.isPro ? "" : " (Pro)")") { vm.requestAddShortcut() }
        Divider()
        Button(loc("menu.quit")) { NSApp.terminate(nil) }
    }

    // MARK: Contenu

    private func content(_ layout: RootLayout) -> some View {
        ZStack(alignment: .topLeading) {
            // Mode édition : Bouton "+" façon iPhone en haut à gauche
            if (vm.editing || vm.optionHeld) && !vm.isSearching {
                Button {
                    vm.showWidgetGallery = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                        Text(loc("widget.add_widget_short"))
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .liquidGlassCapsule(interactive: true, intensity: liquidGlassIntensity)
                    .shadow(color: LiquidGlassStyle.shadowColor, radius: 8, y: 3)
                }
                .buttonStyle(.plain)
                .position(x: max(60, layout.size.width * 0.06), y: layout.searchCenterY)
                .transition(.opacity)

                // Bouton "Terminé" en haut à droite
                Button {
                    vm.setEditing(false)
                } label: {
                    Text(loc("common.done"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .liquidGlassCapsule(interactive: true, intensity: liquidGlassIntensity)
                        .shadow(color: LiquidGlassStyle.shadowColor, radius: 8, y: 3)
                }
                .buttonStyle(.plain)
                .position(x: layout.size.width - max(60, layout.size.width * 0.06), y: layout.searchCenterY)
                .transition(.opacity)
            }
            searchBar
                .position(x: layout.searchCenterX, y: layout.searchCenterY)
            if !permissionManager.isAccessibilityGranted && !permissionManager.hasDismissedBanner && !vm.isSearching {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.orange)

                    Text(loc("permission.banner.desc"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)

                    Button {
                        permissionManager.promptUserForAccessibility()
                    } label: {
                        Text(loc("general.authorize_button"))
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2.5)
                            .background(Color.white)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            permissionManager.hasDismissedBanner = true
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .liquidGlassCapsule(interactive: true)
                .shadow(color: LiquidGlassStyle.shadowColor, radius: 8, y: 3)
                .position(x: layout.searchCenterX, y: layout.searchCenterY + 30)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
            PagesLayer(
                vm: vm,
                store: store,
                metrics: layout.grid,
                showLabels: showLabels,
                showRunning: showRunning,
                reduceMotion: reduceMotion,
                tint: activeTintColor
            )
                .offset(x: layout.gridOrigin.x, y: layout.gridOrigin.y)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: iconScale)
            if vm.displayItems.isEmpty {
                emptyState
                    .position(x: layout.gridOrigin.x + layout.grid.size.width / 2, y: layout.gridOrigin.y + layout.grid.size.height / 2)
            }
            pageDots
                .position(x: layout.dotsX, y: layout.dotsY)
            if layout.hasFavorites {
                FavoritesDockView(vm: vm, store: store)
                    .position(x: layout.dotsX, y: layout.favoritesDockY)
            }
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
    }

    // Barre de recherche façon LaunchOS : capsule en Liquid Glass blanc
    private var searchBar: some View {
        let typing = !vm.query.isEmpty
        return HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
            ZStack(alignment: .leading) {
                if !typing {
                    Text(loc("grid.search_placeholder"))
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .allowsHitTesting(false)
                }
                TextField("", text: $vm.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .tint(.white)
                    .focused($searchFocused)
            }
            if typing {
                Button { vm.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.65))
                .transition(.opacity)
            }
            SearchMenuButton(foreground: .white.opacity(0.85),
                             onAddWidget: { vm.showWidgetGallery = true },
                             onNewFolder: {
                                 let folderID = store.createCustomFolder(name: "Nouveau dossier", style: .frostedGlass)
                                 vm.openFolder(folderID)
                             },
                             onSettings: { vm.onOpenSettings() },
                             onReorganize: { vm.requestReorganize() },
                             onRefresh: { store.refresh() })
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(width: 340, height: 38)
        .liquidGlass(
            in: Capsule(),
            interactive: true,
            tint: nil,
            prominence: .clear,
            intensity: liquidGlassIntensity
        )
        .contentShape(Capsule())
        .onTapGesture { searchFocused = true }
        .shadow(color: LiquidGlassStyle.shadowColor, radius: 10, y: 5)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: typing)
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            if store.isLoading {
                ProgressView().controlSize(.large)
                Text(loc("grid.loading")).foregroundStyle(.white.opacity(0.75))
            } else {
                Image(systemName: vm.isSearching ? "magnifyingglass" : "square.grid.3x3")
                    .font(.system(size: 38)).foregroundStyle(.white.opacity(0.45))
                Text(vm.isSearching ? loc("grid.no_results", vm.query) : loc("grid.loading")).foregroundStyle(.white.opacity(0.75))
            }
        }
    }

    private var pageDots: some View {
        HStack(spacing: 2) {
            ForEach(0..<vm.pageCount, id: \.self) { index in
                Circle()
                    .fill(Color.white.opacity(index == vm.page ? 0.95 : 0.35))
                    .frame(width: 7.5, height: 7.5)
                    .shadow(color: backgroundStyle == .liquidGlass && index == vm.page ? Color.white.opacity(0.65) : Color.clear, radius: 4)
                    .padding(5)
                    .contentShape(Rectangle())
                    .onTapGesture { vm.setPage(index) }
            }
        }
        .opacity(vm.pageCount > 1 ? 1 : 0)
    }

    private func isRemovable(_ item: LayoutItem) -> Bool {
        if item.isWidget { return true }
        guard let id = item.appID else { return false }
        if id.hasPrefix("web:") || id.hasPrefix("shortcut:") { return true }
        return store.catalog[id]?.isRemovable == true
    }

    private func tileModel(for id: String) -> TileModel {
        if let item = vm.displayItems.first(where: { $0.id == id }) ?? store.visibleItems.first(where: { $0.id == id }) {
            return tileModel(for: item)
        }
        return tileModel(for: .app(id))
    }

    private func tileModel(for item: LayoutItem) -> TileModel {
        var model = TileModel.make(item, store: store, showRunning: showRunning)
        model.tintColor = activeTintColor
        return model
    }
}

// MARK: - Bande des pages (isolée : seul ce calque observe le décalage du trackpad)

/// Un seul ForEach pour toutes les pages : l'identité des icônes reste stable pendant un glisser.
/// Le décalage horizontal vit dans `PageScroll` : suivre le doigt à 120 Hz ne reconstruit
/// ni le fond, ni la recherche, ni la vue racine — uniquement cette bande d'icônes.
struct PagesLayer: View {
    @ObservedObject var vm: LaunchpadViewModel
    @ObservedObject var store: LaunchpadStore
    @ObservedObject private var pageScroll: PageScroll
    let metrics: GridMetrics
    let showLabels: Bool
    let showRunning: Bool
    let reduceMotion: Bool
    let tint: Color?

    init(vm: LaunchpadViewModel, store: LaunchpadStore, metrics: GridMetrics,
         showLabels: Bool, showRunning: Bool, reduceMotion: Bool, tint: Color?) {
        self.vm = vm
        self.store = store
        self._pageScroll = ObservedObject(wrappedValue: vm.pageScroll)
        self.metrics = metrics
        self.showLabels = showLabels
        self.showRunning = showRunning
        self.reduceMotion = reduceMotion
        self.tint = tint
    }

    var body: some View {
        let m = metrics
        let placed = vm.placedDisplayItems(metrics: m)
        let width = m.size.width
        let offset = pageScroll.offset
        let draggingID = vm.drag?.id
        let currentPos = width > 0 ? (-offset / width) : CGFloat(vm.page)
        let fromPage = min(vm.page, vm.lastPage)
        let toPage = max(vm.page, vm.lastPage)
        let isSettled = abs(currentPos - CGFloat(vm.page)) < 0.005 && vm.page == vm.lastPage && draggingID == nil
        let minPage = isSettled ? vm.page : (draggingID != nil ? min(fromPage - 1, Int(floor(currentPos)) - 1) : min(fromPage, Int(floor(currentPos))))
        let maxPage = isSettled ? vm.page : (draggingID != nil ? max(toPage + 1, Int(ceil(currentPos)) + 1) : max(toPage, Int(ceil(currentPos))))
        let visiblePlaced = placed.filter { entry in
            (entry.page >= minPage && entry.page <= maxPage) || entry.id == draggingID
        }
        _ = store.iconsVersion
        return ZStack(alignment: .topLeading) {
            ForEach(visiblePlaced) { entry in
                tile(entry, metrics: m)
                    .position(x: CGFloat(entry.page) * width + entry.center.x, y: entry.center.y)
            }
        }
        .frame(width: width, height: m.size.height, alignment: .topLeading)
        .offset(x: offset)
    }

    private func isRemovable(_ item: LayoutItem) -> Bool {
        if item.isWidget { return true }
        guard let id = item.appID else { return false }
        if id.hasPrefix("web:") || id.hasPrefix("shortcut:") { return true }
        return store.catalog[id]?.isRemovable == true
    }

    private func tileModel(for item: LayoutItem) -> TileModel {
        var model = TileModel.make(item, store: store, showRunning: showRunning)
        model.tintColor = tint
        return model
    }

    @ViewBuilder
    private func tile(_ entry: PlacedItem, metrics m: GridMetrics) -> some View {
        if entry.item.isWidget {
            widgetGridTile(entry, metrics: m)
        } else {
            let item = entry.item
            AppTileView(
                model: tileModel(for: item),
                iconSize: m.iconSize,
                labelWidth: m.cellWidth - 8,
                showLabel: showLabels,
                jiggle: (vm.editing || vm.optionHeld) && !vm.isSearching && !reduceMotion,
                showDelete: vm.showsDeleteBadges && isRemovable(item),
                isSelected: vm.selection.contains(item.id),
                isKeyboardFocused: vm.keyboardIndex == entry.index,
                isMergeTarget: vm.mergeTargetID == item.id,
                isPlaceholder: vm.drag?.id == item.id,
                onDelete: { vm.requestUninstall(for: item) }
            )
            .equatable()
            .frame(width: m.cellWidth, height: m.tileHeight)
            .modifier(PointerTracking(item: item, source: .grid, vm: vm))
            .contextMenu { ItemContextMenu(vm: vm, store: store, item: item, folderID: nil) }
        }
    }

    @ViewBuilder
    private func widgetGridTile(_ entry: PlacedItem, metrics m: GridMetrics) -> some View {
        if case .widget(let config) = entry.item {
            let isBeingDragged = vm.drag?.id == config.id
            let isEditing = (vm.editing || vm.optionHeld) && !vm.isSearching
            let displayW = entry.frameSize.width
            let displayH = entry.frameSize.height

            ZStack(alignment: .topTrailing) {
                if isBeingDragged {
                    RoundedRectangle(cornerRadius: WidgetManager.shared.cornerRadius, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: WidgetManager.shared.cornerRadius, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                        )
                        .frame(width: displayW, height: displayH)
                } else {
                    WidgetHostView(config: config, targetSize: entry.frameSize)
                        .equatable()
                        .frame(width: displayW, height: displayH)
                        .contentShape(Rectangle())
                        .allowsHitTesting(!isEditing)
                }

                // Badge de suppression en mode édition
                if isEditing && !isBeingDragged {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                            store.removeWidget(config.kind)
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(Color.black.opacity(0.85))
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.white.opacity(0.95)))
                            .shadow(color: .black.opacity(0.35), radius: 2.5, y: 1.2)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .offset(x: 6, y: -6)
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(200)
                }
            }
            .modifier(JiggleEffect(active: isEditing && !isBeingDragged && !reduceMotion, phase: Double(entry.index) * 0.2, maxAngle: 0.32))
            // Le suivi du pointeur vit DERRIÈRE le widget : ainsi les boutons et la barre de lecture
            // du widget reçoivent leurs clics (un geste posé sur le conteneur les masquait).
            .background(
                Color.clear
                    .contentShape(Rectangle())
                    .modifier(PointerTracking(item: entry.item, source: .grid, vm: vm))
            )
            .contextMenu {
                ItemContextMenu(vm: vm, store: store, item: entry.item, folderID: nil)
            }
        }
    }
}

// MARK: - Voile des réglages (isolé : l'animation ne redessine pas la grille)

struct SettingsDimmingOverlay: View {
    @ObservedObject var chrome: SettingsChrome

    var body: some View {
        let intensity = chrome.intensity
        ZStack {
            if intensity > 0.001 {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(intensity * 0.45)
                Color.black
                    .opacity(0.28 * intensity)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Animation d'ouverture (comme le Launchpad de macOS)

/// Applique la progression d'apparition. Seul ce modificateur observe `PresentationState` :
/// suivre le doigt à 120 Hz ne recalcule ni la grille ni les icônes.
struct PresentationEffect: ViewModifier {
    enum Style { case fade, zoom }
    @ObservedObject var state: PresentationState
    let style: Style

    func body(content: Content) -> some View {
        let progress = state.progress
        switch style {
        case .fade:
            content.opacity(progress)
        case .zoom:
            // Les icônes arrivent de plus près (zoom arrière) en apparaissant, puis se posent à leur taille.
            content
                .opacity(min(1, progress * 1.25))
                .scaleEffect(1 + 0.16 * (1 - progress))
        }
    }
}

// MARK: - Bouton ⋯ de la barre de recherche (comme LaunchOS) : clic = réglages, clic droit = menu principal

struct SearchMenuButton: View {
    var foreground: Color = .white.opacity(0.78)
    var onAddWidget: (() -> Void)? = nil
    var onNewFolder: (() -> Void)? = nil
    let onSettings: () -> Void
    let onReorganize: () -> Void
    let onRefresh: () -> Void
    @State private var hoveringWidget = false
    @State private var hoveringSettings = false

    var body: some View {
        HStack(spacing: 4) {
            if let onAddWidget {
                Button(action: onAddWidget) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.square.on.square")
                            .font(.system(size: 12.5, weight: .semibold))
                        Text("Widgets")
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .foregroundStyle(foreground.opacity(hoveringWidget ? 1.0 : 0.88))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(hoveringWidget ? 0.18 : 0.10), in: Capsule())
                }
                .buttonStyle(.plain)
                .onHover { hoveringWidget = $0 }
                .help("Ajouter et personnaliser des widgets")
                .accessibilityLabel("Ouvrir la galerie de widgets")
            }

            Button(action: onSettings) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(foreground.opacity(hoveringSettings ? 1.0 : 0.85))
                    .frame(width: 26, height: 26)
                    .background(Color.white.opacity(hoveringSettings ? 0.16 : 0.0), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { hoveringSettings = $0 }
            .animation(.easeOut(duration: 0.12), value: hoveringSettings)
            .help("Ouvrir les réglages de LaunchPad")
            .accessibilityLabel("Réglages")
            .contextMenu {
                if let onAddWidget {
                    Button("Ajouter un widget…", action: onAddWidget)
                }
                if let onNewFolder {
                    Button("Créer un nouveau dossier…", action: onNewFolder)
                }
                Divider()
                Button(loc("menu.settings"), action: onSettings)
                Button(loc("menu.reorganize"), action: onReorganize)
                Button(loc("menu.refresh"), action: onRefresh)
                Divider()
                Button(loc("menu.quit")) { NSApp.terminate(nil) }
            }
        }
    }
}

// MARK: - Modèle d'icône

struct TileModel: Equatable {
    var title: String
    var icon: NSImage?
    var folderIcons: [NSImage]?
    var folderStyle: FolderVisualStyle = .frostedGlass
    var folderColorHex: String? = nil
    var folderSymbol: String? = nil
    var isRunning: Bool
    var isLocked: Bool = false
    var tintColor: Color? = nil

    nonisolated static func == (lhs: TileModel, rhs: TileModel) -> Bool {
        guard lhs.title == rhs.title,
              lhs.isRunning == rhs.isRunning,
              lhs.isLocked == rhs.isLocked,
              lhs.tintColor == rhs.tintColor,
              lhs.folderStyle == rhs.folderStyle,
              lhs.folderColorHex == rhs.folderColorHex,
              lhs.folderSymbol == rhs.folderSymbol,
              lhs.icon === rhs.icon else { return false }
        switch (lhs.folderIcons, rhs.folderIcons) {
        case (nil, nil): return true
        case let (a?, b?): return a.count == b.count && zip(a, b).allSatisfy { $0 === $1 }
        default: return false
        }
    }

    @MainActor
    static func make(_ item: LayoutItem, store: LaunchpadStore, showRunning: Bool) -> TileModel {
        switch item {
        case .app(let id):
            let running = showRunning && (store.catalog[id].map(store.isRunning) ?? false)
            return TileModel(title: store.displayName(id), icon: IconCache.shared.icon(for: id), folderIcons: nil, isRunning: running, isLocked: false)
        case .folder(let folder):
            return TileModel(
                title: folder.name,
                icon: nil,
                folderIcons: folder.apps.prefix(9).map { IconCache.shared.icon(for: $0) },
                folderStyle: folder.style,
                folderColorHex: folder.colorHex,
                folderSymbol: folder.iconSymbol,
                isRunning: false,
                isLocked: folder.isLocked
            )
        case .widget(let config):
            return TileModel(title: config.kind.title, icon: nil, folderIcons: nil, isRunning: false, isLocked: false)
        }
    }
}

// MARK: - Suivi du pointeur (détecte aussi les gestes annulés par SwiftUI)

struct PointerTracking: ViewModifier {
    let item: LayoutItem
    let source: DragSource
    let vm: LaunchpadViewModel
    @GestureState private var active = false

    func body(content: Content) -> some View {
        content
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(launchpadSpace))
                    .updating($active) { _, state, _ in state = true }
                    .onChanged { vm.pointerChanged(item, source: source, value: $0) }
                    .onEnded { vm.pointerEnded(item, source: source, value: $0) }
            )
            .onChange(of: active) { _, isActive in
                if !isActive { vm.pointerCancelled(item.id) }
            }
    }
}

// MARK: - Icône

struct AppTileView: View, Equatable {
    let model: TileModel
    let iconSize: CGFloat
    let labelWidth: CGFloat
    let showLabel: Bool
    var jiggle = false
    var showDelete = false
    var isSelected = false
    var isKeyboardFocused = false
    var isMergeTarget = false
    var isPlaceholder = false
    var onDelete: () -> Void = {}

    @State private var hovering = false
    @State private var phase = Double.random(in: 0..<1)

    /// Marge transparente des icônes macOS : la forme visible occupe ~80 % du cadre.
    static let visibleInset: CGFloat = 0.1

    /// Performance : SwiftUI ne recalcule la tuile que si ses données changent (pas à chaque image du défilement).
    nonisolated static func == (lhs: AppTileView, rhs: AppTileView) -> Bool {
        lhs.model == rhs.model && lhs.iconSize == rhs.iconSize && lhs.labelWidth == rhs.labelWidth
            && lhs.showLabel == rhs.showLabel && lhs.jiggle == rhs.jiggle && lhs.showDelete == rhs.showDelete
            && lhs.isSelected == rhs.isSelected && lhs.isKeyboardFocused == rhs.isKeyboardFocused
            && lhs.isMergeTarget == rhs.isMergeTarget && lhs.isPlaceholder == rhs.isPlaceholder
    }

    private var iconShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: iconSize * 0.2, style: .continuous)
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topLeading) {
                if isMergeTarget, model.folderIcons == nil {
                    // Aperçu du futur dossier, comme sur iPhone.
                    RoundedRectangle(cornerRadius: iconSize * 0.27, style: .continuous)
                        .fill(Color.white.opacity(0.3))
                        .overlay(RoundedRectangle(cornerRadius: iconSize * 0.27, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
                        .frame(width: iconSize * 1.24, height: iconSize * 1.24)
                        .frame(width: iconSize, height: iconSize)
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                }
                IconImage(model: model, size: iconSize)
                    .background { highlight }
                    .scaleEffect(isMergeTarget ? (model.folderIcons == nil ? 0.92 : 1.14) : (hovering && !jiggle ? 1.05 : 1))
            }
            .frame(width: iconSize, height: iconSize)
            // Zone cliquable = forme visible de l'icône uniquement (pas les marges transparentes ni la case).
            .contentShape(iconShape.inset(by: iconSize * Self.visibleInset))
            .onHover { hovering = $0 }
            .overlay(alignment: .topLeading) {
                if showDelete {
                    // Collée au coin arrondi visible de l'icône (pas au cadre transparent).
                    let center = iconSize * 0.15
                    Button(action: onDelete) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(Color.black.opacity(0.75))
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.white.opacity(0.95)))
                            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .offset(x: center - 11, y: center - 11)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .overlay(alignment: .bottom) {
                if model.isRunning {
                    Circle().fill(Color.white.opacity(0.85)).frame(width: 4, height: 4).offset(y: 5)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if model.isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: max(8, iconSize * 0.15), weight: .bold))
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(Circle().fill(Color.black.opacity(0.72)))
                        .offset(x: -iconSize * 0.04, y: -iconSize * 0.04)
                        .allowsHitTesting(false)
                }
            }
            if showLabel {
                Text(model.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .shadow(color: .black.opacity(0.88), radius: 0.6, y: 0.5)
                    .contentShape(Rectangle())
                    .frame(width: max(20, labelWidth), height: 16)
            }
        }
        .modifier(JiggleEffect(active: jiggle, phase: phase))
        .opacity(isPlaceholder ? 0 : 1)
        .animation(.easeOut(duration: 0.14), value: hovering)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isMergeTarget)
        .animation(.easeOut(duration: 0.15), value: showDelete)
    }

    @ViewBuilder
    private var highlight: some View {
        if isSelected || isKeyboardFocused {
            // Ajustée à la forme visible de l'icône (avant : un grand carré décalé).
            RoundedRectangle(cornerRadius: iconSize * 0.24, style: .continuous)
                .fill(Color.white.opacity(isSelected ? 0.28 : 0.22))
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: iconSize * 0.24, style: .continuous).stroke(Color.accentColor, lineWidth: 2)
                    }
                }
                .padding(iconSize * 0.02)
                .allowsHitTesting(false)
        }
    }
}

/// Tremblement des icônes : animation répétée gérée par le moteur d'animation
/// (avant : une TimelineView à 60 i/s par icône qui recalculait chaque tuile).
struct JiggleEffect: ViewModifier {
    let active: Bool
    let phase: Double
    var maxAngle: Double = 1.4
    @State private var tilted = false

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(active ? (tilted ? maxAngle : -maxAngle) : 0))
            .onAppear { if active { start() } }
            .onChange(of: active) { _, isActive in
                if isActive { start() } else { stop() }
            }
    }

    private func start() {
        tilted = false
        withAnimation(.easeInOut(duration: 0.13).repeatForever(autoreverses: true).delay(phase * 0.13)) {
            tilted = true
        }
    }

    private func stop() {
        withAnimation(.easeOut(duration: 0.12)) { tilted = false }
    }
}

struct IconImage: View {
    let model: TileModel
    let size: CGFloat

    var body: some View {
        if let icons = model.folderIcons {
            PremiumFolderIconView(
                icons: icons,
                size: size,
                style: model.folderStyle,
                customColorHex: model.folderColorHex,
                customSymbol: model.folderSymbol
            )
        } else if let icon = model.icon {
            // L'ombre et le style (Original, Sombre, Clair, Teinté, Verre, Monochrome) sont déjà pré-rendus en 512×512 Retina dans IconCache.
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(Color.white.opacity(0.15))
                .frame(width: size, height: size)
        }
    }
}

struct FolderIconView: View {
    let icons: [NSImage]
    let size: CGFloat

    var body: some View {
        PremiumFolderIconView(icons: icons, size: size)
    }
}

struct FloatingDragIcon: View {
    @ObservedObject var pointer: DragPointer
    let model: TileModel
    let size: CGFloat
    let grabOffset: CGSize
    var merging = false

    var body: some View {
        IconImage(model: model, size: size)
            .scaleEffect(merging ? 0.86 : 1.1)
            .shadow(color: .black.opacity(0.35), radius: 14, y: 10)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: merging)
            .position(x: pointer.location.x - grabOffset.width, y: pointer.location.y - grabOffset.height)
            .allowsHitTesting(false)
    }
}

struct FloatingDragWidget: View {
    @ObservedObject var pointer: DragPointer
    let config: CustomWidgetConfig
    let grabOffset: CGSize
    var targetSize: CGSize? = nil

    var body: some View {
        WidgetHostView(config: config, targetSize: targetSize)
            .scaleEffect(1.05)
            .shadow(color: .black.opacity(0.45), radius: 20, y: 12)
            .position(x: pointer.location.x - grabOffset.width, y: pointer.location.y - grabOffset.height)
            .allowsHitTesting(false)
    }
}

// MARK: - Menu contextuel

struct ItemContextMenu: View {
    let vm: LaunchpadViewModel
    let store: LaunchpadStore
    let item: LayoutItem
    let folderID: String?
    @ObservedObject private var licenseManager = LicenseManager.shared
    @ObservedObject private var locManager = LocalizationManager.shared

    var body: some View {
        switch item {
        case .app(let id):
            if let app = store.catalog[id] {
                Button(loc("menu.open")) { vm.activate(item) }
                if store.isRunning(app) {
                    Button(loc("menu.quit_app")) { AppActions.quit(app) }
                    Button(loc("menu.force_quit")) { vm.requestForceQuit(app) }
                }
                Divider()
                Button(vm.isFavorite(id) ? loc("menu.remove_from_favorites") : "\(loc("menu.pin_to_favorites"))\(licenseManager.isPro ? "" : " (Pro)")") {
                    vm.toggleFavorite(id)
                }
                if !id.hasPrefix("web:") && !id.hasPrefix("shortcut:") {
                    Button(loc("menu.show_in_finder")) { vm.reveal(app) }
                    Button(loc("menu.get_info")) { vm.showInfo(app) }
                    Button(loc("menu.add_to_dock")) { vm.addToDock(app) }
                }
                Divider()
                Button("Personnaliser l'icône…") {
                    CustomIconManager.shared.activePickerAppID = id
                }
                if CustomIconManager.shared.hasOverride(for: id) {
                    Button("Rétablir l'icône d'origine") {
                        CustomIconManager.shared.removeOverride(for: id)
                    }
                }
                Button("\(loc("dialog.rename"))…") { vm.requestRename(id: id, isFolder: false) }
                if let folderID {
                    Button(loc("menu.remove_from_folder")) { vm.removeFromFolder(id, folderID: folderID) }
                }
                if vm.selection.count > 1, vm.selection.contains(id) {
                    Button(loc("menu.hide_count", vm.selection.count)) { vm.hide(Array(vm.selection)) }
                    Button(loc("menu.create_folder_selection")) { vm.makeFolderFromSelection() }
                } else {
                    Button(loc("menu.hide")) { vm.hide([id]) }
                }
                if id.hasPrefix("web:") || id.hasPrefix("shortcut:") {
                    Divider()
                    Button(loc("menu.delete_from_launchpad"), role: .destructive) { vm.requestDeleteCustomTile(id: id, title: app.name) }
                } else if app.isRemovable {
                    Divider()
                    Button("\(loc("menu.uninstall"))\(licenseManager.isPro ? "" : " (Pro)")", role: .destructive) { vm.requestUninstall(app) }
                }
            }
        case .folder(let folder):
            Button(loc("menu.open_folder")) { vm.openFolder(folder.id) }
            Menu("Style du dossier") {
                ForEach(FolderVisualStyle.allCases) { styleOpt in
                    Button("\(folder.style == styleOpt ? "✓ " : "")\(styleOpt.title)") {
                        store.updateFolderCustomization(
                            folder.id,
                            style: styleOpt,
                            colorHex: folder.colorHex,
                            iconSymbol: folder.iconSymbol
                        )
                    }
                }
            }
            Menu("Couleur du dossier") {
                ForEach([
                    ("#E5B892", "Sable Doré"),
                    ("#FF2442", "Rouge Carmin"),
                    ("#D8DCE2", "Argent"),
                    ("#141416", "Noir Onyx"),
                    ("#0A84FF", "Bleu Apple"),
                    ("#30D158", "Vert Émeraude"),
                    ("#BF5AF2", "Violet"),
                    ("#FF9F0A", "Ambre")
                ], id: \.0) { hex, label in
                    Button("\((folder.colorHex?.uppercased() == hex) ? "✓ " : "")\(label)") {
                        store.updateFolderCustomization(
                            folder.id,
                            style: folder.style,
                            colorHex: hex,
                            iconSymbol: folder.iconSymbol
                        )
                    }
                }
            }
            Button(folder.isLocked ? loc("menu.unprotect_touchid") : "\(loc("menu.protect_touchid"))\(licenseManager.isPro ? "" : " (Pro)")") {
                vm.toggleFolderLock(folder)
            }
            Button("\(loc("dialog.rename"))…") { vm.requestRename(id: folder.id, isFolder: true) }
            Button(loc("menu.dissolve_folder")) { vm.ungroup(folder.id) }
            Divider()
            Button(loc("menu.hide_folder")) { vm.hide([folder.id]) }
        case .widget(let config):
            Text(config.kind.title)
                .font(.headline)
            Divider()
            Menu(loc("widget.menu.change_size")) {
                ForEach(config.kind.allowedSizes) { size in
                    let isCurrent = (size == config.size)
                    Button("\(isCurrent ? "✓ " : "")\(size.title)") {
                        let currentPage = vm.page
                        let success = store.updateWidgetSize(config.id, to: size, columns: vm.columns, rows: vm.rows)
                        if success {
                            if let placed = vm.placedItem(for: config.id), placed.page != vm.page {
                                vm.setPage(placed.page)
                            } else {
                                vm.setPage(currentPage)
                            }
                        } else {
                            vm.showToast(loc("widget.resize_failed"))
                        }
                    }
                }
            }

            if config.kind == .vinylPlayer || config.kind == .mediaWide {
                Menu("Style de lecteur musical") {
                    ForEach(MusicWidgetStyle.allCases) { mStyle in
                        Button("\(config.musicStyle == mStyle ? "✓ " : "")\(mStyle.title)") {
                            var updated = config
                            updated.musicStyle = mStyle
                            WidgetManager.shared.updateMusicStyle(for: config.kind, style: mStyle)
                            store.updateWidgetConfig(updated)
                        }
                    }
                }
            } else if config.kind == .weather {
                Menu("Thème météo (18 thèmes)") {
                    ForEach(WeatherWidgetTheme.allCases) { wTheme in
                        Button("\(config.weatherTheme == wTheme ? "✓ " : "")\(wTheme.title)") {
                            var updated = config
                            updated.weatherTheme = wTheme
                            WidgetManager.shared.updateWeatherTheme(wTheme)
                            store.updateWidgetConfig(updated)
                        }
                    }
                }
            } else if config.kind == .calendar {
                Menu("Style de calendrier") {
                    ForEach(CalendarWidgetStyle.allCases) { cStyle in
                        Button("\(config.calendarStyle == cStyle ? "✓ " : "")\(cStyle.title)") {
                            var updated = config
                            updated.calendarStyle = cStyle
                            WidgetManager.shared.updateCalendarStyle(cStyle)
                            store.updateWidgetConfig(updated)
                        }
                    }
                }
            } else if config.kind == .clock {
                Menu("Design de l'horloge (15 styles)") {
                    ForEach(ClockWidgetStyle.allCases) { clkStyle in
                        Button("\(config.clockStyle == clkStyle ? "✓ " : "")\(clkStyle.title)") {
                            var updated = config
                            updated.clockStyle = clkStyle
                            WidgetManager.shared.updateClockStyle(clkStyle)
                            store.updateWidgetConfig(updated)
                        }
                    }
                }
            }

            Button("Réinitialiser ce widget") {
                WidgetManager.shared.resetWidget(config.kind)
                if let def = WidgetManager.shared.config(for: config.kind) {
                    var updated = def
                    updated.id = config.id
                    updated.size = config.size
                    updated.isEnabled = true
                    store.updateWidgetConfig(updated)
                }
            }

            Divider()
            Button(loc("widget.menu.remove"), role: .destructive) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                    store.removeWidget(config.kind)
                }
            }
        }
    }
}

// MARK: - Dossier ouvert (Inspiré de la Photo de Référence 4 + Personnalisation Complète)

struct FolderOverlayView: View {
    @ObservedObject var vm: LaunchpadViewModel
    @ObservedObject var store: LaunchpadStore
    let folder: FolderData
    let grid: GridMetrics
    let rootSize: CGSize
    let showLabels: Bool
    let showRunning: Bool
    let reduceMotion: Bool

    @State private var title = ""
    @State private var isShowingCustomizer = false
    @State private var isShowingAppPicker = false
    @FocusState private var titleFocused: Bool
    @AppStorage(PrefKey.backgroundStyle) private var theme: BackgroundStyle = .liquidGlass

    /// L'app sortie du dossier reste rendue (invisible) pour ne pas interrompre le geste en cours.
    private var appsToRender: [String] {
        var apps = folder.apps
        if let state = vm.drag, state.detached, state.source == .folder(folder.id), !apps.contains(state.id) {
            apps.append(state.id)
        }
        return apps
    }

    var body: some View {
        let fm = FolderMetrics.make(rootSize: rootSize, grid: grid, count: max(folder.apps.count, 3))
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.32)
                .contentShape(Rectangle())
                .onTapGesture { vm.closeFolder() }

            if theme == .liquidGlass {
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .liquidGlassCard(cornerRadius: 36, interactive: false, borderLineWidth: 1.2)
                    .shadow(color: .black.opacity(0.45), radius: 36, x: 0, y: 18)
                    .shadow(color: .black.opacity(0.20), radius: 6, x: 0, y: 3)
                    .frame(width: fm.panelRect.width, height: fm.panelRect.height)
                    .contentShape(Rectangle())
                    .onTapGesture { titleFocused = false }
                    .position(x: fm.panelRect.midX, y: fm.panelRect.midY)
            } else {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(theme == .dark ? Color.black.opacity(0.55) : Color.white.opacity(0.10))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous).stroke(Color.white.opacity(0.22), lineWidth: 1.0))
                    .frame(width: fm.panelRect.width, height: fm.panelRect.height)
                    .contentShape(Rectangle())
                    .onTapGesture { titleFocused = false }
                    .position(x: fm.panelRect.midX, y: fm.panelRect.midY)
            }

            // En-tête du dossier : Titre éditable + Boutons Personnaliser (pinceau) & Ajouter des apps (+)
            HStack(spacing: 10) {
                Button {
                    withAnimation(AppleDesignSystem.Springs.snappy) {
                        isShowingCustomizer.toggle()
                        if isShowingCustomizer { isShowingAppPicker = false }
                    }
                } label: {
                    Image(systemName: "paintbrush.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isShowingCustomizer ? .black : .white.opacity(0.85))
                        .frame(width: 28, height: 28)
                        .background(isShowingCustomizer ? Color.white : Color.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Personnaliser le style, la couleur et l'icône du dossier")

                Spacer(minLength: 4)

                HStack(spacing: 8) {
                    if folder.isLocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white.opacity(0.85))
                            .help("Dossier protégé par Touch ID")
                    }
                    TextField("Nom du dossier", text: $title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 22, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .focused($titleFocused)
                        .onSubmit { commitTitle() }
                }

                Spacer(minLength: 4)

                Button {
                    withAnimation(AppleDesignSystem.Springs.snappy) {
                        isShowingAppPicker.toggle()
                        if isShowingAppPicker { isShowingCustomizer = false }
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(isShowingAppPicker ? .black : .white.opacity(0.85))
                        .frame(width: 28, height: 28)
                        .background(isShowingAppPicker ? Color.white : Color.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Ajouter ou retirer des applications de ce dossier")
            }
            .padding(.horizontal, 24)
            .frame(width: fm.panelRect.width)
            .position(x: fm.panelRect.midX, y: fm.panelRect.minY + FolderMetrics.header / 2)

            if appsToRender.isEmpty {
                VStack(spacing: 10) {
                    PremiumFolderIconView(
                        icons: [],
                        size: 68,
                        style: folder.style,
                        customColorHex: folder.colorHex,
                        customSymbol: folder.iconSymbol
                    )
                    Text("Ce dossier est vide")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                    Button {
                        withAnimation(AppleDesignSystem.Springs.snappy) {
                            isShowingAppPicker = true
                        }
                    } label: {
                        Label("Ajouter des applications", systemImage: "plus.circle.fill")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Color.white, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .frame(width: fm.contentRect.width, height: fm.contentHeight)
                .position(x: fm.contentRect.midX, y: fm.contentRect.midY)
            } else {
                tiles(fm)
                    .frame(width: fm.contentRect.width, height: fm.contentHeight)
                    .position(x: fm.contentRect.midX, y: fm.contentRect.midY)
            }

            if isShowingCustomizer {
                FolderCustomizationBarView(
                    folder: folder,
                    store: store,
                    isShowingCustomizer: $isShowingCustomizer,
                    isShowingAppPicker: $isShowingAppPicker
                )
                .frame(width: min(fm.panelRect.width - 28, 560))
                .position(x: fm.panelRect.midX, y: max(110, fm.panelRect.minY - 76))
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            if isShowingAppPicker {
                FolderAppPickerSheet(
                    folder: folder,
                    store: store,
                    isPresented: $isShowingAppPicker
                )
                .frame(width: min(fm.panelRect.width - 24, 540))
                .position(x: fm.panelRect.midX, y: fm.panelRect.midY)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .zIndex(50)
            }
        }
        .opacity(vm.folderFaded ? 0 : 1)
        .onAppear {
            title = folder.name
            if vm.consumeNewFolder(folder.id) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { titleFocused = true }
            }
        }
        .onChange(of: folder.name) { _, name in if !titleFocused { title = name } }
        .onChange(of: fm, initial: true) { _, metrics in vm.folderMetrics = metrics }
        .onChange(of: titleFocused) { _, focused in
            vm.textInputActive = focused
            if !focused { commitTitle() }
        }
    }

    @ViewBuilder
    private func tiles(_ fm: FolderMetrics) -> some View {
        let grid = ZStack(alignment: .topLeading) {
            ForEach(Array(appsToRender.enumerated()), id: \.element) { index, id in
                let center = fm.center(ofSlot: index)
                let item = LayoutItem.app(id)
                AppTileView(
                    model: TileModel.make(item, store: store, showRunning: showRunning),
                    iconSize: fm.iconSize,
                    labelWidth: fm.cellWidth - 8,
                    showLabel: showLabels,
                    jiggle: (vm.editing || vm.optionHeld) && !reduceMotion,
                    showDelete: vm.showsDeleteBadges && (id.hasPrefix("web:") || id.hasPrefix("shortcut:") || store.catalog[id]?.isRemovable == true),
                    isMergeTarget: false,
                    isPlaceholder: vm.drag?.id == id,
                    onDelete: { vm.requestUninstall(for: item) }
                )
                .equatable()
                .frame(width: fm.cellWidth, height: fm.tileHeight)
                .modifier(PointerTracking(item: item, source: .folder(folder.id), vm: vm))
                .contextMenu { ItemContextMenu(vm: vm, store: store, item: item, folderID: folder.id) }
                .position(x: center.x, y: center.y)
            }
        }
        .frame(width: fm.contentRect.width, height: fm.contentHeight, alignment: .topLeading)

        if fm.scrolls {
            ScrollView(.vertical, showsIndicators: false) { grid }
        } else {
            grid
        }
    }

    private func commitTitle() {
        if title.trimmingCharacters(in: .whitespacesAndNewlines) != folder.name {
            store.renameFolder(folder.id, to: title)
        }
    }
}

// MARK: - Barre de favoris épinglée (Pro)

struct FavoritesDockView: View {
    @ObservedObject var vm: LaunchpadViewModel
    @ObservedObject var store: LaunchpadStore
    @State private var hoveredID: String?
    @AppStorage(PrefKey.backgroundStyle) private var backgroundStyle: BackgroundStyle = .liquidGlass

    var body: some View {
        HStack(spacing: 12) {
            ForEach(vm.favoriteApps) { app in
                let isHovered = hoveredID == app.id
                Button {
                    vm.activate(.app(app.id))
                } label: {
                    VStack(spacing: 3) {
                        Image(nsImage: IconCache.shared.icon(for: app.id))
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 36, height: 36)
                            .scaleEffect(isHovered ? 1.15 : 1.0)
                            .animation(.spring(response: 0.22, dampingFraction: 0.75), value: isHovered)

                        if store.isRunning(app) {
                            Circle()
                                .fill(Color.white.opacity(0.85))
                                .frame(width: 4, height: 4)
                        } else {
                            Color.clear.frame(width: 4, height: 4)
                        }
                    }
                }
                .buttonStyle(.plain)
                .onHover { hovered in hoveredID = hovered ? app.id : nil }
                .help(app.name)
                .contextMenu {
                    Button(loc("menu.open")) { vm.activate(.app(app.id)) }
                    Divider()
                    Button(loc("menu.remove_from_favorites")) { vm.toggleFavorite(app.id) }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background {
            if backgroundStyle == .liquidGlass {
                Capsule()
                    .liquidGlass(in: Capsule(), interactive: false)
            } else {
                Capsule()
                    .fill(Color.black.opacity(0.42))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.20), lineWidth: 0.8))
            }
        }
        .shadow(color: .black.opacity(0.38), radius: 18, x: 0, y: 9)
        .shadow(color: .black.opacity(0.16), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Galerie Visuelle de Widgets (Design Apple Sidebar + Grille de Cartes inspiré Photo 1)

struct WidgetGalleryModal: View {
    @ObservedObject var vm: LaunchpadViewModel
    @ObservedObject var store: LaunchpadStore
    let rootSize: CGSize

    enum GalleryCategory: String, CaseIterable, Identifiable {
        case all = "Tous les widgets"
        case weather = "Météo"
        case music = "Musique"
        case clock = "Horloge"
        case calendar = "Calendrier"
        case utilities = "Utilitaires"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .all: return "square.grid.2x2.fill"
            case .weather: return "cloud.sun.fill"
            case .music: return "music.note"
            case .clock: return "clock.fill"
            case .calendar: return "calendar"
            case .utilities: return "note.text"
            }
        }
    }

    struct GalleryCardItem: Identifiable, Equatable {
        let id: String
        let title: String
        let subtitle: String
        let category: GalleryCategory
        let config: CustomWidgetConfig
    }

    @ObservedObject private var licenseManager = LicenseManager.shared
    @State private var selectedCategory: GalleryCategory = .all
    @State private var searchText: String = ""
    @State private var selectedCardID: String = "weather-darkPremium"
    @State private var selectedSize: WidgetSize = .medium
    @State private var hoveredCardID: String? = nil
    @State private var isCollectionsExpanded: Bool = true

    private var allCards: [GalleryCardItem] {
        var list: [GalleryCardItem] = []

        for theme in WeatherWidgetTheme.allCases {
            list.append(GalleryCardItem(
                id: "weather-\(theme.rawValue)",
                title: theme.title,
                subtitle: "Météo en direct",
                category: .weather,
                config: CustomWidgetConfig(kind: .weather, size: .medium, weatherTheme: theme)
            ))
        }

        for style in MusicWidgetStyle.allCases {
            let kind: WidgetKind = (style == .fullBleedPill || style == .framedEditorial) ? .mediaWide : .vinylPlayer
            list.append(GalleryCardItem(
                id: "music-\(style.rawValue)",
                title: style.title,
                subtitle: kind == .vinylPlayer ? "Vinyle Apple Music & Spotify" : "Lecteur Musique",
                category: .music,
                config: CustomWidgetConfig(kind: kind, size: .medium, musicStyle: style)
            ))
        }

        for style in ClockWidgetStyle.allCases {
            list.append(GalleryCardItem(
                id: "clock-\(style.rawValue)",
                title: style.title,
                subtitle: "Horloge",
                category: .clock,
                config: CustomWidgetConfig(kind: .clock, size: .small, clockStyle: style)
            ))
        }

        for style in CalendarWidgetStyle.allCases {
            list.append(GalleryCardItem(
                id: "calendar-\(style.rawValue)",
                title: style.title,
                subtitle: "Calendrier EventKit",
                category: .calendar,
                config: CustomWidgetConfig(kind: .calendar, size: .medium, calendarStyle: style)
            ))
        }

        list.append(GalleryCardItem(
            id: "util-quickNote",
            title: "Note rapide",
            subtitle: "Bloc-notes instantané",
            category: .utilities,
            config: CustomWidgetConfig(kind: .quickNote, size: .medium)
        ))
        list.append(GalleryCardItem(
            id: "util-system",
            title: "État du Mac",
            subtitle: "Processeur, RAM & Batterie",
            category: .utilities,
            config: CustomWidgetConfig(kind: .system, size: .medium)
        ))

        return list
    }

    private var filteredCards: [GalleryCardItem] {
        let byCategory = selectedCategory == .all ? allCards : allCards.filter { $0.category == selectedCategory }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return byCategory }
        return byCategory.filter {
            $0.title.lowercased().contains(q)
            || $0.subtitle.lowercased().contains(q)
            || $0.category.rawValue.lowercased().contains(q)
        }
    }

    private var activeCard: GalleryCardItem {
        allCards.first(where: { $0.id == selectedCardID }) ?? filteredCards.first ?? allCards[0]
    }

    var body: some View {
        ZStack {
            // Arrière-plan sombre avec flou
            Color.black.opacity(0.58)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        vm.showWidgetGallery = false
                    }
                }

            HStack(spacing: 0) {
                // 1. Barre latérale gauche (fidèle à la Photo de référence 1)
                gallerySidebar
                    .frame(width: 222)
                    .background(Color.black.opacity(0.28))

                // 2. Panneau principal à droite (En-tête + Recherche + Grille 4 colonnes + Barre d'ajout)
                VStack(spacing: 0) {
                    rightHeader
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                        .padding(.bottom, 12)

                    gallerySearchBar
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)

                    // Grille visuelle de cartes (inspirée de la grille Albums/Playlists de la Photo 1)
                    ScrollView(.vertical, showsIndicators: false) {
                        if filteredCards.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 28))
                                    .foregroundStyle(.white.opacity(0.45))
                                Text("Aucun widget trouvé pour « \(searchText) »")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                        } else {
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 152, maximum: 185), spacing: 14)],
                                spacing: 18
                            ) {
                                ForEach(filteredCards) { card in
                                    galleryGridCard(card)
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.top, 4)
                            .padding(.bottom, 20)
                        }
                    }

                    Divider().background(Color.white.opacity(0.12))

                    // Prévisualisation animée style Apple selon la taille sélectionnée
                    liveSizePreviewBanner
                        .padding(.horizontal, 24)
                        .padding(.top, 10)
                        .padding(.bottom, 4)
                        .background(Color.black.opacity(0.18))

                    // Barre d'action en bas : Taille + Bouton Ajouter
                    bottomActionBar
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.22))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white.opacity(0.05))
            }
            .frame(width: min(920, rootSize.width - 36), height: min(630, rootSize.height - 44))
            .liquidGlassCard(cornerRadius: 24, interactive: false, borderLineWidth: 1.2)
            .shadow(color: LiquidGlassStyle.shadowColor, radius: 36, y: 16)
        }
    }

    private var gallerySidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Widgets")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Tous les styles")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                if !licenseManager.isPro {
                    Text("PRO")
                        .font(.system(size: 9.5, weight: .black))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(Color.yellow.opacity(0.9))
                        .foregroundStyle(.black)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 20)
            .padding(.bottom, 16)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 3) {
                    sidebarCategoryRow(.all)

                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isCollectionsExpanded.toggle()
                        }
                    } label: {
                        HStack {
                            Text("Catégories")
                                .font(.system(size: 13.5, weight: .bold))
                                .foregroundStyle(.white.opacity(0.9))
                            Spacer()
                            Image(systemName: isCollectionsExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 14)
                        .padding(.bottom, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if isCollectionsExpanded {
                        ForEach([GalleryCategory.weather, .music, .clock, .calendar, .utilities]) { cat in
                            sidebarCategoryRow(cat)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
            }
        }
    }

    private func sidebarCategoryRow(_ cat: GalleryCategory) -> some View {
        let isSelected = selectedCategory == cat
        return Button {
            withAnimation(.easeOut(duration: 0.15)) {
                selectedCategory = cat
                if let first = filteredCards.first, !filteredCards.contains(where: { $0.id == selectedCardID }) {
                    selectCard(first)
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: cat.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.68))
                    .frame(width: 20, height: 20)
                Text(cat.rawValue)
                    .font(.system(size: 13.5, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.85))
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8.5)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.18) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var rightHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(selectedCategory.rawValue)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                Text("\(filteredCards.count) \(filteredCards.count > 1 ? "modèles disponibles" : "modèle disponible")")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.58))
            }
            Spacer()
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    vm.showWidgetGallery = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fermer la galerie de widgets")
        }
    }

    private var gallerySearchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
            TextField("Rechercher dans les widgets (ex : météo, vinyle, néon, flip…)", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
    }

    private func galleryGridCard(_ card: GalleryCardItem) -> some View {
        let isSelected = (selectedCardID == card.id)
        let isHovered = (hoveredCardID == card.id)
        var effectiveConfig = card.config
        if isSelected, card.config.kind.allowedSizes.contains(selectedSize) {
            effectiveConfig.size = selectedSize
        }
        let previewW = effectiveConfig.size.width
        let previewH = effectiveConfig.size.height
        let boxSize: CGFloat = 148
        let thumbScale = min(132 / previewW, 118 / previewH)

        return Button {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.78)) {
                selectCard(card)
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    WidgetHostView(config: effectiveConfig, isPreview: true)
                        .scaleEffect(thumbScale)
                        .frame(width: previewW * thumbScale, height: previewH * thumbScale)
                        .shadow(color: .black.opacity(0.32), radius: 10, x: 0, y: 5)
                        .allowsHitTesting(false)
                        .animation(.spring(response: 0.38, dampingFraction: 0.76), value: effectiveConfig.size)
                }
                .frame(height: boxSize * 0.86)
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 2) {
                    Text(card.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(card.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.60))
                        .lineLimit(1)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.18) : (isHovered ? Color.white.opacity(0.08) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isSelected ? Color.white.opacity(0.30) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredCardID = hovering ? card.id : (hoveredCardID == card.id ? nil : hoveredCardID)
        }
    }

    @ViewBuilder
    private var liveSizePreviewBanner: some View {
        let card = activeCard
        let chosenSize = card.config.kind.allowedSizes.contains(selectedSize) ? selectedSize : card.config.kind.defaultSize
        let previewConfig: CustomWidgetConfig = {
            var c = card.config
            c.size = chosenSize
            return c
        }()
        let pw = previewConfig.size.width
        let ph = previewConfig.size.height
        let scale = min(130.0 / ph, 250.0 / pw)

        HStack(spacing: 16) {
            ZStack {
                WidgetHostView(config: previewConfig, isPreview: true)
                    .scaleEffect(scale)
                    .frame(width: pw * scale, height: ph * scale)
                    .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 6)
                    .allowsHitTesting(false)
            }
            .frame(width: 256, height: 132)
            .animation(.spring(response: 0.40, dampingFraction: 0.78), value: chosenSize)
            .animation(.spring(response: 0.36, dampingFraction: 0.80), value: selectedCardID)

            VStack(alignment: .leading, spacing: 4) {
                Text("Aperçu en direct • \(friendlySizeLabel(chosenSize))")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(Color.cyan)
                Text(card.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("Format \(Int(pw))×\(Int(ph)) pt • \(card.subtitle)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.65))
            }
            Spacer()
        }
    }

    private var bottomActionBar: some View {
        let card = activeCard
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(card.title)
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(card.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            }
            .frame(minWidth: 110, alignment: .leading)

            Spacer(minLength: 8)

            if card.config.kind.allowedSizes.count > 1 {
                HStack(spacing: 6) {
                    ForEach(card.config.kind.allowedSizes) { size in
                        let isChosen = selectedSize == size
                        Button {
                            withAnimation(AppleDesignSystem.Springs.snappy) {
                                selectedSize = size
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: sizeSymbol(for: size))
                                    .font(.system(size: 11, weight: .semibold))
                                Text(friendlySizeLabel(size))
                                    .font(.system(size: 12, weight: isChosen ? .bold : .medium))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(isChosen ? .black : .white.opacity(0.88))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6.5)
                            .background(isChosen ? Color.white : Color.white.opacity(0.12), in: Capsule())
                            .fixedSize(horizontal: true, vertical: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .fixedSize(horizontal: true, vertical: true)
            }

            Button {
                addSelectedWidget()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text("Ajouter")
                        .font(.system(size: 13.5, weight: .bold))
                        .lineLimit(1)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(
                    LinearGradient(
                        colors: [Color(red: 0.10, green: 0.52, blue: 1.0), Color(red: 0.42, green: 0.30, blue: 0.98)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: Capsule()
                )
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
                .shadow(color: Color.blue.opacity(0.32), radius: 8, y: 3)
                .fixedSize(horizontal: true, vertical: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ajouter le widget \(card.title)")
        }
    }

    private func selectCard(_ card: GalleryCardItem) {
        selectedCardID = card.id
        if card.config.kind.allowedSizes.contains(selectedSize) {
            // Conserver la taille choisie si compatible
        } else {
            selectedSize = card.config.kind.defaultSize
        }
    }

    private func addSelectedWidget() {
        if !licenseManager.isPro {
            vm.showProUpgradeAlert(
                feature: loc("widget.gallery.title"),
                description: "Les widgets interactifs sont inclus dans la version Pro.\n\nVous pouvez activer votre essai gratuit ou votre licence dans les Réglages."
            )
            return
        }
        let card = activeCard
        let chosenSize = card.config.kind.allowedSizes.contains(selectedSize) ? selectedSize : card.config.kind.defaultSize
        var newConfig = card.config
        newConfig.size = chosenSize

        let currentPage = vm.page
        WidgetManager.shared.updateMusicStyle(for: newConfig.kind, style: newConfig.musicStyle)
        if newConfig.kind == .weather {
            WidgetManager.shared.updateWeatherTheme(newConfig.weatherTheme)
        } else if newConfig.kind == .calendar {
            WidgetManager.shared.updateCalendarStyle(newConfig.calendarStyle)
        } else if newConfig.kind == .clock {
            WidgetManager.shared.updateClockStyle(newConfig.clockStyle)
        }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            let ok = store.addWidget(newConfig, onPage: currentPage, columns: vm.columns, rows: vm.rows)
            if ok {
                vm.showWidgetGallery = false
                if let placed = vm.placedItem(for: newConfig.id) {
                    vm.setPage(placed.page)
                } else {
                    vm.setPage(currentPage)
                }
            } else {
                vm.showToast(loc("widget.resize_failed"))
            }
        }
    }

    private func friendlySizeLabel(_ size: WidgetSize) -> String {
        switch size {
        case .small: return "Petit"
        case .medium: return "Moyen"
        case .tall: return "Vertical"
        case .large: return "Grand"
        }
    }

    private func sizeSymbol(for size: WidgetSize) -> String {
        switch size {
        case .small: return "square"
        case .medium: return "rectangle"
        case .tall: return "rectangle.portrait"
        case .large: return "square.split.2x2"
        }
    }
}
