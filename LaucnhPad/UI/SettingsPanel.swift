import Combine
import SwiftUI
import AppKit
import ServiceManagement

// MARK: - Réglages (mise en page inspirée de la fenêtre de réglages de LaunchOS)

enum SettingsStyle {
    static let accent = Color(red: 0.70, green: 0.36, blue: 0.80)
    static let cardFill = Color.primary.opacity(0.055)
    static let cardStroke = Color.primary.opacity(0.06)
    static let separator = Color.primary.opacity(0.09)
}

struct SettingsPanel: View {
    static let size = CGSize(width: 880, height: 640)
    static var targetTab: SettingsTab? = nil

    static var initialTab: SettingsTab {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--settings-tab"), index + 1 < arguments.count,
           let tab = SettingsTab(rawValue: arguments[index + 1]) {
            return tab
        }
        #endif
        return targetTab ?? .general
    }

    @ObservedObject var store: LaunchpadStore
    @AppStorage(PrefKey.columns) private var columns = 7
    @AppStorage(PrefKey.rows) private var rows = 5
    @AppStorage(PrefKey.backgroundOpacity) private var opacity = 0.35
    @AppStorage(PrefKey.liquidGlassIntensity) private var liquidGlassIntensity = 0.85
    @AppStorage(PrefKey.backgroundStyle) private var backgroundStyle: BackgroundStyle = .liquidGlass
    @AppStorage(PrefKey.iconScale) private var iconScale = 1.0
    @AppStorage(PrefKey.scrollSensitivity) private var scrollSensitivity = 1.0
    @AppStorage(PrefKey.settingsOpacity) private var settingsOpacity = 0.92
    @AppStorage(PrefKey.reduceMotion) private var reduceMotion = false
    @AppStorage(PrefKey.showLabels) private var showLabels = true
    @AppStorage(PrefKey.showRunningIndicator) private var showRunning = true
    @AppStorage(PrefKey.pinchMode) private var pinchMode: PinchMode = .three
    @AppStorage(PrefKey.hotCorner) private var hotCorner: HotCorner = .off
    @AppStorage(PrefKey.interceptF4) private var interceptF4 = false
    @AppStorage(PrefKey.hotKeyEnabled) private var hotKeyEnabled = true
    @AppStorage(PrefKey.screenTarget) private var screenTarget: ScreenTarget = .cursor
    @AppStorage(PrefKey.returnToFirstPage) private var returnToFirstPage = -1
    @AppStorage(PrefKey.showMenuBarIcon) private var showMenuBarIcon = true
    @AppStorage(PrefKey.showDockIcon) private var showDockIcon = false
    @AppStorage(PrefKey.showHiddenInSearch) private var showHiddenInSearch = false
    @AppStorage(PrefKey.reorganizeRule) private var reorganizeRule: SortRule = .nameAscending
    @AppStorage(PrefKey.folderPlacement) private var folderPlacement: FolderPlacement = .before
    @AppStorage(PrefKey.sortFolderContents) private var sortFolderContents = false
    @AppStorage(PrefKey.displayMode) private var displayMode: DisplayMode = .fullScreen
    @AppStorage(PrefKey.hideDock) private var hideDock = true
    @AppStorage(PrefKey.appLogo) private var appLogo: AppLogo = .noir
    @AppStorage(PrefKey.tintedIcons) private var tintedIcons = false
    @AppStorage(PrefKey.tintedIconColor) private var tintedIconColor = "accent"
    @AppStorage(PrefKey.showFavoritesBar) private var showFavoritesBar = true
    @ObservedObject private var licenseManager = LicenseManager.shared
    @ObservedObject private var customTileManager = CustomTileManager.shared
    @ObservedObject private var locManager = LocalizationManager.shared
    @ObservedObject private var adminManager = AdminManager.shared
    @State private var adminUsername = ""
    @State private var adminPassword = ""
    @State private var adminErrorMessage: String?
    @State private var isPasswordVisible = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var accessibilityGranted = AXIsProcessTrusted()
    @State private var selectedTab = SettingsPanel.initialTab
    @State private var customSources: [String] = Prefs.customSources
    @State private var sortChoice = "custom"
    @State private var message: String?
    @State private var licenseInput = ""
    @State private var licenseFeedback: (isError: Bool, message: String)?
    @State private var showProCelebration = false
    @State private var showAdvancedInGeneral = false
    @State private var showManageAppsInCustomization = false
    @State private var settingsToast: String? = nil
    @State private var isPlusSectionExpanded: Bool = true
    @State private var hasLaunchOSDB = false
    @State private var hasSystemLPDB = false
    @State private var fourFingerPinchConflict = false
    @State private var threeFingerDragConflict = false
    @State private var hotCornerConflict = false
    @State private var settingsToastTask: Task<Void, Never>? = nil
    @State private var iconScalePreviewTask: Task<Void, Never>? = nil
    @AppStorage(PrefKey.autoCheckUpdates) private var autoCheckUpdates = true
    @AppStorage("LaunchpadEnableUsageTips") private var enableUsageTips = true
    @AppStorage("LaunchpadEnableSoundFeedback") private var enableSoundFeedback = true

    enum SettingsTab: String, CaseIterable, Identifiable {
        case interface, apps, notifications, general, license, about, advanced
        var id: String { rawValue }

        static var primaryTabs: [SettingsTab] {
            [.interface, .apps, .notifications, .general]
        }

        static var secondaryTabs: [SettingsTab] {
            [.advanced, .license, .about]
        }

        static var visibleTabs: [SettingsTab] {
            [.interface, .apps, .notifications, .general, .license, .about]
        }

        var subtitle: String {
            loc("tab.sub.\(rawValue)")
        }

        var title: String {
            switch self {
            case .interface: return loc("tab.appearance")
            case .apps: return loc("tab.customization")
            case .notifications: return loc("tab.notifications")
            case .general: return loc("tab.general")
            case .license: return loc("tab.license")
            case .about: return loc("tab.about")
            case .advanced: return loc("tab.advanced")
            }
        }
        var symbol: String {
            switch self {
            case .interface: return "paintpalette.fill"
            case .apps: return "sparkles.rectangle.stack.fill"
            case .notifications: return "bell.badge.fill"
            case .general: return "gearshape.fill"
            case .license: return "crown.fill"
            case .about: return "info.circle.fill"
            case .advanced: return "slider.horizontal.3"
            }
        }
    }

