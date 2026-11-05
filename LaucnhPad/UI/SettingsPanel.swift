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
    static let size = CGSize(width: 640, height: 710)
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
    @AppStorage(PrefKey.iconStyle) private var iconStyle = "system"
    @AppStorage(PrefKey.displayMode) private var displayMode: DisplayMode = .fullScreen
    @AppStorage(PrefKey.hideDock) private var hideDock = true
    @AppStorage(PrefKey.appLogo) private var appLogo: AppLogo = .noir
    @AppStorage(PrefKey.tintedIcons) private var tintedIcons = false
    @AppStorage(PrefKey.tintedIconColor) private var tintedIconColor = "accent"
    @AppStorage(PrefKey.showFavoritesBar) private var showFavoritesBar = true
    @AppStorage(PrefKey.showWidgetBanner) private var showWidgetBanner = true
    @AppStorage(PrefKey.widgetClockEnabled) private var widgetClockEnabled = true
    @AppStorage(PrefKey.widgetSystemEnabled) private var widgetSystemEnabled = true
    @AppStorage(PrefKey.widgetQuickNoteEnabled) private var widgetQuickNoteEnabled = true
    @ObservedObject private var licenseManager = LicenseManager.shared
    @ObservedObject private var widgetManager = WidgetManager.shared
    @ObservedObject private var customTileManager = CustomTileManager.shared
    @ObservedObject private var locManager = LocalizationManager.shared
    @ObservedObject private var updateManager = UpdateManager.shared
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

    enum SettingsTab: String, CaseIterable, Identifiable {
        case general, interface, apps, advanced, license, about
        var id: String { rawValue }
        var title: String {
            switch self {
            case .general: return loc("tab.general")
            case .interface: return loc("tab.interface")
            case .apps: return loc("tab.apps")
            case .advanced: return loc("tab.advanced")
            case .license: return loc("tab.license")
            case .about: return loc("tab.about")
            }
        }
        var symbol: String {
            switch self {
            case .general: return "gearshape"
            case .interface: return "camera.macro"
            case .apps: return "rectangle.inset.topleft.filled"
            case .advanced: return "switch.2"
            case .license: return "key.fill"
            case .about: return "info.circle"
            }
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                tabBar
                    .padding(.top, 28)
                    .padding(.bottom, 10)
                Rectangle().fill(SettingsStyle.separator).frame(height: 1)
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        switch selectedTab {
                        case .general: generalTab
                        case .interface: interfaceTab
                        case .apps: appsTab
                        case .advanced: advancedTab
                        case .license: licenseTab
                        case .about: aboutTab
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 44)
                }
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
        .frame(width: Self.size.width, height: Self.size.height)
        .background(settingsBackground)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
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
        .environment(\.colorScheme, backgroundStyle == .light ? .light : .dark)
        .onReceive(Timer.publish(every: 3, on: .main, in: .common).autoconnect()) { _ in
            guard selectedTab == .general, !accessibilityGranted else { return }
            accessibilityGranted = AXIsProcessTrusted()
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) { message = nil }
        }
        .onAppear {
            accessibilityGranted = AXIsProcessTrusted()
            if let target = SettingsPanel.targetTab {
                selectedTab = target
                SettingsPanel.targetTab = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsTab)) { note in
            if let tab = note.object as? SettingsTab {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedTab = tab
                }
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            if newTab != .interface {
                NotificationCenter.default.post(name: .iconScalePreviewDidChange, object: false)
            }
        }
        .onDisappear {
            NotificationCenter.default.post(name: .iconScalePreviewDidChange, object: false)
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
            case .glass:
                VisualEffectBackground(material: .fullScreenUI)
                Color(nsColor: .windowBackgroundColor).opacity(settingsOpacity * 0.45)
            case .liquidGlass:
                VisualEffectBackground(material: .fullScreenUI)
                    .opacity(0.30 + 0.70 * i)
                Color.black.opacity(0.24)
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.18),
                        Color.purple.opacity(0.06),
                        Color.blue.opacity(0.05),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                LinearGradient(
                    colors: [Color.white.opacity(0.24), Color.white.opacity(0.04), Color.clear],
                    startPoint: .top,
                    endPoint: .center
                )
            }
        }
        .ignoresSafeArea()
    }

    // MARK: Onglets (icône au-dessus du titre, onglet actif en violet)

    private var tabBar: some View {
        HStack(spacing: 8) {
            ForEach(SettingsTab.allCases) { tab in
                let selected = selectedTab == tab
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { selectedTab = tab }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 18, weight: .regular))
                            .frame(height: 20)
                        HStack(spacing: 3) {
                            Text(tab.title)
                                .font(.system(size: 12.5, weight: selected ? .medium : .regular))
                                .lineLimit(1)
                            if tab == .license && licenseManager.isPro {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(Color.green)
                            }
                        }
                    }
                    .frame(width: 96, height: 62)
                    .foregroundStyle(selected ? SettingsStyle.accent : Color.primary.opacity(0.78))
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(SettingsStyle.accent.opacity(0.18))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(SettingsStyle.accent.opacity(0.35), lineWidth: 1)
                                }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
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
                            .foregroundStyle(.white)
                        Text(loc("permission.banner.desc"))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.white.opacity(0.72))
                    }

                    Spacer()

                    Button(loc("general.authorize_button")) {
                        PermissionManager.shared.requestAccessibility()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.small)
                }
                .padding(.vertical, 10)
            }
        }

        SettingsSectionTitle(loc("section.language"))
        SettingsCardBox {
            SettingsRow(loc("lang.title"), subtitle: loc("lang.subtitle")) {
                SettingsMenuPicker(selection: $locManager.currentLanguage, options: AppLanguage.allCases, title: \.displayName)
            }
        }

        SettingsCardBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(loc("general.app_logo")).font(.system(size: 14, weight: .medium))
                            if !licenseManager.isPro {
                                ProBadge(isUnlocked: false)
                            }
                        }
                        Text(loc("general.app_logo_subtitle"))
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(AppLogo.allCases) { logo in
                            AppLogoOption(
                                logo: logo,
                                selected: appLogo == logo,
                                isProUnlocked: licenseManager.isPro
                            ) {
                                handleLogoSelection(logo)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 2)
                }
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
            if pinchMode != .off && pinchMode != .three && SystemConflicts.systemFourFingerPinchEnabled {
                SettingsWarning(loc("general.pinch_conflict"))
            }
            if pinchMode != .off && SystemConflicts.systemThreeFingerDragEnabled {
                SettingsWarning(loc("general.three_finger_drag_tip"))
            }
            SettingsSeparator()
            SettingsSliderRow(loc("general.scroll_sensitivity"), value: $scrollSensitivity, range: 0.2...2.0, step: 0.1)
            SettingsSeparator()
            SettingsRow(loc("general.hot_corner")) {
                SettingsMenuPicker(selection: $hotCorner, options: HotCorner.allCases, title: \.title)
            }
            if hotCorner != .off && SystemConflicts.systemHotCornerAssigned(hotCorner) {
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

        SettingsSectionTitle(loc("general.behavior"))
        SettingsCardBox {
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
        }

        SettingsSectionTitle(loc("general.tips_title"))
        SettingsCardBox {
            SettingsNote(loc("general.tips_text"))
                .padding(.vertical, 6)
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
                    if LaunchOSReader.databaseURL != nil {
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
            SettingsSeparator()
            SettingsSliderRow(loc("interface.icon_scale"), value: $iconScale, range: 0.7...1.3, onEditingChanged: { editing in
                NotificationCenter.default.post(name: .iconScalePreviewDidChange, object: editing)
            })
            IconScalePreviewBox(iconScale: $iconScale, reduceMotion: reduceMotion)
            SettingsSeparator()
            SettingsRow(loc("interface.icon_color"),
                        subtitle: loc("interface.icon_color_subtitle")) {
                Picker("", selection: $iconStyle) {
                    Text(loc("interface.icon_color_system")).tag("system")
                    Text(loc("interface.icon_color_original")).tag("original")
                }
                .labelsHidden().fixedSize()
            }
        }
        SettingsCardBox {
            SettingsRow(loc("interface.hide_labels")) {
                SettingsSwitch(isOn: Binding(get: { !showLabels }, set: { showLabels = !$0 }))
            }
            SettingsSeparator()
            SettingsRow(loc("interface.show_running")) { SettingsSwitch(isOn: $showRunning) }
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

            SettingsSeparator()
            SettingsSliderRow(loc("interface.dimming"), value: $opacity, range: 0...0.8)

            if licenseManager.isPro {
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
                            ("accent", "Accent"),
                            ("graphite", "Gris"),
                            ("blue", "Bleu"),
                            ("purple", "Violet"),
                            ("orange", "Orange"),
                            ("mint", "Menthe"),
                            ("rose", "Rose"),
                            ("gold", "Or")
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

        SettingsSectionTitle(loc("widgets.title"))
        SettingsCardBox {
            SettingsRow(
                loc("widgets.enable_banner"),
                subtitle: loc("widgets.banner_subtitle"),
                isPro: true,
                isProUnlocked: licenseManager.isPro
            ) {
                SettingsSwitch(isOn: Binding(
                    get: { showWidgetBanner },
                    set: { newValue in
                        if newValue && !licenseManager.isPro {
                            confirm(loc("pro_alert.widgets_title"),
                                    loc("pro_alert.widgets_msg")) {
                                withAnimation { selectedTab = .license }
                            }
                        } else {
                            showWidgetBanner = newValue
                        }
                    }
                ))
            }

            if showWidgetBanner && licenseManager.isPro {
                SettingsSeparator()

                // Disposition / Positionnement (Style référence : Volet gauche)
                SettingsRow(loc("widget.settings.position"), subtitle: loc("widget.settings.position_desc")) {
                    Picker("", selection: Binding(
                        get: { widgetManager.position },
                        set: {
                            widgetManager.position = $0
                            widgetManager.saveSettings()
                        }
                    )) {
                        Text(loc("widget.position.leftSide")).tag(WidgetPosition.leftSide)
                        Text(loc("widget.position.topBanner")).tag(WidgetPosition.topBanner)
                    }
                    .labelsHidden().fixedSize()
                }

                SettingsSeparator()

                // Lueur des contours néon (Inspiré des lignes organiques de l'image)
                SettingsRow(loc("widget.settings.glow"), subtitle: loc("widget.settings.glow_desc")) {
                    HStack(spacing: 8) {
                        ForEach(WidgetGlowColor.allCases) { glow in
                            Button {
                                widgetManager.glowColor = glow
                                widgetManager.saveSettings()
                            } label: {
                                Circle()
                                    .fill(glow == .none ? Color.gray.opacity(0.3) : glow.primaryColor)
                                    .frame(width: 20, height: 20)
                                    .overlay(
                                        Circle().stroke(widgetManager.glowColor == glow ? Color.white : Color.clear, lineWidth: 2)
                                    )
                                    .scaleEffect(widgetManager.glowColor == glow ? 1.15 : 1.0)
                            }
                            .buttonStyle(.plain)
                            .help(glow.title)
                        }
                    }
                }

                SettingsSeparator()

                // Arrondi des coins
                SettingsRow(loc("widget.settings.corners")) {
                    Picker("", selection: Binding(
                        get: { Int(widgetManager.cornerRadius) },
                        set: {
                            widgetManager.cornerRadius = CGFloat($0)
                            widgetManager.saveSettings()
                        }
                    )) {
                        Text("18 px (Doux)").tag(18)
                        Text("26 px (Apple / Référence)").tag(26)
                        Text("34 px (Extra arrondi)").tag(34)
                    }
                    .labelsHidden().fixedSize()
                }

                SettingsSeparator()

                // Opacité du verre
                SettingsSliderRow(
                    loc("widget.settings.opacity"),
                    value: Binding(
                        get: { widgetManager.glassOpacity },
                        set: {
                            widgetManager.glassOpacity = $0
                            widgetManager.saveSettings()
                        }
                    ),
                    range: 0.20...0.85
                )
            }
        }

        if showWidgetBanner && licenseManager.isPro {
            SettingsSectionTitle(loc("widget.settings.manage_widgets"))
            ForEach(widgetManager.widgets) { config in
                SettingsCardBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(config.kind.title)
                                    .font(.system(size: 13, weight: .semibold))
                                Text(config.kind.subtitle)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            SettingsSwitch(isOn: Binding(
                                get: { config.isEnabled },
                                set: { _ in widgetManager.toggleWidget(config.kind) }
                            ))
                        }
                        .padding(.vertical, 4)

                        if config.isEnabled {
                            SettingsSeparator()

                            // Choix de la taille
                            HStack {
                                Text(loc("widget.settings.size")).font(.system(size: 12))
                                Spacer()
                                Picker("", selection: Binding(
                                    get: { config.size },
                                    set: { newSize in
                                        widgetManager.updateSize(for: config.kind, size: newSize)
                                        _ = store.updateWidgetSize(config.id, to: newSize, columns: columns, rows: rows)
                                    }
                                )) {
                                    ForEach(config.kind.allowedSizes) { size in
                                        Text(size.title).tag(size)
                                    }
                                }
                                .labelsHidden().fixedSize()
                            }

                            // Options spécifiques selon le widget
                            if config.kind == .weather {
                                SettingsSeparator()
                                HStack {
                                    Text(loc("widget.weather.city")).font(.system(size: 12))
                                    Spacer()
                                    TextField("", text: Binding(
                                        get: { config.weatherCity },
                                        set: {
                                            widgetManager.updateWeather(city: $0, unit: config.weatherUnit, temp: config.weatherTemp, condition: config.weatherCondition, feelsLike: config.weatherFeelsLike)
                                        }
                                    ))
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 140)
                                }

                                SettingsSeparator()
                                HStack {
                                    Text(loc("widget.weather.condition")).font(.system(size: 12))
                                    Spacer()
                                    Picker("", selection: Binding(
                                        get: { config.weatherCondition },
                                        set: {
                                            widgetManager.updateWeather(city: config.weatherCity, unit: config.weatherUnit, temp: config.weatherTemp, condition: $0, feelsLike: config.weatherFeelsLike)
                                        }
                                    )) {
                                        Text(loc("widget.weather.cond.cloudy")).tag("Cloudy")
                                        Text(loc("widget.weather.cond.sunny")).tag("Sunny")
                                        Text(loc("widget.weather.cond.rainy")).tag("Rainy")
                                        Text(loc("widget.weather.cond.clear")).tag("Clear")
                                    }
                                    .labelsHidden().fixedSize()
                                }
                            } else if config.kind == .vinylPlayer || config.kind == .mediaWide {
                                SettingsSeparator()
                                HStack {
                                    Text(loc("widget.music.artist")).font(.system(size: 12))
                                    Spacer()
                                    TextField("", text: Binding(
                                        get: { config.musicArtist },
                                        set: { widgetManager.updateMusic(track: config.musicTrack, artist: $0, album: config.musicAlbum) }
                                    ))
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 140)
                                }

                                SettingsSeparator()
                                HStack {
                                    Text(loc("widget.music.track")).font(.system(size: 12))
                                    Spacer()
                                    TextField("", text: Binding(
                                        get: { config.musicTrack },
                                        set: { widgetManager.updateMusic(track: $0, artist: config.musicArtist, album: config.musicAlbum) }
                                    ))
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 140)
                                }
                            }
                        }
                    }
                }
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

        var body: some View {
        SettingsSectionTitle(loc("music_services.title"))

        // 1. Carte Apple Music (Style Liquid Glass)
        SettingsCardBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 14) {
                    AppleMusicLogoView(size: 42)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(loc("music.apple.title"))
                                .font(.system(size: 14, weight: .semibold))
                            MusicConnectionStatusBadge(status: musicManager.appleMusicStatus)
                        }

                        Text(appleMusicDescriptionText)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 12)

                    if musicManager.appleMusicStatus.isConnected {
                        Button(role: .destructive) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                musicManager.disconnectAppleMusic()
                            }
                        } label: {
                            Label(loc("music.disconnect"), systemImage: "xmark.circle")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                    } else {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                musicManager.connectAppleMusic()
                            }
                        } label: {
                            if musicManager.appleMusicStatus == .connecting {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    Text(loc("music.status.connecting"))
                                }
                            } else {
                                Label(loc("music.connect"), systemImage: "arrow.right.circle.fill")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0.98, green: 0.22, blue: 0.38))
                        .controlSize(.regular)
                    }
                }
            }
            .padding(.vertical, 4)
        }

        // 2. Carte Spotify (Style Liquid Glass)
        SettingsCardBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 14) {
                    SpotifyLogoView(size: 42)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(loc("music.spotify.title"))
                                .font(.system(size: 14, weight: .semibold))
                            MusicConnectionStatusBadge(status: musicManager.spotifyStatus)
                        }

                        Text(spotifyDescriptionText)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 12)

                    if musicManager.spotifyStatus.isConnected {
                        Button(role: .destructive) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                musicManager.disconnectSpotify()
                            }
                        } label: {
                            Label(loc("music.disconnect"), systemImage: "xmark.circle")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                    } else {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                musicManager.connectSpotify()
                            }
                        } label: {
                            if musicManager.spotifyStatus == .connecting {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    Text(loc("music.status.connecting"))
                                }
                            } else {
                                Label(loc("music.connect"), systemImage: "arrow.right.circle.fill")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0.114, green: 0.725, blue: 0.329))
                        .controlSize(.regular)
                    }
                }

                if let notice = musicManager.spotifyLimitationNotice, musicManager.spotifyStatus.isConnected {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                        Text(notice)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.2), lineWidth: 1))
                }

                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(loc("music.spotify.client_id"))
                                .font(.system(size: 11, weight: .medium))
                            Spacer()
                            TextField(loc("music.spotify.client_id_placeholder"), text: $musicManager.customSpotifyClientID)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11))
                                .frame(width: 250)
                        }
                        Text(loc("music.spotify.client_id_help"))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 4)
                } label: {
                    Text(loc("music.spotify.dev_config"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }

        // 3. Source prioritaire
        SettingsCardBox {
            SettingsRow(loc("music.service.preferred")) {
                Picker("", selection: $musicManager.preferredService) {
                    Text(loc("music.service.auto")).tag(MusicServiceSource.system)
                    Text(loc("music.apple.title")).tag(MusicServiceSource.appleMusic)
                    Text(loc("music.spotify.title")).tag(MusicServiceSource.spotify)
                }
                .labelsHidden()
                .fixedSize()
            }
        }
        }

        private var appleMusicDescriptionText: String {
            if musicManager.appleMusicStatus.isConnected {
                return musicManager.appleMusicSubscriptionDescription.isEmpty
                    ? loc("music.apple.authorized")
                    : musicManager.appleMusicSubscriptionDescription
            }
            return loc("music.apple.desc")
        }

        private var spotifyDescriptionText: String {
            if musicManager.spotifyStatus.isConnected {
                if let name = musicManager.spotifyUserDisplayName {
                    let tier = (musicManager.spotifyProductType?.capitalized ?? "")
                    return tier.isEmpty ? name : "\(name) • \(tier)"
                }
                return loc("music.status.connected")
            }
            return loc("music.spotify.desc")
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
            SettingsRow(loc("apps.folders"), subtitle: loc("apps.ungroup_confirm_msg")) {
                Button(loc("apps.ungroup_all")) { store.ungroupAll() }
            }
        }

        SettingsSectionTitle(loc("section.hidden_apps"))
        SettingsCardBox {
            if store.hiddenApps.isEmpty {
                SettingsNote(loc("apps.no_hidden")).padding(.vertical, 6)
            } else {
                ForEach(Array(store.hiddenApps.enumerated()), id: \.element.id) { index, app in
                    if index > 0 { SettingsSeparator() }
                    HStack(spacing: 10) {
                        Image(nsImage: IconCache.shared.icon(for: app.id)).resizable().frame(width: 24, height: 24)
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

        musicServicesSection

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
                        subtitle: LaunchOSReader.databaseURL == nil
                            ? loc("advanced.launchos_no_db")
                            : loc("advanced.launchos_subtitle")) {
                Button(loc("advanced.import")) {
                    confirm(loc("advanced.launchos_confirm_title"), loc("advanced.launchos_confirm_msg")) {
                        importLaunchOS()
                    }
                }
                .disabled(LaunchOSReader.databaseURL == nil)
            }
            SettingsSeparator()
            SettingsRow(loc("advanced.system_launchpad_title"),
                        subtitle: SystemLaunchpadReader.databaseURL == nil
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
                .disabled(SystemLaunchpadReader.databaseURL == nil)
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
        // En-tête de statut
        SettingsCardBox {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(
                            licenseManager.isPro
                                ? LinearGradient(colors: [SettingsStyle.accent, Color.purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [Color.gray.opacity(0.35), Color.gray.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 52, height: 52)
                    Image(systemName: licenseManager.isPro ? "crown.fill" : "lock.shield.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(licenseManager.isPro ? loc("license.pro_unlocked") : loc("license.free_version"))
                            .font(.system(size: 16, weight: .bold))
                        if !licenseManager.isPro {
                            ProBadge()
                        }
                    }
                    Text(licenseManager.isPro
                         ? loc("license.pro_desc")
                         : loc("license.free_desc"))
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(.vertical, 14)
        }

        // Formulaire d'activation ou gestion
        SettingsCardBox {
            VStack(alignment: .leading, spacing: 12) {
                Text(licenseManager.isPro ? loc("license.manage_title") : loc("license.activate_title"))
                    .font(.system(size: 14, weight: .semibold))

                if licenseManager.isPro {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(loc("license.active_key"))
                                .font(.system(size: 13))
                            Text(licenseManager.licenseKey.isEmpty ? "1234 (Démo)" : licenseManager.licenseKey)
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
        let result = licenseManager.validate(code: licenseInput)
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
                        if !licenseManager.isPro {
                            ProBadge()
                        }
                    }

                    HStack(spacing: 6) {
                        Text("Version installée :")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Text("v\(updateManager.currentAppVersion)")
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
                        Text("Mise à jour du logiciel")
                            .font(.system(size: 14, weight: .semibold))
                        if let lastChecked = updateManager.lastChecked {
                            Text("Dernière vérification : \(lastChecked.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Vérification automatique activée")
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
                            Text("Version actuelle : v\(updateManager.currentAppVersion)")
                                .font(.system(size: 13, weight: .medium))
                            Text("Rechercher si une nouvelle version est disponible.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Rechercher") {
                            updateManager.checkForUpdates(manual: true)
                        }
                        .buttonStyle(.bordered)
                    }

                case .checking:
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Recherche de mises à jour sur GitHub...")
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
                            Text("LaucnhPad est à jour (v\(version))")
                                .font(.system(size: 13, weight: .medium))
                        }
                        Spacer()
                        Button("Vérifier à nouveau") {
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
                                Text("Mise à jour disponible : v\(version)")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(SettingsStyle.accent)
                            }
                            Spacer()
                            Button {
                                updateManager.downloadAndInstall()
                            } label: {
                                Label("Installer la mise à jour", systemImage: "arrow.down.circle.fill")
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
                                Text("Nouveautés de cette version :")
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
                            Text("Téléchargement en cours... \(Int(progress * 100))%")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Button("Annuler") {
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
                                Text("Mise à jour v\(version) téléchargée avec succès !")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.green)
                                Text("L'ancienne version sera automatiquement remplacée et supprimée.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        HStack {
                            Spacer()
                            Button {
                                updateManager.applyUpdateAndRelaunch()
                            } label: {
                                Label("Redémarrer l'application", systemImage: "arrow.clockwise.circle.fill")
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
                        Text("Installation et redémarrage automatique en cours...")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(SettingsStyle.accent)
                    }
                    .padding(.vertical, 4)

                case .error(let message):
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Impossible de vérifier")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.red)
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Réessayer") {
                            updateManager.checkForUpdates(manual: true)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                SettingsSeparator()
                    .padding(.vertical, 2)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Recherche automatique")
                            .font(.system(size: 13, weight: .medium))
                        Text("Vérifier régulièrement si une nouvelle version est disponible.")
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
                    Text("Tutoriel de bienvenue")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Revoir le guide interactif présentant toutes les fonctionnalités de LaunchPad.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Button {
                    NotificationCenter.default.post(name: .closeSettings, object: nil)
                    NotificationCenter.default.post(name: .openTutorial, object: nil)
                } label: {
                    Label("Lancer le tutoriel", systemImage: "play.circle.fill")
                        .font(.system(size: 12.5, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                }
                .buttonStyle(.bordered)
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
                            Text("Mode Administrateur")
                                .font(.system(size: 14, weight: .semibold))
                            if adminManager.isAuthenticated {
                                HStack(spacing: 4) {
                                    Circle().fill(Color.green).frame(width: 6, height: 6)
                                    Text("DÉVERROUILLÉ")
                                        .font(.system(size: 10, weight: .bold))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2.5)
                                .background(Color.green.opacity(0.16))
                                .foregroundStyle(.green)
                                .clipShape(Capsule())
                            }
                        }
                        Text(adminManager.isAuthenticated ? "Connecté en tant que \(adminManager.authenticatedUser) — Accès complet au menu de tests" : "Accès réservé pour tester tous les sous-systèmes, widgets, animations et fonctionnalités.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }

                SettingsSeparator()
                    .padding(.vertical, 2)

                if adminManager.isAuthenticated {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Le mode administrateur est actuellement actif. Vous pouvez ouvrir le Centre de Test pour expérimenter toutes les fonctionnalités de LaunchPad.")
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
                                    Text("Ouvrir le Menu de Test")
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
                                Text("Se déconnecter")
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
                                Text("Nom d'utilisateur")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                TextField("admin", text: $adminUsername)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(minWidth: 130)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Mot de passe")
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
                                Label("Connexion", systemImage: "key.fill")
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
                            Text("Identifiants par défaut : **admin** / **1234**")
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
            }
        } catch {
            message = error.localizedDescription
        }
    }
}

// MARK: - Enregistreur de raccourci

struct ShortcutRecorder: View {
    @AppStorage(PrefKey.hotKeyDisplay) private var display = "⌃ Espace"
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Text(recording ? loc("about.shortcut_recording") : display)
                .monospaced()
                .frame(minWidth: 140)
        }
        .onDisappear { stop() }
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
        case .glass:
            Color.white.opacity(0.065)
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
        case .glass:
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
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

/// Bouton de sélection d'un thème (Sombre, Verre flouté, Liquid Glass)
struct ThemeCardButton: View {
    let theme: AppTheme
    let isSelected: Bool
    let isProUnlocked: Bool
    let action: () -> Void

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
                        .overlay {
                            VStack(spacing: 5) {
                                Image(systemName: theme.symbol)
                                    .font(.system(size: 20))
                                    .foregroundStyle(theme == .dark ? Color.white.opacity(0.85) : (theme == .light ? Color.orange : SettingsStyle.accent))
                                Text(theme.title)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(theme == .light ? Color.black.opacity(0.85) : .primary)
                            }
                        }

                    if theme.isProOnly && !isProUnlocked {
                        ProBadge()
                            .padding(6)
                    }
                }

                HStack(spacing: 6) {
                    Circle()
                        .fill(isSelected ? SettingsStyle.accent : Color.primary.opacity(0.16))
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

    @ViewBuilder
    private var previewFill: some View {
        switch theme {
        case .dark:
            Color.black.opacity(0.75)
        case .light:
            LinearGradient(
                colors: [Color.white.opacity(0.95), Color(white: 0.90)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .glass:
            Color.white.opacity(0.09)
        case .liquidGlass:
            LinearGradient(
                colors: [
                    Color.white.opacity(0.20),
                    Color.purple.opacity(0.09),
                    Color.blue.opacity(0.06),
                    Color.white.opacity(0.03)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    @ViewBuilder
    private var previewStroke: some View {
        switch theme {
        case .dark:
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        case .light:
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.black.opacity(0.12), lineWidth: 1)
        case .glass:
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
        case .liquidGlass:
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
}

struct ProCelebrationPopup: View {
    let onDismiss: () -> Void

    @State private var appear = false
    @State private var logoBounce = false
    @State private var particlesExploded = false
    @State private var logoPulse = false
    @State private var ringRotation: Double = 0
    @AppStorage(PrefKey.appLogo) private var appLogo: AppLogo = .noir

    private let particles: [CelebrationParticle] = {
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
            return CelebrationParticle(angle: angle, distance: distance, size: size, color: color, symbol: symbol, rotation: rotation)
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
                ForEach(particles) { p in
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
                    .scaleEffect(particlesExploded ? CGFloat.random(in: 0.8...1.25) : 0.1)
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

                // Badge couronne dorée
                HStack(spacing: 6) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text(loc("celebration.badge"))
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .tracking(1.4)
                }
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(red: 1.0, green: 0.90, blue: 0.50), Color(red: 1.0, green: 0.72, blue: 0.20)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 4.5)
                .background(Color(red: 0.95, green: 0.75, blue: 0.20).opacity(0.18), in: Capsule())
                .overlay(Capsule().stroke(Color(red: 1.0, green: 0.85, blue: 0.35).opacity(0.45), lineWidth: 0.8))
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
    @State private var temporaryPreviewTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(loc("interface.icon_scale_preview"), systemImage: "sparkles")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(SettingsStyle.accent)

                livePreviewPillButton

                Spacer()

                HStack(spacing: 6) {
                    presetButton("0.85×", scale: 0.85)
                    presetButton("1.00×", scale: 1.00)
                    presetButton("1.15×", scale: 1.15)
                }
            }

            HStack(spacing: 24) {
                Spacer(minLength: 0)
                sampleTile(
                    title: "Finder",
                    gradient: [Color(red: 0.15, green: 0.55, blue: 0.95), Color(red: 0.05, green: 0.35, blue: 0.80)],
                    symbol: "face.smiling.fill"
                )
                sampleTile(
                    title: "Musique",
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
            temporaryPreviewTask?.cancel()
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

    private func triggerTemporaryPreview() {
        guard !isLivePreviewingOnLaunchpad else { return }
        temporaryPreviewTask?.cancel()
        NotificationCenter.default.post(name: .iconScalePreviewDidChange, object: true)
        temporaryPreviewTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1600))
            guard !Task.isCancelled, !isLivePreviewingOnLaunchpad else { return }
            NotificationCenter.default.post(name: .iconScalePreviewDidChange, object: false)
        }
    }

    private func presetButton(_ label: String, scale: Double) -> some View {
        let isSelected = abs(iconScale - scale) < 0.02
        return Button {
            withAnimation(.easeInOut(duration: 0.20)) {
                iconScale = scale
            }
            triggerTemporaryPreview()
        } label: {
            Text(label)
                .font(.system(size: 10.5, weight: isSelected ? .bold : .regular))
                .padding(.horizontal, 7)
                .padding(.vertical, 2.5)
                .background(isSelected ? SettingsStyle.accent.opacity(0.2) : Color.primary.opacity(0.04), in: Capsule())
                .foregroundStyle(isSelected ? SettingsStyle.accent : .secondary)
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