    private func triggerSettingsToast(_ text: String) {
        settingsToastTask?.cancel()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            settingsToast = text
        }
        settingsToastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                if settingsToast == text {
                    settingsToast = nil
                }
            }
        }
    }

    private func refreshSystemChecks() {
        let cornerKey = hotCorner.dockKey
        let checkCorner = hotCorner != .off
        Task { @MainActor in
            let results = await Task.detached(priority: .userInitiated) {
                (
                    launchOS: LaunchOSReader.databaseURL != nil,
                    systemLP: SystemLaunchpadReader.databaseURL != nil,
                    pinch: SystemConflicts.systemFourFingerPinchEnabled,
                    drag: SystemConflicts.systemThreeFingerDragEnabled,
                    corner: checkCorner && SystemConflicts.systemHotCornerAssigned(dockKey: cornerKey)
                )
            }.value
            if hasLaunchOSDB != results.launchOS { hasLaunchOSDB = results.launchOS }
            if hasSystemLPDB != results.systemLP { hasSystemLPDB = results.systemLP }
            if fourFingerPinchConflict != results.pinch { fourFingerPinchConflict = results.pinch }
            if threeFingerDragConflict != results.drag { threeFingerDragConflict = results.drag }
            if hotCornerConflict != results.corner { hotCornerConflict = results.corner }
        }
    }

    var body: some View {
        settingsInteractionShell
            .onAppear {
                PermissionManager.shared.checkStatus()
                accessibilityGranted = AXIsProcessTrusted()
                refreshSystemChecks()
                if let target = SettingsPanel.targetTab {
                    selectedTab = target
                    SettingsPanel.targetTab = nil
                }
            }
            .onDisappear {
                iconScalePreviewTask?.cancel()
                iconScalePreviewTask = nil
                NotificationCenter.default.post(name: .iconScalePreviewDidChange, object: false)
            }
            .onReceive(NotificationCenter.default.publisher(for: .settingsWillShow)) { _ in
                PermissionManager.shared.checkStatus()
                accessibilityGranted = AXIsProcessTrusted()
                refreshSystemChecks()
                if let target = SettingsPanel.targetTab {
                    selectedTab = target
                    SettingsPanel.targetTab = nil
                } else {
                    let initial = SettingsPanel.initialTab
                    if selectedTab != initial { selectedTab = initial }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openSettingsTab)) { note in
                if let tab = note.object as? SettingsTab {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                }
            }
    }

    private var settingsInteractionShell: some View {
        settingsDecoratedShell
            .onReceive(PermissionManager.shared.$isAccessibilityGranted) { granted in
                accessibilityGranted = granted
            }
            .onChange(of: hotCorner) { (_: HotCorner, newValue: HotCorner) in
                hotCornerConflict = (newValue != .off && SystemConflicts.systemHotCornerAssigned(newValue))
            }
            .onChange(of: selectedTab) { (_: SettingsTab, tab: SettingsTab) in
                if tab == .general || tab == .interface || tab == .advanced {
                    refreshSystemChecks()
                }
                if tab != .interface {
                    NotificationCenter.default.post(name: .iconScalePreviewDidChange, object: false)
                }
            }
            .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) { message = nil }
            }
    }

    private var settingsDecoratedShell: some View {
        settingsShell
            .frame(width: Self.size.width, height: Self.size.height)
            .background(settingsBackground)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay { settingsBorderOverlay }
            .environment(\.colorScheme, backgroundStyle == .light ? .light : .dark)
    }

    @ViewBuilder
    private var settingsBorderOverlay: some View {
        if backgroundStyle == .liquidGlass {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    LiquidGlassStyle.specularBorder(intensity: liquidGlassIntensity),
                    lineWidth: 1.2
                )
        } else {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1.0)
        }
    }

    private var settingsShell: some View {
        ZStack(alignment: .bottom) {
            HStack(spacing: 0) {
                // Barre latérale gauche inspirée de l'interface Apple (Photo de référence 1)
                appleSidebar
                    .frame(width: 228)
                    .background(Color.black.opacity(backgroundStyle == .light ? 0.05 : 0.22))

                // Panneau de contenu principal à droite
                VStack(spacing: 0) {
                    rightPaneHeader
                        .padding(.horizontal, 24)
                        .padding(.top, 22)
                        .padding(.bottom, 14)

                    Divider().background(SettingsStyle.separator)

                    ScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            switch selectedTab {
                            case .interface: interfaceTab
                            case .apps: customizationAndAppsTab
                            case .notifications: notificationsTab
                            case .general: generalTab
                            case .advanced: advancedTab
                            case .license: licenseTab
                            case .about: aboutTab
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                        .padding(.bottom, 52)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white.opacity(backgroundStyle == .light ? 0.22 : 0.045))
            }

            if let settingsToast {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(settingsToast)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(Color.black.opacity(0.84), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.20), lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
                .padding(.bottom, 14)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(500)
            }

            if showProCelebration {
                ProCelebrationPopup(onDismiss: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        showProCelebration = false
                    }
                })
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .zIndex(999)
            }
        }
    }

    @ViewBuilder
    private var settingsBackground: some View {
        let i = max(0.0, min(1.0, liquidGlassIntensity))
        ZStack {
            switch backgroundStyle {
            case .dark:
                VisualEffectBackground(material: .fullScreenUI)
                Color.black.opacity(0.72)
            case .light:
                VisualEffectBackground(material: .underWindowBackground)
                Color.white.opacity(0.62)
            case .liquidGlass:
                VisualEffectBackground(material: .fullScreenUI)
                    .opacity(0.30 + 0.70 * i)
                Color.black.opacity(0.26)
                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.purple.opacity(0.06),
                        Color.blue.opacity(0.05),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .ignoresSafeArea()
    }

    // MARK: Onglets (icône au-dessus du titre, onglet actif en violet)

    // MARK: Barre Latérale Apple & En-tête Panneau Droit (Inspiré Photo 1)

    private var appleSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // En-tête de la barre latérale (avec photo et prénom du compte Apple si disponible)
            HStack(alignment: .center, spacing: 10) {
                if let avatar = licenseManager.appleAccountAvatar {
                    Image(nsImage: avatar)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .frame(width: 34, height: 34)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.14), lineWidth: 1))
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(loc("settings.title"))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                    HStack(spacing: 4) {
                        Text(licenseManager.appleAccountFirstName.isEmpty ? "LaunchPad" : licenseManager.appleAccountFirstName)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if licenseManager.isPro {
                            AnimatedVerifiedSealBadge(
                                isTrial: licenseManager.isTrialActive && !licenseManager.isProLifetime,
                                size: 14
                            )
                        }
                    }
                }
                Spacer()
                Button {
                    selectedTab = .about
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color.primary.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .help(loc("about.tooltip"))
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 16)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(SettingsTab.primaryTabs) { tab in
                        sidebarRow(for: tab)
                    }

                    // Groupe secondaire dépliable (comme "Playlists v")
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isPlusSectionExpanded.toggle()
                        }
                    } label: {
                        HStack {
                            Text(loc("settings.plus_section"))
                                .font(.system(size: 13.5, weight: .bold))
                                .foregroundStyle(.primary.opacity(0.9))
                            Spacer()
                            Image(systemName: isPlusSectionExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 16)
                        .padding(.bottom, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if isPlusSectionExpanded {
                        ForEach(SettingsTab.secondaryTabs) { tab in
                            sidebarRow(for: tab)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
            }
        }
    }

    private func sidebarRow(for tab: SettingsTab) -> some View {
        let selected = selectedTab == tab
        return Button {
            withAnimation(.easeOut(duration: 0.16)) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(selected ? .white : (tab == .license && licenseManager.isPro ? Color.yellow : Color.secondary))
                    .frame(width: 20, height: 20)

                Text(tab.title)
                    .font(.system(size: 13.5, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? .white : .primary.opacity(0.88))
                    .lineLimit(1)

                Spacer(minLength: 4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8.5)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Color.primary.opacity(backgroundStyle == .light ? 0.14 : 0.16) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(loc("settings.tab_a11y", tab.title))
    }

    private var rightPaneHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(selectedTab.title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.primary)
                Text(selectedTab.subtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                Text("ESC")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                Text(loc("settings.esc_hint"))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel(loc("settings.esc_a11y"))
        }
    }

    // MARK: Notifications (Gestion simple et claire des alertes)

    @ViewBuilder
    private var notificationsTab: some View {
        SettingsSectionTitle(loc("notif.section.alerts"))
        SettingsCardBox {
            SettingsRow(
                loc("notif.auto_update"),
                subtitle: loc("notif.auto_update_desc")
            ) {
                SettingsAutoUpdateSwitch(autoCheckUpdates: $autoCheckUpdates, triggerToast: triggerSettingsToast)
            }
            SettingsSeparator()
            SettingsRow(
                loc("notif.tips"),
                subtitle: loc("notif.tips_desc")
            ) {
                SettingsSwitch(isOn: $enableUsageTips)
                    .onChange(of: enableUsageTips) { _, val in
                        triggerSettingsToast(val ? loc("notif.tips_on_toast") : loc("notif.tips_off_toast"))
                    }
            }
            SettingsSeparator()
            SettingsRow(
                loc("notif.confirmations"),
                subtitle: loc("notif.confirmations_desc")
            ) {
                SettingsSwitch(isOn: $enableSoundFeedback)
                    .onChange(of: enableSoundFeedback) { _, val in
                        triggerSettingsToast(val ? loc("notif.confirmations_on_toast") : loc("notif.confirmations_off_toast"))
                    }
            }
        }

        SettingsSectionTitle(loc("notif.section.macos"))
        SettingsCardBox {
            SettingsRow(
                loc("notif.test_title"),
                subtitle: loc("notif.test_desc")
            ) {
                Button(loc("notif.test_button")) {
                    NotificationCenter.default.post(name: .triggerTestToast, object: nil)
                    triggerSettingsToast(loc("notif.test_toast"))
                }
                .buttonStyle(.borderedProminent)
                .tint(SettingsStyle.accent)
                .controlSize(.small)
            }
            SettingsSeparator()
            SettingsRow(
                loc("notif.macos_settings"),
                subtitle: loc("notif.macos_settings_desc")
            ) {
                Button(loc("notif.macos_settings_button")) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .controlSize(.small)
            }
        }
    }

    // MARK: Personnalisation (Icônes HD, Grille, Widgets & Applications)

    @ViewBuilder
    private var customizationAndAppsTab: some View {
        if licenseManager.isPro {
            SettingsSectionTitle(loc("custom.icons_hd_section"))
            SettingsCardBox {
                VStack(alignment: .leading, spacing: 10) {
                    IconAppearanceShowcaseView(
                        onStyleChanged: {
                            triggerSettingsToast(loc("custom.icon_style_toast"))
                        },
                        onRequirePro: { title, msg in
                            confirm(title, msg) {
                                withAnimation { selectedTab = .license }
                            }
                        }
                    )
                }
                .padding(.vertical, 10)

                if !CustomIconManager.shared.overrides.isEmpty {
                    SettingsSeparator()
                    SettingsRow(
                        loc("custom.indiv_icons_title"),
                        subtitle: loc("custom.indiv_icons_sub", CustomIconManager.shared.overrides.count)
                    ) {
                        Button(loc("custom.restore_all_defaults")) {
                            CustomIconManager.shared.removeAllOverrides()
                            triggerSettingsToast(loc("custom.restore_all_toast"))
                        }
                        .controlSize(.small)
                    }
                }
            }
        }

        SettingsSectionTitle(loc("section.theme"))
        SettingsCardBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    ForEach(AppTheme.allCases) { theme in
                        ThemeCardButton(
                            theme: theme,
                            isSelected: backgroundStyle == theme,
                            isProUnlocked: licenseManager.isPro
                        ) {
                            handleThemeSelection(theme)
                        }
                    }
                }

                // Description et retour visuel du thème actif
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(SettingsStyle.accent)
                        .font(.system(size: 13))
                    Text(backgroundStyle.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if backgroundStyle == .liquidGlass {
                        Text(loc("interface.apple_style"))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(SettingsStyle.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(SettingsStyle.accent.opacity(0.12), in: Capsule())
                    }
                }
                .padding(.top, 2)
            }
            .padding(.vertical, 14)

            if licenseManager.isPro && backgroundStyle == .liquidGlass {
                SettingsSeparator()
                SettingsSliderRow(
                    loc("interface.liquid_glass_intensity"),
                    subtitle: loc("interface.liquid_glass_intensity_subtitle"),
                    value: $liquidGlassIntensity,
                    range: 0.05...1.0,
                    step: 0.05,
                    isPercentage: true
                )
            }
        }

        SettingsSectionTitle(loc("custom.grid_section"))
        SettingsCardBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc("custom.icon_size_title"))
                            .font(.system(size: 14, weight: .semibold))
                        Text(loc("custom.icon_size_desc"))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                HStack {
                    Spacer(minLength: 0)
                    HStack(spacing: 10) {
                        ForEach([
                            (loc("widget.size.small"), 0.80),
                            (loc("widget.size.medium"), 1.00),
                            (loc("widget.size.large"), 1.15)
                        ], id: \.1) { label, value in
                            let isChosen = value == 1.15 ? (iconScale >= 1.11) : abs(iconScale - value) < 0.04
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                                    iconScale = value
                                }
                                iconScalePreviewTask?.cancel()
                                NotificationCenter.default.post(name: .iconScalePreviewDidChange, object: true)
                                iconScalePreviewTask = Task { @MainActor in
                                    try? await Task.sleep(for: .milliseconds(350))
                                    guard !Task.isCancelled else { return }
                                    NotificationCenter.default.post(name: .iconScalePreviewDidChange, object: false)
                                }
                                triggerSettingsToast(loc("custom.icon_size_toast", label))
                            } label: {
                                Text(label)
                                    .font(.system(size: 12.5, weight: isChosen ? .bold : .medium))
                                    .foregroundStyle(isChosen ? .white : .primary.opacity(0.88))
                                    .frame(width: 112)
                                    .padding(.vertical, 7)
                                    .background(
                                        isChosen ? SettingsStyle.accent : Color.primary.opacity(0.07),
                                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Spacer(minLength: 0)
                }

                IconScalePreviewBox(iconScale: $iconScale, reduceMotion: reduceMotion)
            }
            .padding(.vertical, 6)
            SettingsSeparator()
            SettingsRow(loc("custom.grid_dims_title"), subtitle: loc("custom.grid_dims_sub")) {
                HStack(spacing: 10) {
                    SettingsNumberField(value: $columns, range: 4...10)
                    Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                    SettingsNumberField(value: $rows, range: 3...8)
                }
            }
            SettingsSeparator()
            SettingsRow(loc("custom.show_labels")) {
                SettingsSwitch(isOn: $showLabels)
            }
            SettingsSeparator()
            SettingsRow(loc("custom.show_running")) {
                SettingsSwitch(isOn: $showRunning)
            }
            SettingsSeparator()
            SettingsRow(
                loc("interface.favorites_bar"),
                subtitle: loc("interface.favorites_subtitle"),
                isPro: true,
                isProUnlocked: licenseManager.isPro
            ) {
                SettingsSwitch(isOn: Binding(
                    get: { showFavoritesBar },
                    set: { newValue in
                        if newValue && !licenseManager.isPro {
                            confirm(loc("pro_alert.favorites_title"), loc("pro_alert.favorites_msg")) {
                                withAnimation { selectedTab = .license }
                            }
                        } else {
                            showFavoritesBar = newValue
                            triggerSettingsToast(newValue ? loc("custom.favorites_shown_toast") : loc("custom.favorites_hidden_toast"))
                        }
                    }
                ))
            }
        }

        SettingsSectionTitle(loc("custom.apps_folders_section"))
        appsTab
    }

    // MARK: Général

    @ViewBuilder
    private var generalTab: some View {
        if !accessibilityGranted {
            SettingsCardBox {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.orange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc("permission.banner.title"))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.primary)
                        Text(loc("permission.banner.desc"))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        PermissionManager.shared.requestAccessibility()
                    } label: {
                        Text(loc("general.authorize_button"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5.5)
                            .background(Color(red: 0.90, green: 0.43, blue: 0.05), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 10)
            }
        }

        SettingsSectionTitle(loc("section.language"))
        SettingsCardBox {
            HStack(spacing: 10) {
                ForEach(AppLanguage.allCases) { lang in
                    let isSelected = locManager.currentLanguage == lang
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                            locManager.currentLanguage = lang
                        }
                    } label: {
                        Group {
                            if lang == .auto {
                                HStack(spacing: 5) {
                                    Image(systemName: "globe")
                                        .font(.system(size: 13, weight: .semibold))
                                    Text(lang.shortTitle)
                                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                                }
                            } else {
                                Text(lang.flag)
                                    .font(.system(size: 20))
                            }
                        }
                        .foregroundStyle(isSelected ? .white : .primary.opacity(0.88))
                        .padding(.horizontal, lang == .auto ? 12 : 14)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isSelected ? SettingsStyle.accent : Color.primary.opacity(0.06))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(isSelected ? Color.white.opacity(0.24) : Color.primary.opacity(0.08), lineWidth: 0.8)
                        )
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(lang.displayName)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 12)
        }

        SettingsCardBox {
            VStack(spacing: 14) {
                HStack(spacing: 6) {
                    Text(loc("general.app_logo"))
                        .font(.system(size: 14, weight: .medium))
                    if !licenseManager.isPro {
                        ProBadge(isUnlocked: false)
                    }
                    Spacer()
                }

                HStack(spacing: 16) {
                    ForEach(AppLogo.allCases) { logo in
                        let effectiveSelected = licenseManager.isPro ? (appLogo == logo) : (logo == .noir)
                        AppLogoOption(
                            logo: logo,
                            selected: effectiveSelected,
                            isProUnlocked: licenseManager.isPro
                        ) {
                            handleLogoSelection(logo)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 4)
            }
            .padding(.vertical, 14)
        }

        SettingsCardBox {
            SettingsRow(loc("general.open_at_login")) {
                SettingsSwitch(isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                            message = "\(loc("general.open_at_login")) : \(error.localizedDescription)"
                        }
                    }
            }
            SettingsSeparator()
            SettingsRow(loc("general.menu_bar_icon")) { SettingsSwitch(isOn: $showMenuBarIcon) }
            SettingsSeparator()
            SettingsRow(loc("general.dock_icon"),
                        subtitle: loc("general.dock_icon_subtitle")) {
                SettingsSwitch(isOn: $showDockIcon)
            }
        }

        musicServicesSection

        SettingsSectionTitle(loc("section.activation"))
        SettingsCardBox {
            SettingsRow(loc("general.hotkey")) { SettingsSwitch(isOn: $hotKeyEnabled) }
            SettingsSeparator()
            SettingsRow(loc("general.hotkey_field"),
                        subtitle: loc("general.hotkey_subtitle")) {
                ShortcutRecorder().disabled(!hotKeyEnabled)
            }
        }
        SettingsCardBox {
            SettingsRow(loc("general.pinch"), subtitle: loc("general.pinch_subtitle")) {
                SettingsMenuPicker(selection: $pinchMode, options: PinchMode.allCases, title: \.title)
            }
            if pinchMode != .off && pinchMode != .three && fourFingerPinchConflict {
                SettingsWarning(loc("general.pinch_conflict"))
            }
            if pinchMode != .off && threeFingerDragConflict {
                SettingsWarning(loc("general.three_finger_drag_tip"))
            }
            SettingsSeparator()
            SettingsSliderRow(loc("general.scroll_sensitivity"), value: $scrollSensitivity, range: 0.2...2.0, step: 0.1)
            SettingsSeparator()
            SettingsRow(loc("general.hot_corner")) {
                SettingsMenuPicker(selection: $hotCorner, options: HotCorner.allCases, title: \.title)
            }
            if hotCorner != .off && hotCornerConflict {
                SettingsWarning(loc("general.hot_corner_conflict"))
            }
            SettingsSeparator()
            SettingsRow(loc("general.f4_key"), subtitle: loc("general.f4_subtitle")) {
                SettingsSwitch(isOn: $interceptF4)
                    .onChange(of: interceptF4) { _, enabled in
                        if enabled && !AXIsProcessTrusted() { InputEventMonitor.requestAccessibility() }
                    }
            }
            SettingsSeparator()
            SettingsRow(loc("general.accessibility_title")) {
                if accessibilityGranted {
                    Label(loc("general.authorized"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Button(loc("general.authorize_button")) {
                        PermissionManager.shared.requestAccessibility()
                    }
                }
            }
        }

        SettingsSectionTitle(loc("general.advanced_section"))
        SettingsCardBox {
            Button {
                withAnimation(AppleDesignSystem.Springs.snappy) {
                    showAdvancedInGeneral.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SettingsStyle.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc("general.advanced_toggle_title"))
                            .font(.system(size: 13.5, weight: .semibold))
                        Text(loc("general.advanced_toggle_sub"))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: showAdvancedInGeneral ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showAdvancedInGeneral {
                SettingsSeparator()
                SettingsRow(loc("general.screen_target")) {
                    SettingsMenuPicker(selection: $screenTarget, options: ScreenTarget.allCases, title: \.title)
                }
                SettingsSeparator()
                SettingsRow(loc("general.return_first_page")) {
                    Picker("", selection: $returnToFirstPage) {
                        Text(loc("return.never")).tag(-1)
                        Text(loc("return.always")).tag(0)
                        Text(loc("return.5s")).tag(5)
                        Text(loc("return.15s")).tag(15)
                        Text(loc("return.30s")).tag(30)
                        Text(loc("return.1m")).tag(60)
                        Text(loc("return.5m")).tag(300)
                    }
                    .labelsHidden().fixedSize()
                }
                SettingsSeparator()
                SettingsRow(loc("general.include_hidden_search")) { SettingsSwitch(isOn: $showHiddenInSearch) }
                SettingsSeparator()
                SettingsRow(loc("general.backup_row_title"), subtitle: loc("general.backup_row_sub")) {
                    HStack(spacing: 8) {
                        Button(loc("advanced.import")) { importBackup() }
                        Button(loc("advanced.export")) { exportBackup() }
                    }
                }
                SettingsSeparator()
                SettingsRow(loc("advanced.reset_title"), subtitle: loc("advanced.reset_subtitle")) {
                    Button(loc("advanced.reset_button")) {
                        confirm(loc("advanced.reset_confirm_title"), loc("advanced.reset_confirm_msg")) {
                            store.resetLayout()
                            triggerSettingsToast(loc("general.reset_done_toast"))
                        }
                    }
                }
            }
        }
    }

    // MARK: Interface

    @ViewBuilder
    private var interfaceTab: some View {
        SettingsCardBox {
            HStack(alignment: .top) {
                Text(loc("interface.display_mode")).font(.system(size: 14))
                Spacer(minLength: 16)
                HStack(spacing: 20) {
                    ForEach(DisplayMode.allCases) { mode in
                        DisplayModeOption(mode: mode, selected: displayMode == mode) { displayMode = mode }
                    }
                }
            }
            .padding(.vertical, 14)
            SettingsSeparator()
            SettingsRow(loc("interface.hide_dock"), subtitle: loc("interface.hide_dock_subtitle")) {
                SettingsSwitch(isOn: $hideDock)
            }
        }

        SettingsSectionTitle(loc("interface.layout"))
        SettingsCardBox {
            SettingsRow(loc("interface.sort_by"), info: loc("interface.sort_info")) {
                Picker("", selection: $sortChoice) {
                    Text(loc("interface.sort_custom")).tag("custom")
                    if hasLaunchOSDB {
                        Text(loc("interface.sort_launchos")).tag("launchos")
                    }
                    Divider()
                    ForEach(SortRule.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .labelsHidden().fixedSize()
                .onChange(of: sortChoice) { _, choice in applySortChoice(choice) }
            }
        }
        SettingsCardBox {
            SettingsRow(loc("interface.grid")) {
                HStack(spacing: 10) {
                    SettingsNumberField(value: $columns, range: 4...10)
                    Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                    SettingsNumberField(value: $rows, range: 3...8)
                }
            }
        }
        SettingsCardBox {
            SettingsRow(loc("interface.hide_labels")) {
                SettingsSwitch(isOn: Binding(get: { !showLabels }, set: { showLabels = !$0 }))
            }
            SettingsSeparator()
            SettingsRow(loc("interface.show_running")) { SettingsSwitch(isOn: $showRunning) }
        }

        SettingsSectionTitle(loc("section.pro_customization"))
        SettingsCardBox {
            SettingsRow(loc("interface.tinted_icons"),
                        subtitle: loc("interface.tinted_subtitle"),
                        isPro: true,
                        isProUnlocked: licenseManager.isPro) {
                SettingsSwitch(isOn: Binding(
                    get: { tintedIcons },
                    set: { newValue in
                        if newValue && !licenseManager.isPro {
                            confirm(loc("pro_alert.tinted_title"),
                                    loc("pro_alert.tinted_msg")) {
                                withAnimation { selectedTab = .license }
                            }
                        } else {
                            tintedIcons = newValue
                        }
                    }
                ))
            }
            if tintedIcons && licenseManager.isPro {
                SettingsSeparator()
                SettingsRow(loc("interface.tint_accent")) {
                    HStack(spacing: 8) {
                        ForEach([
                            ("accent", loc("tint.accent")),
                            ("graphite", loc("tint.graphite")),
                            ("blue", loc("tint.blue")),
                            ("purple", loc("tint.purple")),
                            ("orange", loc("tint.orange")),
                            ("mint", loc("tint.mint")),
                            ("rose", loc("tint.rose")),
                            ("gold", loc("tint.gold"))
                        ], id: \.0) { key, label in
                            Button {
                                tintedIconColor = key
                            } label: {
                                Circle()
                                    .fill(tintColor(for: key))
                                    .frame(width: 20, height: 20)
                                    .overlay(
                                        Circle().stroke(tintedIconColor == key ? Color.white : Color.clear, lineWidth: 2)
                                    )
                                    .scaleEffect(tintedIconColor == key ? 1.15 : 1.0)
                            }
                            .buttonStyle(.plain)
                            .help(label)
                        }
                    }
                }
            }
            SettingsSeparator()
            SettingsRow(loc("interface.favorites_bar"),
                        subtitle: loc("interface.favorites_subtitle"),
                        isPro: true,
                        isProUnlocked: licenseManager.isPro) {
                SettingsSwitch(isOn: Binding(
                    get: { showFavoritesBar },
                    set: { newValue in
                        if newValue && !licenseManager.isPro {
                            confirm(loc("pro_alert.favorites_title"),
                                    loc("pro_alert.favorites_msg")) {
                                withAnimation { selectedTab = .license }
                            }
                        } else {
                            showFavoritesBar = newValue
                        }
                    }
                ))
            }
        }

        SettingsSectionTitle(loc("section.animations"))
        SettingsCardBox {
            SettingsRow(loc("interface.reduce_motion"), subtitle: loc("interface.reduce_motion_subtitle")) {
                SettingsSwitch(isOn: $reduceMotion)
            }
            SettingsSeparator()
            SettingsSliderRow(loc("interface.settings_opacity"), value: $settingsOpacity, range: 0.45...1.0)
        }
    }

    // MARK: - Services Musicaux (Apple Music & Spotify)

    @ViewBuilder
    private var musicServicesSection: some View {
        MusicServicesSettingsView()
    }

    private struct MusicServicesSettingsView: View {
        @ObservedObject private var musicManager = MusicServiceManager.shared
        @ObservedObject private var locManager = LocalizationManager.shared
        @State private var hoveredSource: MusicServiceSource? = nil

        var body: some View {
            VStack(alignment: .center, spacing: 12) {
                Text(loc("music.source_header"))
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 14)

                HStack(spacing: 48) {
                    Spacer(minLength: 0)

                    sourceOption(source: .system, label: loc("music.source.auto_label")) {
                        autoSourceLogo
                    }

                    sourceOption(source: .spotify, label: "Spotify") {
                        sourceAppLogo("SpotifySourceLogo")
                    }

                    sourceOption(source: .appleMusic, label: "Music") {
                        sourceAppLogo("AppleMusicSourceLogo")
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)

                sourceStatusFooter
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.bottom, 4)
        }

        private func sourceOption<Icon: View>(
            source: MusicServiceSource,
            label: String,
            @ViewBuilder icon: () -> Icon
        ) -> some View {
            let isSelected = musicManager.preferredService == source
            let isHovered = hoveredSource == source

            return Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.80)) {
                    musicManager.selectSource(source)
                }
            } label: {
                VStack(spacing: 10) {
                    Text(label)
                        .font(.system(size: 13.5, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)

                    icon()
                        .frame(width: 48, height: 48)
                        .scaleEffect(isHovered ? 1.07 : (isSelected ? 1.03 : 1.0))

                    Circle()
                        .fill(isSelected ? Color.primary.opacity(0.92) : Color.clear)
                        .frame(width: 5, height: 5)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.16)) {
                    hoveredSource = hovering ? source : (hoveredSource == source ? nil : hoveredSource)
                }
            }
        }

        private func sourceSquircle<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
            content()
                .frame(width: 46, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 11.5, style: .continuous))
                .shadow(color: .black.opacity(0.24), radius: 5, y: 2)
        }

        private var autoSourceLogo: some View {
            sourceSquircle {
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(red: 0.25, green: 0.27, blue: 0.31),
                            Color(red: 0.13, green: 0.14, blue: 0.17)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    RoundedRectangle(cornerRadius: 11.5, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.8)
                    Image(systemName: "person.crop.rectangle.stack.fill")
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(.white.opacity(0.95))
                }
            }
        }

        private func sourceAppLogo(_ assetName: String) -> some View {
            sourceSquircle {
                Image(assetName)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            }
        }

        @ViewBuilder
        private var sourceStatusFooter: some View {
            switch musicManager.preferredService {
            case .system, .none:
                HStack(spacing: 6) {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                    Text(loc("music.source.auto_desc"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }

            case .spotify:
                switch musicManager.spotifyStatus {
                case .connected:
                    HStack(spacing: 6) {
                        Circle().fill(Color.green).frame(width: 6, height: 6)
                        Text(loc("music.spotify.connected_native"))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                case .connecting:
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text(loc("music.spotify.connecting"))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                case .restricted(let reason):
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                        Text(reason)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                        Button(loc("music.spotify.authorize_btn")) {
                            musicManager.openAutomationPrivacySettings()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                case .error(let msg):
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                        Text(msg)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                case .notConnected:
                    Button(loc("music.spotify.connect_btn")) {
                        musicManager.connectSpotify()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

            case .appleMusic:
                switch musicManager.appleMusicStatus {
                case .connected:
                    HStack(spacing: 6) {
                        Circle().fill(Color.green).frame(width: 6, height: 6)
                        Text(loc("music.apple.connected_label"))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                case .connecting:
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text(loc("music.apple.authorizing"))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                case .restricted(let reason):
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                        Text(reason)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                        Button(loc("settings.title")) {
                            musicManager.openAutomationPrivacySettings()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                case .error(let msg):
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                        Text(msg)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                case .notConnected:
                    Button(loc("music.apple.connect_btn")) {
                        musicManager.connectAppleMusic()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: Apps

    @ViewBuilder
    private var appsTab: some View {
        SettingsCardBox {
            SettingsRow(loc("apps.detected")) {
                Text("\(store.catalog.count)").foregroundStyle(.secondary).monospacedDigit()
            }
            SettingsSeparator()
            SettingsRow(loc("apps.catalog")) { Button(loc("apps.refresh")) { store.refresh() } }
            SettingsSeparator()
            SettingsRow(loc("apps.organize_apple_title"), subtitle: loc("apps.organize_apple_sub")) {
                Button(loc("apps.organize_now")) {
                    store.organizeAppleAppsIntoFolders()
                    triggerSettingsToast(loc("apps.organize_done_toast"))
                }
            }
            SettingsSeparator()
            SettingsRow(loc("apps.folders"), subtitle: loc("apps.ungroup_confirm_msg")) {
                Button(loc("apps.ungroup_all")) { store.ungroupAll() }
            }
        }

        SettingsSectionTitle(loc("section.hidden_apps"))
        let hiddenApps = store.hiddenApps
        SettingsCardBox {
            if hiddenApps.isEmpty {
                SettingsNote(loc("apps.no_hidden")).padding(.vertical, 6)
            } else {
                ForEach(Array(hiddenApps.enumerated()), id: \.element.id) { index, app in
                    if index > 0 { SettingsSeparator() }
                    HStack(spacing: 10) {
                        LiveAppIconView(image: IconCache.shared.icon(for: app.id), size: 24, useLiveGlass: false)
                        Text(app.name).font(.system(size: 14))
                        Spacer()
                        Button(loc("apps.unhide")) { store.unhide(app.id) }
                    }
                    .padding(.vertical, 8)
                }
            }
        }

        HStack(spacing: 6) {
            SettingsSectionTitle(loc("section.custom_tiles"))
            if !licenseManager.isPro {
                ProBadge()
            }
        }
        SettingsCardBox {
            if !licenseManager.isPro {
                HStack(spacing: 12) {
                    Image(systemName: "globe.badge.chevron.backward")
                        .font(.system(size: 24))
                        .foregroundStyle(SettingsStyle.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(loc("apps.custom_tiles_title")).font(.system(size: 13, weight: .semibold))
                        Text(loc("apps.custom_tiles_subtitle"))
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(loc("apps.unlock_pro")) {
                        withAnimation { selectedTab = .license }
                    }
                }
                .padding(.vertical, 8)
            } else {
                let tiles = customTileManager.tiles
                if tiles.isEmpty {
                    SettingsNote(loc("apps.custom_tiles_empty"))
                        .padding(.vertical, 6)
                } else {
                    ForEach(Array(tiles.enumerated()), id: \.element.id) { index, tile in
                        if index > 0 { SettingsSeparator() }
                        HStack(spacing: 10) {
                            Image(nsImage: CustomTileRenderer.renderImage(symbol: tile.symbol, colorHex: tile.colorHex, size: 64))
                                .resizable().frame(width: 24, height: 24)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(tile.title).font(.system(size: 13, weight: .medium))
                                Text(tile.target).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                store.removeCustomTile(tile.id)
                            } label: {
                                Image(systemName: "trash").foregroundStyle(.red.opacity(0.8))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }

        SettingsSectionTitle(loc("section.scanned_folders"))
        SettingsCardBox {
            ForEach(AppScanner.defaultSources, id: \.self) { path in
                HStack(spacing: 8) {
                    Image(systemName: "folder").foregroundStyle(.secondary)
                    Text(path).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 6)
            }
            ForEach(customSources, id: \.self) { path in
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill").foregroundStyle(SettingsStyle.accent)
                    Text((path as NSString).abbreviatingWithTildeInPath)
                    Spacer()
                    Button { removeSource(path) } label: { Image(systemName: "minus.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.red)
                }
                .padding(.vertical, 6)
            }
            SettingsSeparator()
            HStack {
                Spacer()
                Button(loc("apps.add_folder")) { addSource() }
            }
            .padding(.vertical, 10)
        }
    }

    // MARK: Avancé

    @ViewBuilder
    private var advancedTab: some View {
        SettingsSectionTitle(loc("section.reorganization"))
        SettingsCardBox {
            SettingsRow(loc("advanced.sort_rule")) {
                SettingsMenuPicker(selection: $reorganizeRule, options: SortRule.allCases, title: \.title)
            }
            SettingsSeparator()
            SettingsRow(loc("advanced.folder_placement")) {
                SettingsMenuPicker(selection: $folderPlacement, options: FolderPlacement.allCases, title: \.title)
            }
            SettingsSeparator()
            SettingsRow(loc("advanced.sort_folder_contents")) { SettingsSwitch(isOn: $sortFolderContents) }
            SettingsSeparator()
            SettingsRow(loc("advanced.reorganize_now"), subtitle: loc("advanced.reorganize_subtitle")) {
                Button(loc("advanced.reorganize_button")) {
                    confirm(loc("advanced.reorganize_confirm_title"), loc("advanced.reorganize_confirm_msg")) {
                        store.reorganize(rule: reorganizeRule, placement: folderPlacement, sortFolderContents: sortFolderContents)
                    }
                }
            }
        }

        SettingsSectionTitle(loc("section.backup"))
        SettingsCardBox {
            SettingsRow(loc("advanced.backup_title"),
                        subtitle: loc("advanced.backup_subtitle"),
                        isPro: true,
                        isProUnlocked: licenseManager.isPro) {
                HStack(spacing: 8) {
                    Button(loc("advanced.import")) { importBackup() }
                    Button(loc("advanced.export")) { exportBackup() }
                }
            }
            SettingsSeparator()
            SettingsRow(loc("advanced.launchos_title"),
                        subtitle: !hasLaunchOSDB
                            ? loc("advanced.launchos_no_db")
                            : loc("advanced.launchos_subtitle")) {
                Button(loc("advanced.import")) {
                    confirm(loc("advanced.launchos_confirm_title"), loc("advanced.launchos_confirm_msg")) {
                        importLaunchOS()
                    }
                }
                .disabled(!hasLaunchOSDB)
            }
            SettingsSeparator()
            SettingsRow(loc("advanced.system_launchpad_title"),
                        subtitle: !hasSystemLPDB
                            ? loc("advanced.system_launchpad_no_db")
                            : loc("advanced.system_launchpad_subtitle")) {
                Button(loc("advanced.import")) {
                    confirm(loc("advanced.system_launchpad_confirm_title"), loc("advanced.system_launchpad_confirm_msg")) {
                        do {
                            let result = try BackupManager.importSystemLaunchpad(store: store)
                            message = loc("advanced.system_launchpad_imported", result.apps, result.folders)
                        } catch {
                            message = error.localizedDescription
                        }
                    }
                }
                .disabled(!hasSystemLPDB)
            }
        }

        SettingsSectionTitle(loc("section.reset"))
        SettingsCardBox {
            SettingsRow(loc("advanced.reset_title"), subtitle: loc("advanced.reset_subtitle")) {
                Button(loc("advanced.reset_button")) {
                    confirm(loc("advanced.reset_confirm_title"), loc("advanced.reset_confirm_msg")) {
                        store.resetLayout()
                    }
                }
            }
        }
    }

    // MARK: Licence

    @ViewBuilder
    private var licenseTab: some View {
        // En-tête de profil Compte Apple + statut Pro/Essai avec badge animé
        SettingsCardBox {
            VStack(spacing: 14) {
                // Portrait circulaire du compte Apple + Prénom + Sceau vérifié animé (Bleu Pro / Jaune Essai)
                VStack(spacing: 10) {
                    ZStack {
                        if let avatar = licenseManager.appleAccountAvatar {
                            Image(nsImage: avatar)
                                .resizable()
                                .interpolation(.high)
                                .scaledToFill()
                                .frame(width: 82, height: 82)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .strokeBorder(
                                            licenseManager.isPro
                                                ? (licenseManager.isProLifetime ? SettingsStyle.accent : Color(red: 1.00, green: 0.78, blue: 0.05))
                                                : Color.primary.opacity(0.18),
                                            lineWidth: 2.2
                                        )
                                )
                                .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
                        } else {
                            Circle()
                                .fill(
                                    licenseManager.isPro
                                        ? LinearGradient(colors: [SettingsStyle.accent, Color.purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                                        : LinearGradient(colors: [Color.gray.opacity(0.35), Color.gray.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                )
                                .frame(width: 82, height: 82)
                            Image(systemName: licenseManager.isPro ? "person.crop.circle.fill" : "lock.shield.fill")
                                .font(.system(size: 38))
                                .foregroundStyle(.white)
                        }
                    }

                    HStack(spacing: 7) {
                        Text(licenseManager.appleAccountFirstName.isEmpty ? "LaunchPad" : licenseManager.appleAccountFirstName)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.primary)

                        if licenseManager.isPro {
                            AnimatedVerifiedSealBadge(
                                isTrial: licenseManager.isTrialActive && !licenseManager.isProLifetime,
                                size: 22
                            )
                        }
                    }

                    HStack(spacing: 8) {
                        Text(
                            licenseManager.isProLifetime
                                ? loc("license.pro_unlocked")
                                : (licenseManager.isTrialActive ? loc("license.trial_active") : loc("license.free_version"))
                        )
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.secondary)

                        if licenseManager.isProLifetime {
                            HStack(spacing: 4) {
                                Text("PRO")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2.5)
                            .background(SettingsStyle.accent.opacity(0.16), in: Capsule())
                            .foregroundStyle(SettingsStyle.accent)
                        } else if licenseManager.isTrialActive {
                            SettingsTrialDaysBadgeView(countdown: licenseManager.countdown)
                        }
                    }

                    Text(
                        licenseManager.isProLifetime
                            ? loc("license.pro_desc")
                            : (licenseManager.isTrialActive ? loc("license.trial_desc") : loc("license.free_desc"))
                    )
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 460)
                }

                if !licenseManager.isProLifetime {
                    Button {
                        licenseManager.openGetProPage()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11.5, weight: .semibold))
                            Text(licenseManager.isTrialActive ? loc("license.pay_pro_lifetime") : loc("license.get_pro"))
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .foregroundStyle(Color.white)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            SettingsStyle.accent,
                                            Color.purple.opacity(0.88)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.white.opacity(0.25), lineWidth: 1.0)
                                )
                        )
                        .shadow(color: SettingsStyle.accent.opacity(0.22), radius: 8, y: 3)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }

        // Bandeau Compte à Rebours de l'Essai 7 Jours (si actif)
        if licenseManager.isTrialActive && !licenseManager.isProLifetime {
            SettingsTrialCountdownCard(
                licenseManager: licenseManager,
                countdown: licenseManager.countdown,
                onCancelTrial: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        licenseManager.cancelTrial()
                        licenseFeedback = nil
                    }
                }
            )
            .onAppear { LicenseManager.shared.beginCountdownObservation() }
            .onDisappear { LicenseManager.shared.endCountdownObservation() }
        } else if !licenseManager.isPro && !licenseManager.hasUsedTrial {
            // Proposition de démarrer l'essai 7 jours
            SettingsCardBox {
                HStack(spacing: 14) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.orange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc("license.trial_banner_title"))
                            .font(.system(size: 13.5, weight: .semibold))
                        Text(loc("license.trial_banner_sub"))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            licenseManager.startSevenDayTrial()
                        }
                    } label: {
                        Text(loc("license.activate_trial_short"))
                            .font(.system(size: 12.5, weight: .bold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
                .padding(.vertical, 10)
            }
        }

        // Formulaire d'activation ou gestion
        SettingsCardBox {
            VStack(alignment: .leading, spacing: 12) {
                Text(licenseManager.isProLifetime ? loc("license.manage_title") : loc("license.activate_title"))
                    .font(.system(size: 14, weight: .semibold))

                if licenseManager.isProLifetime {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(loc("license.active_key"))
                                .font(.system(size: 13))
                            Text(licenseManager.licenseKey.isEmpty ? loc("license.active_status") : licenseManager.licenseKey)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        HStack(spacing: 8) {
                            Button(loc("license.deactivate_button")) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    licenseManager.deactivate()
                                    licenseFeedback = nil
                                }
                            }
                            .controlSize(.small)

                            Button {
                                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
                                withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) {
                                    showProCelebration = true
                                }
                            } label: {
                                Label(loc("license.resee_animation"), systemImage: "sparkles")
                            }
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    HStack(spacing: 10) {
                        TextField(loc("license.placeholder"), text: $licenseInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13, design: .monospaced))
                            .onSubmit { validateCurrentLicense() }

                        Button(loc("license.validate_button")) {
                            validateCurrentLicense()
                        }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .tint(SettingsStyle.accent)
                    }

                    // Retour visuel animé (erreur ou succès)
                    if let feedback = licenseFeedback {
                        HStack(spacing: 8) {
                            Image(systemName: feedback.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(feedback.isError ? Color.red : Color.green)
                                .font(.system(size: 14))
                            Text(feedback.message)
                                .font(.system(size: 12.5))
                                .foregroundStyle(feedback.isError ? Color.red : Color.green)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            (feedback.isError ? Color.red : Color.green).opacity(0.10),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            .padding(.vertical, 14)
        }

        // Tableau comparatif Gratuit vs Pro
        SettingsCardBox {
            VStack(alignment: .leading, spacing: 10) {
                Text(loc("license.features_comparison"))
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.bottom, 2)

                featureRow(title: loc("license.feature_themes"), statusFree: loc("license.status_included"), statusPro: loc("license.status_included"))
                SettingsSeparator()
                featureRow(title: loc("license.feature_liquid_glass"), statusFree: loc("license.status_locked"), statusPro: loc("license.status_unlocked"), isProHighlight: true)
                SettingsSeparator()
                featureRow(title: loc("license.feature_transparent_icons"), statusFree: loc("license.status_locked"), statusPro: loc("license.status_unlocked"), isProHighlight: true)
                SettingsSeparator()
                featureRow(title: loc("license.feature_uninstall"), statusFree: loc("license.status_locked"), statusPro: loc("license.status_unlocked"), isProHighlight: true)
                SettingsSeparator()
                featureRow(title: loc("license.feature_touchid"), statusFree: loc("license.status_locked"), statusPro: loc("license.status_unlocked"), isProHighlight: true)
                SettingsSeparator()
                featureRow(title: loc("license.feature_tinted"), statusFree: loc("license.status_locked"), statusPro: loc("license.status_unlocked"), isProHighlight: true)
                SettingsSeparator()
                featureRow(title: loc("license.feature_custom_tiles"), statusFree: loc("license.status_locked"), statusPro: loc("license.status_unlocked"), isProHighlight: true)
                SettingsSeparator()
                featureRow(title: loc("license.feature_backup"), statusFree: loc("license.status_locked"), statusPro: loc("license.status_unlocked"))
                SettingsSeparator()
                featureRow(title: loc("license.feature_auto_sort"), statusFree: loc("license.status_manual"), statusPro: loc("license.status_auto"))
                SettingsSeparator()
                featureRow(title: loc("license.feature_custom_folders"), statusFree: loc("license.status_default"), statusPro: loc("license.status_unlimited"))
            }
            .padding(.vertical, 14)
        }

        // Note de test pour prototype
        SettingsCardBox {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(SettingsStyle.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(loc("license.demo_code_title"))
                        .font(.system(size: 13, weight: .semibold))
                    Text(loc("license.demo_code_desc"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 12)
        }

        // Section Support & Communauté Discord
        SettingsCardBox {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(red: 0.35, green: 0.40, blue: 0.95).opacity(0.18))
                        .frame(width: 34, height: 34)
                    Image("DiscordLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 22, height: 17)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(loc("license.discord_title"))
                        .font(.system(size: 13, weight: .semibold))
                    Text(loc("license.discord_sub"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    if let url = URL(string: "https://discord.gg/VG9rgMjBMf") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image("DiscordLogoWhite")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 14, height: 11)
                        Text(loc("license.join_discord"))
                            .fontWeight(.semibold)
                    }
                    .font(.system(size: 12))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.35, green: 0.40, blue: 0.95))
            }
            .padding(.vertical, 12)
        }
    }

    private func tintColor(for key: String) -> Color {
        switch key {
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

    private func featureRow(title: String, statusFree: String, statusPro: String, isProHighlight: Bool = false) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(isProHighlight ? Color.primary : Color.secondary)
            Spacer()
            Text(licenseManager.isPro ? statusPro : statusFree)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(licenseManager.isPro ? (isProHighlight ? SettingsStyle.accent : Color.green) : Color.secondary)
        }
    }

    private func validateCurrentLicense() {
        let codeToValidate = licenseInput
        Task { @MainActor in
            let result = await licenseManager.activateLicenseOnline(code: codeToValidate)
            withAnimation(.easeInOut(duration: 0.25)) {
                licenseFeedback = (isError: !result.success, message: result.message)
                if result.success {
                    licenseInput = ""
                    NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) {
                        showProCelebration = true
                    }
                }
            }
        }
    }

    private func handleThemeSelection(_ theme: AppTheme) {
        if theme.isProOnly && !licenseManager.isPro {
            confirm(
                loc("pro_alert.theme_title"),
                loc("pro_alert.theme_msg")
            ) {
                withAnimation { selectedTab = .license }
            }
            return
        }
        withAnimation(.easeInOut(duration: 0.25)) {
            backgroundStyle = theme
        }
    }

    private func handleLogoSelection(_ logo: AppLogo) {
        if logo.isProOnly && !licenseManager.isPro {
            confirm(
                loc("pro_alert.logo_title", logo.title),
                loc("pro_alert.logo_msg")
            ) {
                withAnimation { selectedTab = .license }
            }
            return
        }
        withAnimation(.easeOut(duration: 0.15)) {
            appLogo = logo
            if let img = logo.image {
                NSApp.applicationIconImage = img
            }
        }
    }

    // MARK: À propos

    @ViewBuilder
    private var aboutTab: some View {
        // Section En-tête de l'application
        SettingsCardBox {
            HStack(spacing: 16) {
                Image(nsImage: appLogo.image ?? NSApp.applicationIconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("LaucnhPad")
                            .font(.system(size: 19, weight: .bold))
                        if licenseManager.isPro {
                            AnimatedVerifiedSealBadge(
                                isTrial: licenseManager.isTrialActive && !licenseManager.isProLifetime,
                                size: 19
                            )
                        }
                    }

                    HStack(spacing: 6) {
                        Text(loc("about.installed_version"))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Text("v\(UpdateManager.shared.currentAppVersion)")
                            .font(.system(size: 12.5, weight: .semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.08))
                            .clipShape(Capsule())
                    }

                    Text(loc("about.created_by"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 16)
        }

        // Section Mise à jour
        SettingsUpdateCardView()

        // Section Guide & Tutoriel
        SettingsCardBox {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.blue.opacity(0.16))
                        .frame(width: 32, height: 32)
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.blue)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(loc("about.tutorial_title"))
                        .font(.system(size: 14, weight: .semibold))
                    Text(loc("about.tutorial_desc"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Button {
                    NotificationCenter.default.post(name: .closeSettings, object: nil)
                    NotificationCenter.default.post(name: .openTutorial, object: nil)
                } label: {
                    Label(loc("about.launch_tutorial"), systemImage: "play.circle.fill")
                        .font(.system(size: 12.5, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                }
                .buttonStyle(.bordered)
            }
            .padding(.vertical, 14)
        }

        // Section Communauté & Support Discord
        SettingsCardBox {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color(red: 0.35, green: 0.40, blue: 0.95).opacity(0.18))
                        .frame(width: 34, height: 34)
                    Image("DiscordLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 22, height: 17)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(loc("about.discord_title"))
                            .font(.system(size: 14, weight: .semibold))
                        HStack(spacing: 4) {
                            Circle().fill(Color.green).frame(width: 6, height: 6)
                            Text(loc("about.online_badge"))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.green)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.12))
                        .clipShape(Capsule())
                    }
                    Text(loc("about.discord_desc"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Button {
                    if let url = URL(string: "https://discord.gg/VG9rgMjBMf") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image("DiscordLogoWhite")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 14, height: 11)
                        Text(loc("license.join_discord"))
                            .fontWeight(.semibold)
                    }
                    .font(.system(size: 12.5))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.35, green: 0.40, blue: 0.95))
            }
            .padding(.vertical, 14)
        }

        // Section Mode Administrateur & Tests
        SettingsCardBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(adminManager.isAuthenticated ? Color.green.opacity(0.16) : Color.orange.opacity(0.16))
                            .frame(width: 32, height: 32)
                        Image(systemName: adminManager.isAuthenticated ? "checkmark.shield.fill" : "lock.shield.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(adminManager.isAuthenticated ? Color.green : Color.orange)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(loc("about.admin_title"))
                                .font(.system(size: 14, weight: .semibold))
                            if adminManager.isAuthenticated {
                                HStack(spacing: 4) {
                                    Circle().fill(Color.green).frame(width: 6, height: 6)
                                    Text(loc("about.admin_unlocked_badge"))
                                        .font(.system(size: 10, weight: .bold))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2.5)
                                .background(Color.green.opacity(0.16))
                                .foregroundStyle(.green)
                                .clipShape(Capsule())
                            }
                        }
                        Text(adminManager.isAuthenticated ? loc("about.admin_connected_sub", adminManager.authenticatedUser) : loc("about.admin_locked_sub"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }

                SettingsSeparator()
                    .padding(.vertical, 2)

                if adminManager.isAuthenticated {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(loc("about.admin_active_desc"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineSpacing(2)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.035))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                        HStack(spacing: 12) {
                            Button {
                                adminManager.openTestCenter()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "hammer.fill")
                                    Text(loc("about.open_test_menu"))
                                        .fontWeight(.semibold)
                                }
                                .font(.system(size: 12.5))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(SettingsStyle.accent)

                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    adminManager.logout()
                                    adminUsername = ""
                                    adminPassword = ""
                                    adminErrorMessage = nil
                                }
                            } label: {
                                Text(loc("about.logout"))
                                    .font(.system(size: 12.5))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .bottom, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(loc("about.username"))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                TextField("admin", text: $adminUsername)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(minWidth: 130)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(loc("about.password"))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                HStack {
                                    if isPasswordVisible {
                                        TextField("••••••", text: $adminPassword)
                                            .textFieldStyle(.roundedBorder)
                                    } else {
                                        SecureField("••••••", text: $adminPassword)
                                            .textFieldStyle(.roundedBorder)
                                    }
                                    Button {
                                        isPasswordVisible.toggle()
                                    } label: {
                                        Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .frame(minWidth: 130)
                            }

                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    let res = adminManager.authenticate(username: adminUsername, password: adminPassword)
                                    if res.success {
                                        adminErrorMessage = nil
                                        adminPassword = ""
                                        adminManager.openTestCenter()
                                    } else {
                                        adminErrorMessage = res.message
                                    }
                                }
                            } label: {
                                Label(loc("about.login"), systemImage: "key.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(SettingsStyle.accent)
                        }

                        if let adminErrorMessage {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.red)
                                Text(adminErrorMessage)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                            .padding(.top, 2)
                        }

                        HStack(spacing: 6) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Text(LocalizedStringKey(loc("about.default_creds")))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 2)
                    }
                }
            }
            .padding(.vertical, 16)
        }

        // Section Quitter
        SettingsCardBox {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.red.opacity(0.14))
                        .frame(width: 32, height: 32)
                    Image(systemName: "power")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.red)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(loc("about.quit_title"))
                        .font(.system(size: 14, weight: .semibold))
                    Text(loc("about.quit_subtitle"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Button(role: .destructive) {
                    NSApp.terminate(nil)
                } label: {
                    Label(loc("about.quit_button"), systemImage: "power")
                        .font(.system(size: 12.5, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.red.opacity(0.88))
                .keyboardShortcut("q", modifiers: .command)
            }
            .padding(.vertical, 14)
        }
    }

    // MARK: Actions

    private func applySortChoice(_ choice: String) {
        if choice == "launchos" {
            confirm(loc("advanced.launchos_confirm_title"), loc("advanced.launchos_confirm_msg"),
                    onCancel: { sortChoice = "custom" }) {
                importLaunchOS()
            }
            return
        }
        guard choice != "custom", let rule = SortRule(rawValue: choice) else { return }
        confirm(loc("advanced.sort_confirm_title", rule.title), loc("advanced.sort_confirm_msg"), onCancel: { sortChoice = "custom" }) {
            reorganizeRule = rule
            store.reorganize(rule: rule, placement: folderPlacement, sortFolderContents: sortFolderContents)
        }
    }

    private func importLaunchOS() {
        do {
            let result = try BackupManager.importLaunchOS(store: store)
            message = loc("advanced.launchos_imported", result.apps, result.folders)
        } catch {
            sortChoice = "custom"
            message = error.localizedDescription
        }
    }

    /// Feuille attachée à la fenêtre des réglages : elle reste visible même au-dessus du Launchpad.
    private func confirm(_ title: String, _ text: String, onCancel: (() -> Void)? = nil, action: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: loc("dialog.confirm"))
        alert.addButton(withTitle: loc("dialog.cancel"))
        let settingsWindow = NSApp.keyWindow ?? NSApp.windows.first { $0.title == loc("about.window_title") && $0.isVisible }
        if let settingsWindow {
            alert.beginSheetModal(for: settingsWindow) { response in
                if response == .alertFirstButtonReturn { action() } else { onCancel?() }
            }
        } else if alert.runModal() == .alertFirstButtonReturn {
            action()
        } else {
            onCancel?()
        }
    }

    private func addSource() {
        guard let url = BackupPanels.chooseFolder() else { return }
        let path = url.standardizedFileURL.path
        guard !AppScanner.defaultSources.map(AppScanner.expand).contains(path), !customSources.contains(path) else { return }
        customSources.append(path)
        Prefs.defaults.set(customSources, forKey: PrefKey.customSources)
        store.refresh()
    }

    private func removeSource(_ path: String) {
        customSources.removeAll { $0 == path }
        Prefs.defaults.set(customSources, forKey: PrefKey.customSources)
        store.refresh()
    }

    private func exportBackup() {
        if !licenseManager.isPro {
            confirm(loc("pro_alert.backup_title"),
                    loc("pro_alert.backup_msg")) {
                withAnimation { selectedTab = .license }
            }
            return
        }
        guard let url = BackupPanels.chooseExportURL() else { return }
        do {
            try BackupManager.export(store: store, to: url)
            message = loc("advanced.backup_exported", url.path)
            AppNotificationManager.shared.sendBackupCompletedNotification(isExport: true)
        } catch {
            message = error.localizedDescription
        }
    }

    private func importBackup() {
        if !licenseManager.isPro {
            confirm(loc("pro_alert.backup_title"),
                    loc("pro_alert.backup_msg")) {
                withAnimation { selectedTab = .license }
            }
            return
        }
        guard let url = BackupPanels.chooseImportURL() else { return }
        do {
            let backup = try BackupManager.read(from: url)
            confirm(loc("advanced.backup_confirm_title"), loc("advanced.backup_confirm_msg")) {
                BackupManager.restore(backup, store: store)
                customSources = Prefs.customSources
                message = loc("advanced.backup_restored")
                AppNotificationManager.shared.sendBackupCompletedNotification(isExport: false)
            }
        } catch {
            message = error.localizedDescription
        }
    }
}

// MARK: - Enregistreur de raccourci

struct ShortcutRecorder: View {
    @AppStorage(PrefKey.hotKeyDisplay) private var display = "⌃ Espace"
    @AppStorage(PrefKey.hotKeyCode) private var hotKeyCode: Int = 49
    @ObservedObject private var locManager = LocalizationManager.shared
    @State private var recording = false
    @State private var monitor: Any?

    private var localizedDisplay: String {
        let _ = locManager.effectiveLanguageCode
        guard hotKeyCode == 49 else { return display }
        let spaceTokens = ["Espace", "Space", "Espacio", "Leertaste", "Spazio", "Espaço"]
        let spaceLabel = loc("hotkey.space")
        for token in spaceTokens {
            if display == token { return spaceLabel }
            if display.hasSuffix(" " + token) {
                return String(display.dropLast(token.count)) + spaceLabel
            }
        }
        return display
    }

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Text(recording ? loc("about.shortcut_recording") : localizedDisplay)
                .monospaced()
                .frame(minWidth: 140)
        }
        .onDisappear {
            if recording || monitor != nil {
                stop()
            }
        }
    }

    private func start() {
        recording = true
        HotKeyManager.shared.unregister()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil }
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            let isFunctionKey = ShortcutFormatter.functionKeys[event.keyCode] != nil
            guard isFunctionKey || !flags.intersection([.command, .option, .control]).isEmpty else {
                NSSound.beep()
                return nil
            }
            let symbols = ShortcutFormatter.symbols(for: flags)
            display = (symbols.isEmpty ? "" : symbols + " ") + ShortcutFormatter.keyName(for: event)
            Prefs.defaults.set(Int(event.keyCode), forKey: PrefKey.hotKeyCode)
            Prefs.defaults.set(Int(ShortcutFormatter.carbonModifiers(from: flags)), forKey: PrefKey.hotKeyModifiers)
            stop()
            return nil
        }
    }

    private func stop() {
        guard recording || monitor != nil else { return }
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        NotificationCenter.default.post(name: .launchpadHotKeyChanged, object: nil)
    }
}

extension Notification.Name {
    static let launchpadHotKeyChanged = Notification.Name("LaunchpadHotKeyChanged")
}

// MARK: - Composants (style LaunchOS)

private struct SettingsSectionTitle: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title)
            .font(.system(size: 14, weight: .semibold))
            .padding(.leading, 16)
            .padding(.top, 14)
            .padding(.bottom, -2)
    }
}

private struct SettingsCardBox<Content: View>: View {
    @AppStorage(PrefKey.backgroundStyle) private var theme: BackgroundStyle = .liquidGlass
    let content: () -> Content
    init(@ViewBuilder content: @escaping () -> Content) { self.content = content }
    var body: some View {
        Group {
            if theme == .liquidGlass {
                VStack(alignment: .leading, spacing: 0, content: content)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .liquidGlassCard(cornerRadius: 15, interactive: false)
            } else {
                VStack(alignment: .leading, spacing: 0, content: content)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        cardBackground
                            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    }
                    .overlay {
                        cardStroke
                    }
            }
        }
    }

    @ViewBuilder
    private var cardBackground: some View {
        switch theme {
        case .dark:
            Color.white.opacity(0.045)
        case .light:
            Color.white.opacity(0.72)
        case .liquidGlass:
            ZStack {
                Color.white.opacity(0.05)
                LinearGradient(
                    colors: [Color.white.opacity(0.10), Color.white.opacity(0.02), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }

    @ViewBuilder
    private var cardStroke: some View {
        switch theme {
        case .dark:
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        case .light:
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
        case .liquidGlass:
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.24), Color.white.opacity(0.08), Color.white.opacity(0.03), Color.white.opacity(0.14)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }
}

/// Badge visuel discret et lisible indiquant une option réservée à la version Pro
struct ProBadge: View {
    var isUnlocked: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "sparkles")
                .font(.system(size: 8, weight: .bold))
            Text("PRO")
                .font(.system(size: 9, weight: .bold))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .foregroundStyle(SettingsStyle.accent)
        .background(
            ZStack {
                Capsule().fill(.ultraThinMaterial)
                Capsule().fill(SettingsStyle.accent.opacity(0.12))
            }
        )
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [SettingsStyle.accent.opacity(0.6), SettingsStyle.accent.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        )
    }
}

/// Bouton de sélection d'un thème (Sombre, Clair, Liquid Glass)
struct ThemeCardButton: View {
    let theme: AppTheme
    let isSelected: Bool
    let isProUnlocked: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var hostColorScheme
    private static let clairSunColor = Color(.sRGB, red: 1.0, green: 0.62, blue: 0.0, opacity: 1.0)
    private static let liquidGlassLightInk = Color(.sRGB, red: 0.13, green: 0.11, blue: 0.25, opacity: 0.94)
    private static let liquidGlassLightAccent = Color(.sRGB, red: 0.48, green: 0.24, blue: 0.92, opacity: 1.0)

    private var isHostLight: Bool {
        hostColorScheme == .light
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    previewFill
                        .frame(height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            previewStroke
                        }
                        .shadow(
                            color: (theme == .liquidGlass && isHostLight)
                                ? Color(red: 0.36, green: 0.28, blue: 0.85).opacity(0.14)
                                : Color.clear,
                            radius: 5,
                            y: 2
                        )
                        .overlay {
                            VStack(spacing: 5) {
                                Image(systemName: theme.symbol)
                                    .font(.system(size: 20))
                                    .symbolRenderingMode(.monochrome)
                                    .foregroundStyle(cardSymbolColor)
                                    .drawingGroup()
                                Text(theme.title)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(cardLabelColor)
                            }
                        }

                    if theme.isProOnly && !isProUnlocked {
                        ProBadge()
                            .padding(6)
                    }
                }

                HStack(spacing: 6) {
                    Circle()
                        .fill(isSelected ? SettingsStyle.accent : (isHostLight ? Color.black.opacity(0.18) : Color.primary.opacity(0.16)))
                        .frame(width: 14, height: 14)
                        .overlay(
                            Circle()
                                .fill(Color.white)
                                .frame(width: 5.5, height: 5.5)
                                .opacity(isSelected ? 1 : 0)
                        )
                    Text(theme.title)
                        .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(8)
            .background(
                isSelected ? SettingsStyle.accent.opacity(0.08) : Color.clear,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? SettingsStyle.accent.opacity(0.6) : Color.clear, lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var cardSymbolColor: Color {
        switch theme {
        case .dark:
            return Color.white.opacity(0.95)
        case .light:
            return Self.clairSunColor
        case .liquidGlass:
            return isHostLight ? Self.liquidGlassLightAccent : SettingsStyle.accent
        }
    }

    private var cardLabelColor: Color {
        switch theme {
        case .dark:
            return Color.white.opacity(0.95)
        case .light:
            return Color(.sRGB, red: 0.10, green: 0.10, blue: 0.12, opacity: 0.88)
        case .liquidGlass:
            return isHostLight ? Self.liquidGlassLightInk : Color.white.opacity(0.94)
        }
    }

    @ViewBuilder
    private var previewFill: some View {
        switch theme {
        case .dark:
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.05, blue: 0.07), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
        case .light:
            LinearGradient(
                colors: [Color.white.opacity(0.95), Color(white: 0.90)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .liquidGlass:
            if isHostLight {
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(red: 0.82, green: 0.78, blue: 0.97),
                            Color(red: 0.72, green: 0.80, blue: 0.99),
                            Color(red: 0.84, green: 0.88, blue: 0.99)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.50), location: 0.0),
                            .init(color: Color.white.opacity(0.08), location: 0.45),
                            .init(color: Color.white.opacity(0.28), location: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            } else {
                LinearGradient(
                    colors: [
                        Color.primary.opacity(0.10),
                        Color.purple.opacity(0.14),
                        Color.blue.opacity(0.10),
                        Color.primary.opacity(0.04)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }

    @ViewBuilder
    private var previewStroke: some View {
        switch theme {
        case .dark:
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
        case .light:
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.black.opacity(0.12), lineWidth: 1)
        case .liquidGlass:
            if isHostLight {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color(red: 0.48, green: 0.34, blue: 0.92).opacity(0.42),
                                Color.white.opacity(0.85),
                                Color(red: 0.30, green: 0.50, blue: 0.96).opacity(0.38)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.3
                    )
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.55), Color.white.opacity(0.1), Color.white.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
            }
        }
    }
}

private struct SettingsRow<Control: View>: View {
    let title: String
    var subtitle: String?
    var info: String?
    var isPro: Bool = false
    var isProUnlocked: Bool = false
    let control: () -> Control

    init(_ title: String, subtitle: String? = nil, info: String? = nil, isPro: Bool = false, isProUnlocked: Bool = false, @ViewBuilder control: @escaping () -> Control) {
        self.title = title
        self.subtitle = subtitle
        self.info = info
        self.isPro = isPro
        self.isProUnlocked = isProUnlocked
        self.control = control
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title).font(.system(size: 14))
                    if isPro && !isProUnlocked {
                        ProBadge()
                    }
                    if let info {
                        Image(systemName: "info.circle")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .help(info)
                    }
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            control()
        }
        .padding(.vertical, 12)
    }
}

private struct SettingsSeparator: View {
    var body: some View { Rectangle().fill(SettingsStyle.separator).frame(height: 1) }
}

private struct SettingsSwitch: View {
    @Binding var isOn: Bool
    var body: some View {
        Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch).tint(SettingsStyle.accent)
    }
}

private struct SettingsMenuPicker<Value: Hashable & Identifiable>: View {
    @Binding var selection: Value
    let options: [Value]
    let title: KeyPath<Value, String>
    var body: some View {
        Picker("", selection: $selection) {
            ForEach(options) { Text($0[keyPath: title]).tag($0) }
        }
        .labelsHidden()
        .fixedSize()
    }
}

/// Boutons radio ronds violets (comme « Pages / Défilement » dans LaunchOS).
private struct SettingsRadioGroup<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [Value]
    let title: KeyPath<Value, String>
    var body: some View {
        HStack(spacing: 18) {
            ForEach(options, id: \.self) { option in
                Button { selection = option } label: {
                    HStack(spacing: 7) {
                        RadioDot(selected: selection == option)
                        Text(option[keyPath: title]).font(.system(size: 14))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct RadioDot: View {
    let selected: Bool
    var body: some View {
        ZStack {
            Circle().fill(selected ? SettingsStyle.accent : Color.primary.opacity(0.16))
            if selected { Circle().fill(Color.white).frame(width: 6, height: 6) }
        }
        .frame(width: 17, height: 17)
        .animation(.easeOut(duration: 0.12), value: selected)
    }
}

/// Champ numérique encadré avec flèches (comme « 7 ⌃⌄ × 5 ⌃⌄ » dans LaunchOS).
private struct SettingsNumberField: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var body: some View {
        HStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 14))
                .monospacedDigit()
                .frame(minWidth: 30)
            Stepper("", value: $value, in: range).labelsHidden()
        }
        .padding(.leading, 8)
        .padding(.trailing, 2)
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.primary.opacity(0.2)))
    }
}

private struct SettingsSliderRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double?
    var isPercentage: Bool = false
    var onEditingChanged: ((Bool) -> Void)?

    init(_ title: String, subtitle: String? = nil, value: Binding<Double>, range: ClosedRange<Double>, step: Double? = nil, isPercentage: Bool = false, onEditingChanged: ((Bool) -> Void)? = nil) {
        self.title = title
        self.subtitle = subtitle
        self._value = value
        self.range = range
        self.step = step
        self.isPercentage = isPercentage
        self.onEditingChanged = onEditingChanged
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14))
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Group {
                if let step {
                    Slider(value: $value, in: range, step: step, onEditingChanged: onEditingChanged ?? { _ in })
                } else {
                    Slider(value: $value, in: range, onEditingChanged: onEditingChanged ?? { _ in })
                }
            }
            .tint(SettingsStyle.accent)
            .frame(width: 180)
            if isPercentage {
                Text("\(Int(round(value * 100))) %")
                    .monospacedDigit().foregroundStyle(.secondary).frame(width: 48, alignment: .trailing)
            } else {
                Text(value, format: .number.precision(.fractionLength(2)))
                    .monospacedDigit().foregroundStyle(.secondary).frame(width: 38, alignment: .trailing)
            }
        }
        .padding(.vertical, 12)
    }
}

private struct SettingsNote: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SettingsWarning: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 12)).foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 10)
    }
}

/// Vignette du mode d'affichage (Plein écran / Fenêtre) comme dans LaunchOS.
private struct DisplayModeOption: View {
    let mode: DisplayMode
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 9) {
                thumbnail
                    .frame(width: 118, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .padding(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(selected ? SettingsStyle.accent : Color.clear, lineWidth: 2.5)
                    )
                Text(mode.title).font(.system(size: 14))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: selected)
    }

    private var thumbnail: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.16, green: 0.12, blue: 0.55), Color(red: 0.38, green: 0.35, blue: 0.92),
                                    Color(red: 0.10, green: 0.08, blue: 0.35)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            if mode == .fullScreen {
                dots(rows: 3, columns: 6, size: 9, spacing: 7)
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.black.opacity(0.35))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.white.opacity(0.25)))
                    .frame(width: 80, height: 50)
                    .overlay(dots(rows: 3, columns: 5, size: 6, spacing: 5))
            }
        }
    }

    private func dots(rows: Int, columns: Int, size: CGFloat, spacing: CGFloat) -> some View {
        VStack(spacing: spacing) {
            ForEach(0..<rows, id: \.self) { _ in
                HStack(spacing: spacing) {
                    ForEach(0..<columns, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                            .fill(Color.white.opacity(0.55))
                            .frame(width: size, height: size)
                    }
                }
            }
        }
    }
}

/// Vignette d'un logo de l'app (le logo actif est entouré avec la couleur d'accent, les logos Pro verrouillés affichent un cadenas).
private struct AppLogoOption: View {
    let logo: AppLogo
    let selected: Bool
    let isProUnlocked: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let image = logo.image {
                            Image(nsImage: image)
                                .resizable()
                                .interpolation(.high)
                        } else {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(Color.primary.opacity(0.08))
                        }
                    }
                    .frame(width: 58, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .shadow(color: Color.black.opacity(selected ? 0.35 : (isHovered ? 0.25 : 0.12)), radius: selected ? 6 : 4, y: 2)
                    .padding(3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(
                                selected ? SettingsStyle.accent : (isHovered ? Color.white.opacity(0.3) : Color.clear),
                                lineWidth: selected ? 2.5 : 1
                            )
                    )

                    if logo.isProOnly && !isProUnlocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(4.5)
                            .background(Circle().fill(Color.black.opacity(0.75)))
                            .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 0.5))
                            .offset(x: 2, y: -2)
                    }
                }

                Text(logo.title)
                    .font(.system(size: 11, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? SettingsStyle.accent : Color.primary.opacity(0.85))
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: selected)
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}

// MARK: - Animation Pop-Up de Célébration Pro

private struct CelebrationParticle: Identifiable {
    let id = UUID()
    let angle: Double
    let distance: CGFloat
    let size: CGFloat
    let color: Color
    let symbol: String
    let rotation: Double
    let endScale: CGFloat
}

struct ProCelebrationPopup: View {
    let onDismiss: () -> Void

    @State private var appear = false
    @State private var logoBounce = false
    @State private var particlesExploded = false
    @State private var logoPulse = false
    @State private var ringRotation: Double = 0
    @AppStorage(PrefKey.appLogo) private var appLogo: AppLogo = .noir

    private static let particles: [CelebrationParticle] = {
        let colors: [Color] = [
            Color(red: 1.0, green: 0.84, blue: 0.20),  // Or étincelant
            Color(red: 0.68, green: 0.45, blue: 1.0),   // Violet royal
            Color(red: 0.25, green: 0.70, blue: 1.0),   // Cyan azur
            Color(red: 1.0, green: 0.38, blue: 0.65),   // Rose vif
            Color(red: 0.30, green: 0.88, blue: 0.65),  // Émeraude
            Color.white
        ]
        let symbols = ["sparkle", "star.fill", "circle.fill", "diamond.fill"]
        return (0..<36).map { i in
            let angle = (Double(i) / 36.0) * (2 * .pi) + Double.random(in: -0.15...0.15)
            let distance = CGFloat.random(in: 110...220)
            let size = CGFloat.random(in: 6...13)
            let color = colors[i % colors.count]
            let symbol = symbols[i % symbols.count]
            let rotation = Double.random(in: 0...360)
            let endScale = CGFloat.random(in: 0.8...1.25)
            return CelebrationParticle(angle: angle, distance: distance, size: size, color: color, symbol: symbol, rotation: rotation, endScale: endScale)
        }
    }()

    var body: some View {
        ZStack {
            // Arrière-plan assombri et flouté
            Color.black.opacity(0.65)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }

            // Explosion radiale de particules et confettis
            ZStack {
                ForEach(Self.particles) { p in
                    Group {
                        if p.symbol == "sparkle" {
                            Image(systemName: "sparkle")
                                .font(.system(size: p.size, weight: .bold))
                                .foregroundStyle(p.color)
                        } else if p.symbol == "star.fill" {
                            Image(systemName: "star.fill")
                                .font(.system(size: p.size))
                                .foregroundStyle(p.color)
                        } else if p.symbol == "diamond.fill" {
                            Image(systemName: "diamond.fill")
                                .font(.system(size: p.size))
                                .foregroundStyle(p.color)
                        } else {
                            Circle()
                                .fill(p.color)
                                .frame(width: p.size, height: p.size)
                        }
                    }
                    .rotationEffect(.degrees(p.rotation + (particlesExploded ? 45 : 0)))
                    .offset(
                        x: particlesExploded ? cos(p.angle) * p.distance : 0,
                        y: particlesExploded ? sin(p.angle) * p.distance : 0
                    )
                    .scaleEffect(particlesExploded ? p.endScale : 0.1)
                    .opacity(particlesExploded ? 0.95 : 0.0)
                }
            }
            .allowsHitTesting(false)

            // Carte centrale Pop-Up Liquid Glass
            VStack(spacing: 0) {
                // Section Logo de l'application & Rayonnement
                ZStack {
                    // Halo lumineux respirant
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.80, blue: 0.30).opacity(0.55),
                                    Color(red: 0.60, green: 0.35, blue: 0.95).opacity(0.40),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 15,
                                endRadius: 85
                            )
                        )
                        .frame(width: 170, height: 170)
                        .scaleEffect(logoPulse ? 1.15 : 0.92)
                        .opacity(logoPulse ? 0.95 : 0.65)

                    // Anneau scintillant rotatif
                    Circle()
                        .strokeBorder(
                            AngularGradient(
                                gradient: Gradient(colors: [
                                    Color.clear,
                                    Color(red: 1.0, green: 0.85, blue: 0.35).opacity(0.8),
                                    Color.purple.opacity(0.8),
                                    Color.cyan.opacity(0.8),
                                    Color.clear
                                ]),
                                center: .center
                            ),
                            lineWidth: 2.5
                        )
                        .frame(width: 110, height: 110)
                        .rotationEffect(.degrees(ringRotation))

                    // Logo officiel de l'application
                    Group {
                        if let img = appLogo.image ?? NSApp.applicationIconImage {
                            Image(nsImage: img)
                                .resizable()
                                .interpolation(.high)
                                .aspectRatio(contentMode: .fit)
                        } else {
                            Image(systemName: "app.gift.fill")
                                .font(.system(size: 46))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 19, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.90),
                                        Color(red: 1.0, green: 0.84, blue: 0.40).opacity(0.65),
                                        Color.white.opacity(0.20)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )
                    .shadow(color: Color.black.opacity(0.45), radius: 18, x: 0, y: 9)
                    .scaleEffect(logoBounce ? 1.0 : 0.35)
                    .rotationEffect(.degrees(logoBounce ? 0 : -14))
                }
                .padding(.top, 22)
                .padding(.bottom, 10)

                // Badge vérifié animé
                HStack(spacing: 6) {
                    AnimatedVerifiedSealBadge(isTrial: false, size: 15)
                    Text(loc("celebration.badge"))
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .tracking(1.4)
                }
                .foregroundStyle(Color(red: 0.82, green: 0.58, blue: 1.00))
                .padding(.horizontal, 12)
                .padding(.vertical, 4.5)
                .background(SettingsStyle.accent.opacity(0.20), in: Capsule())
                .overlay(Capsule().stroke(Color(red: 0.72, green: 0.38, blue: 0.94).opacity(0.52), lineWidth: 0.9))
                .padding(.bottom, 8)

                // Titre percutant
                Text(loc("celebration.title"))
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 4)

                Text(loc("celebration.subtitle"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)

                // Liste des fonctionnalités débloquées
                VStack(spacing: 7) {
                    proFeatureRow(symbol: "sparkles", color: .purple, title: loc("celebration.feature1"), desc: loc("theme.desc.liquidGlass"))
                    proFeatureRow(symbol: "lock.shield.fill", color: .green, title: loc("celebration.feature3"), desc: loc("touchid.auth_required"))
                    proFeatureRow(symbol: "trash.fill", color: .orange, title: loc("celebration.feature4"), desc: loc("uninstall.desc"))
                    proFeatureRow(symbol: "globe", color: .blue, title: loc("celebration.feature2"), desc: loc("apps.custom_tiles_subtitle"))
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 20)

                // Bouton d'action principal
                Button {
                    onDismiss()
                } label: {
                    HStack(spacing: 7) {
                        Text(loc("celebration.button"))
                            .font(.system(size: 13.5, weight: .semibold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.20, green: 0.50, blue: 1.0), Color(red: 0.55, green: 0.32, blue: 0.95)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.65), Color.white.opacity(0.15)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: Color.purple.opacity(0.42), radius: 10, y: 5)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .padding(.horizontal, 24)
                .padding(.bottom, 22)
            }
            .frame(width: 440)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.15), Color.white.opacity(0.02), Color.black.opacity(0.28)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.78),
                                Color(red: 1.0, green: 0.85, blue: 0.4).opacity(0.55),
                                Color.white.opacity(0.12),
                                Color.white.opacity(0.32)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            )
            .shadow(color: .black.opacity(0.55), radius: 36, y: 16)
            .scaleEffect(appear ? 1.0 : 0.78)
            .opacity(appear ? 1.0 : 0.0)
        }
        .onAppear {
            if Prefs.reduceMotion {
                appear = true
                logoBounce = true
                particlesExploded = true
                return
            }
            withAnimation(.spring(response: 0.48, dampingFraction: 0.72)) {
                appear = true
            }
            withAnimation(.spring(response: 0.52, dampingFraction: 0.65).delay(0.05)) {
                logoBounce = true
            }
            withAnimation(.easeOut(duration: 0.65).delay(0.08)) {
                particlesExploded = true
            }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                logoPulse = true
            }
            withAnimation(.linear(duration: 12).repeatForever(autoreverses: false)) {
                ringRotation = 360
            }
        }
    }

    private func proFeatureRow(symbol: String, color: Color, title: String, desc: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 26, height: 26)
                .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.65))
            }
            Spacer()
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.green)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Aperçu de la taille des icônes (Live Preview avec fondu doux)

struct IconScalePreviewBox: View {
    @Binding var iconScale: Double
    var reduceMotion: Bool
    @State private var isLivePreviewingOnLaunchpad = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(loc("interface.icon_scale_preview"), systemImage: "sparkles")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(SettingsStyle.accent)

                livePreviewPillButton

                Spacer()
            }

            HStack(spacing: 24) {
                Spacer(minLength: 0)
                sampleTile(
                    title: "Finder",
                    gradient: [Color(red: 0.15, green: 0.55, blue: 0.95), Color(red: 0.05, green: 0.35, blue: 0.80)],
                    symbol: "face.smiling.fill"
                )
                sampleTile(
                    title: loc("app_sample.music"),
                    gradient: [Color(red: 0.98, green: 0.22, blue: 0.38), Color(red: 0.88, green: 0.12, blue: 0.55)],
                    symbol: "music.note"
                )
                sampleTile(
                    title: "Safari",
                    gradient: [Color(red: 0.12, green: 0.65, blue: 0.95), Color(red: 0.10, green: 0.45, blue: 0.85)],
                    symbol: "safari.fill"
                )
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(SettingsStyle.cardStroke, lineWidth: 1)
                    )
            )
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: iconScale)
        }
        .padding(.vertical, 3)
        .onDisappear {
            if isLivePreviewingOnLaunchpad {
                isLivePreviewingOnLaunchpad = false
                NotificationCenter.default.post(name: .iconScalePreviewDidChange, object: false)
            }
        }
    }

    private var livePreviewPillButton: some View {
        Button {
            isLivePreviewingOnLaunchpad.toggle()
            NotificationCenter.default.post(name: .iconScalePreviewDidChange, object: isLivePreviewingOnLaunchpad)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isLivePreviewingOnLaunchpad ? "eye.fill" : "eye")
                    .font(.system(size: 10, weight: .semibold))
                Text(isLivePreviewingOnLaunchpad ? loc("interface.preview_active") : loc("interface.preview_launchpad"))
                    .font(.system(size: 10, weight: isLivePreviewingOnLaunchpad ? .bold : .medium))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(
                isLivePreviewingOnLaunchpad ? SettingsStyle.accent.opacity(0.20) : Color.primary.opacity(0.04),
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .stroke(isLivePreviewingOnLaunchpad ? SettingsStyle.accent.opacity(0.55) : Color.white.opacity(0.12), lineWidth: 0.8)
            )
            .foregroundStyle(isLivePreviewingOnLaunchpad ? SettingsStyle.accent : .secondary)
        }
        .buttonStyle(.plain)
    }

    private func sampleTile(title: String, gradient: [Color], symbol: String) -> some View {
        let baseSize: CGFloat = 46.0
        let effectiveSize = (baseSize * iconScale).rounded()

        return VStack(spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: effectiveSize * 0.23, style: .continuous)
                    .fill(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: effectiveSize, height: effectiveSize)
                    .shadow(color: gradient.first?.opacity(0.35) ?? .black.opacity(0.2), radius: 5, y: 2.5)
                    .overlay(
                        RoundedRectangle(cornerRadius: effectiveSize * 0.23, style: .continuous)
                            .stroke(Color.white.opacity(0.25), lineWidth: 0.8)
                    )

                Image(systemName: symbol)
                    .font(.system(size: effectiveSize * 0.50, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 64, height: 64)

            Text(title)
                .font(.system(size: max(10, min(12, 11 * iconScale))))
                .foregroundStyle(.primary.opacity(0.85))
                .lineLimit(1)
        }
    }
}

// MARK: - Logos Officiels et Badges de Services Musicaux

struct AppleMusicLogoView: View {
    var size: CGFloat = 38

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.99, green: 0.24, blue: 0.38),
                            Color(red: 0.90, green: 0.12, blue: 0.52)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .shadow(color: Color(red: 0.99, green: 0.24, blue: 0.38).opacity(0.35), radius: 6, y: 2)

            HStack(spacing: 2) {
                Image(systemName: "apple.logo")
                    .font(.system(size: size * 0.38, weight: .bold))
                    .foregroundStyle(.white)
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.40, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }
}

struct SpotifyWavesShape: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        // Onde 1 (supérieure, large)
        path.move(to: CGPoint(x: w * 0.14, y: h * 0.34))
        path.addQuadCurve(to: CGPoint(x: w * 0.86, y: h * 0.24),
                          control: CGPoint(x: w * 0.50, y: h * 0.14))

        // Onde 2 (médiane)
        path.move(to: CGPoint(x: w * 0.20, y: h * 0.56))
        path.addQuadCurve(to: CGPoint(x: w * 0.80, y: h * 0.48),
                          control: CGPoint(x: w * 0.50, y: h * 0.39))

        // Onde 3 (inférieure, courte)
        path.move(to: CGPoint(x: w * 0.26, y: h * 0.77))
        path.addQuadCurve(to: CGPoint(x: w * 0.74, y: h * 0.71),
                          control: CGPoint(x: w * 0.50, y: h * 0.64))

        return path
    }
}

struct SpotifyLogoView: View {
    var size: CGFloat = 38

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(red: 0.114, green: 0.725, blue: 0.329)) // Vert officiel #1DB954
                .frame(width: size, height: size)
                .shadow(color: Color(red: 0.114, green: 0.725, blue: 0.329).opacity(0.35), radius: 6, y: 2)

            SpotifyWavesShape()
                .stroke(Color.black, style: StrokeStyle(lineWidth: size * 0.088, lineCap: .round))
                .frame(width: size * 0.64, height: size * 0.64)
        }
    }
}

struct MusicConnectionStatusBadge: View {
    let status: MusicServiceStatus

    var body: some View {
        HStack(spacing: 5) {
            if status.isConnected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .bold))
                Text(loc("music.status.connected"))
                    .font(.system(size: 11, weight: .semibold))
            } else if status == .connecting {
                ProgressView()
                    .controlSize(.mini)
                Text(loc("music.status.connecting"))
                    .font(.system(size: 11, weight: .semibold))
            } else if case .restricted(let reason) = status {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text(reason.isEmpty ? loc("music.status.restricted") : reason)
                    .font(.system(size: 11, weight: .medium))
            } else if case .error(let msg) = status {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text(msg.isEmpty ? loc("music.status.error") : msg)
                    .font(.system(size: 11, weight: .medium))
            } else {
                Image(systemName: "circle.slash")
                    .font(.system(size: 10, weight: .semibold))
                Text(loc("music.status.not_connected"))
                    .font(.system(size: 11, weight: .medium))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .foregroundStyle(foregroundColor)
        .background(
            Capsule()
                .fill(backgroundColor)
                .overlay(Capsule().stroke(borderColor, lineWidth: 1))
        )
    }

    private var foregroundColor: Color {
        if status.isConnected { return Color(red: 0.16, green: 0.78, blue: 0.40) }
        if status == .connecting { return .orange }
        if case .restricted = status { return .orange }
        if case .error = status { return .red }
        return .secondary
    }

    private var backgroundColor: Color {
        if status.isConnected { return Color.green.opacity(0.12) }
        if status == .connecting { return Color.orange.opacity(0.12) }
        if case .restricted = status { return Color.orange.opacity(0.12) }
        if case .error = status { return Color.red.opacity(0.12) }
        return Color.primary.opacity(0.05)
    }

    private var borderColor: Color {
        if status.isConnected { return Color.green.opacity(0.30) }
        if status == .connecting { return Color.orange.opacity(0.30) }
        if case .restricted = status { return Color.orange.opacity(0.30) }
        if case .error = status { return Color.red.opacity(0.30) }
        return Color.primary.opacity(0.08)
    }
}

// MARK: - Sous-vues isolées des Paramètres (évitent le re-render complet à chaque tick)

private struct SettingsAutoUpdateSwitch: View {
    @Binding var autoCheckUpdates: Bool
    let triggerToast: (String) -> Void
    @ObservedObject private var updateManager = UpdateManager.shared
    @ObservedObject private var locManager = LocalizationManager.shared

    var body: some View {
        SettingsSwitch(isOn: Binding(
            get: { updateManager.autoCheckEnabled },
            set: { newVal in
                updateManager.autoCheckEnabled = newVal
                autoCheckUpdates = newVal
                triggerToast(newVal ? loc("update.auto_on_toast") : loc("update.auto_off_toast"))
            }
        ))
    }
}

private struct SettingsTrialDaysBadgeView: View {
    @ObservedObject var countdown: TrialCountdownState
    @ObservedObject private var locManager = LocalizationManager.shared

    var body: some View {
        Text(countdown.trialDaysRemaining > 0 ? loc("license.trial_days_short", countdown.trialDaysRemaining) : loc("license.trial_7_days_badge"))
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2.5)
            .background(Color(red: 1.00, green: 0.78, blue: 0.05).opacity(0.18), in: Capsule())
            .foregroundStyle(Color(red: 0.85, green: 0.55, blue: 0.00))
            .onAppear { LicenseManager.shared.beginCountdownObservation() }
            .onDisappear { LicenseManager.shared.endCountdownObservation() }
    }
}

private struct SettingsTrialCountdownCard: View {
    @ObservedObject var licenseManager: LicenseManager
    @ObservedObject var countdown: TrialCountdownState
    @ObservedObject private var locManager = LocalizationManager.shared
    let onCancelTrial: () -> Void

    var body: some View {
        let locale = locManager.effectiveLocale
        SettingsCardBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.badge.checkmark.fill")
                            .foregroundStyle(Color.orange)
                            .font(.system(size: 14))
                        Text(loc("license.trial_countdown_header"))
                            .font(.system(size: 13, weight: .bold))
                    }

                    Spacer()

                    Text(countdown.timeRemainingString)
                        .font(.system(size: 13.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.orange)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }

                // Jauge de progression
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.white.opacity(0.10))
                            .frame(height: 6)

                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(LinearGradient(colors: [Color.orange, SettingsStyle.accent], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(8, geo.size.width * CGFloat(1.0 - countdown.trialProgress)), height: 6)
                    }
                }
                .frame(height: 6)

                HStack {
                    Text(loc("license.activated_on", licenseManager.trialStartDate?.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale)) ?? loc("license.activated_recently")))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(loc("license.expires_on", licenseManager.trialEndDate?.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale)) ?? loc("license.expires_in_7_days")))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                SettingsSeparator()
                    .padding(.vertical, 2)

                HStack {
                    Text(loc("license.cancel_trial_hint"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button(role: .destructive, action: onCancelTrial) {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle")
                            Text(loc("license.cancel_trial_btn"))
                        }
                        .font(.system(size: 11.5, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.vertical, 10)
        }
    }
}

private struct SettingsUpdateCardView: View {
    @ObservedObject private var updateManager = UpdateManager.shared
    @ObservedObject private var locManager = LocalizationManager.shared

    var body: some View {
        SettingsCardBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.purple.opacity(0.16))
                            .frame(width: 32, height: 32)
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.purple)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc("update.section_title"))
                            .font(.system(size: 14, weight: .semibold))
                        if let lastChecked = updateManager.lastChecked {
                            Text(loc("update.last_checked", lastChecked.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locManager.effectiveLocale))))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(loc("update.auto_enabled_badge"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if updateManager.state == .checking {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                SettingsSeparator()
                    .padding(.vertical, 2)

                switch updateManager.state {
                case .idle:
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loc("update.current_version", updateManager.currentAppVersion))
                                .font(.system(size: 13, weight: .medium))
                            Text(loc("update.check_desc"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(loc("update.check_btn")) {
                            updateManager.checkForUpdates(manual: true)
                        }
                        .buttonStyle(.bordered)
                    }

                case .checking:
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(loc("update.checking"))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)

                case .upToDate(let version):
                    HStack(spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.system(size: 16))
                            Text(loc("update.up_to_date", version))
                                .font(.system(size: 13, weight: .medium))
                        }
                        Spacer()
                        Button(loc("update.recheck_btn")) {
                            updateManager.checkForUpdates(manual: true)
                        }
                        .buttonStyle(.bordered)
                    }

                case .updateAvailable(let version, let notes, _):
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(SettingsStyle.accent)
                                Text(loc("update.available", version))
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(SettingsStyle.accent)
                            }
                            Spacer()
                            Button {
                                updateManager.downloadAndInstall()
                            } label: {
                                Label(loc("update.install_btn"), systemImage: "arrow.down.circle.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(SettingsStyle.accent)
                        }

                        if !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            let cleanNotes = notes
                                .replacingOccurrences(of: "### ", with: "")
                                .trimmingCharacters(in: .whitespacesAndNewlines)

                            VStack(alignment: .leading, spacing: 6) {
                                Text(loc("update.whats_new"))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                Text(LocalizedStringKey(cleanNotes))
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(.primary.opacity(0.92))
                                    .lineSpacing(3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.04))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }

                case .downloading(let progress):
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(loc("update.downloading", Int(progress * 100)))
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Button(loc("dialog.cancel")) {
                                updateManager.cancelDownload()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        ProgressView(value: progress)
                    }

                case .readyToRestart(let version):
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(loc("update.downloaded_title", version))
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.green)
                                Text(loc("update.downloaded_sub"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        HStack {
                            Spacer()
                            Button {
                                updateManager.applyUpdateAndRelaunch()
                            } label: {
                                Label(loc("update.restart_btn"), systemImage: "arrow.clockwise.circle.fill")
                                    .font(.system(size: 13, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                        }
                    }
                    .padding(12)
                    .background(Color.green.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                case .installing:
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(loc("update.installing"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(SettingsStyle.accent)
                    }
                    .padding(.vertical, 4)

                case .error(let message):
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loc("update.check_failed"))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.red)
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(loc("update.retry_btn")) {
                            updateManager.checkForUpdates(manual: true)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                SettingsSeparator()
                    .padding(.vertical, 2)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc("update.auto_row_title"))
                            .font(.system(size: 13, weight: .medium))
                        Text(loc("update.auto_row_sub"))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $updateManager.autoCheckEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(SettingsStyle.accent)
                }
            }
            .padding(.vertical, 16)
        }
    }
}
