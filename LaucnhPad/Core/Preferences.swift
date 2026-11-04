import AppKit
import Carbon.HIToolbox

// Préférences centralisées : UserDefaults reste léger et évite de recréer des tâches.
// (Inspiré de l'« AppState » de LaunchOS : une seule source de vérité pour tous les réglages.)
nonisolated enum PrefKey: Sendable {
    static let columns = "LaunchpadGridColumns"
    static let rows = "LaunchpadGridRows"
    static let backgroundOpacity = "LaunchpadBackgroundOpacity"
    static let backgroundStyle = "LaunchpadBackgroundStyle"
    static let iconScale = "LaunchpadIconScale"
    static let showLabels = "LaunchpadShowLabels"
    static let reduceMotion = "LaunchpadReduceMotion"
    static let launchAtLogin = "LaunchpadLaunchAtLogin"
    static let scrollSensitivity = "LaunchpadScrollSensitivity"
    static let settingsOpacity = "LaunchpadSettingsOpacity"
    static let pinchMode = "LaunchpadPinchMode"
    static let hotCorner = "LaunchpadHotCorner"
    static let interceptF4 = "LaunchpadInterceptF4"
    static let hotKeyEnabled = "LaunchpadHotKeyEnabled"
    static let hotKeyCode = "LaunchpadHotKeyCode"
    static let hotKeyModifiers = "LaunchpadHotKeyModifiers"
    static let hotKeyDisplay = "LaunchpadHotKeyDisplay"
    static let screenTarget = "LaunchpadScreenTarget"
    static let returnToFirstPage = "LaunchpadReturnToFirstPage"
    static let showMenuBarIcon = "LaunchpadShowMenuBarIcon"
    static let showDockIcon = "LaunchpadShowDockIcon"
    static let showHiddenInSearch = "LaunchpadShowHiddenInSearch"
    static let showRunningIndicator = "LaunchpadShowRunningIndicator"
    static let customSources = "LaunchpadCustomSources"
    static let reorganizeRule = "LaunchpadReorganizeRule"
    static let folderPlacement = "LaunchpadFolderPlacement"
    static let sortFolderContents = "LaunchpadSortFolderContents"
    static let hasLaunchedBefore = "LaunchpadHasLaunchedBefore"
    static let iconStyle = "LaunchpadIconStyle"
    static let displayMode = "LaunchpadDisplayMode"
    static let hideDock = "LaunchpadHideDock"
    static let appLogo = "LaunchpadAppLogo"
    static let isProUnlocked = "LaunchpadIsProUnlocked"
    static let licenseKey = "LaunchpadLicenseKey"
    static let tintedIcons = "LaunchpadTintedIcons"
    static let tintedIconColor = "LaunchpadTintedIconColor"
    static let showFavoritesBar = "LaunchpadShowFavoritesBar"
    static let favoriteAppIDs = "LaunchpadFavoriteAppIDs"
    static let customTiles = "LaunchpadCustomTiles"
    static let autoCheckUpdates = "LaunchpadAutoCheckUpdates"
    static let appLanguage = "LaunchpadAppLanguage"
    static let showWidgetBanner = "LaunchpadShowWidgetBanner"
    static let widgetBannerCollapsed = "LaunchpadWidgetBannerCollapsed"
    static let widgetClockEnabled = "LaunchpadWidgetClockEnabled"
    static let widgetSystemEnabled = "LaunchpadWidgetSystemEnabled"
    static let widgetQuickNoteEnabled = "LaunchpadWidgetQuickNoteEnabled"
    static let widgetQuickNoteText = "LaunchpadWidgetQuickNoteText"
    static let customWidgetsData = "LaunchpadCustomWidgetsData"
    static let widgetPosition = "LaunchpadWidgetPosition"
    static let widgetGlowColor = "LaunchpadWidgetGlowColor"
    static let widgetCornerRadius = "LaunchpadWidgetCornerRadius"
    static let widgetGlassOpacity = "LaunchpadWidgetGlassOpacity"

    /// Clés exportées dans les sauvegardes.
    static let backupKeys: [String] = [
        columns, rows, backgroundOpacity, backgroundStyle, iconScale, showLabels, reduceMotion,
        scrollSensitivity, settingsOpacity, pinchMode, hotCorner, interceptF4, hotKeyEnabled,
        hotKeyCode, hotKeyModifiers, hotKeyDisplay, screenTarget, returnToFirstPage,
        showMenuBarIcon, showDockIcon, showHiddenInSearch, showRunningIndicator, customSources,
        reorganizeRule, folderPlacement, sortFolderContents, iconStyle, displayMode, hideDock, appLogo,
        isProUnlocked, licenseKey, tintedIcons, tintedIconColor, showFavoritesBar, favoriteAppIDs, customTiles,
        appLanguage, showWidgetBanner, widgetBannerCollapsed, widgetClockEnabled, widgetSystemEnabled,
        widgetQuickNoteEnabled, widgetQuickNoteText, customWidgetsData, widgetPosition, widgetGlowColor,
        widgetCornerRadius, widgetGlassOpacity,
    ]
}

/// Logos de l'app, au choix dans les réglages (réservé à la version Pro sauf le logo par défaut).
enum AppLogo: Int, CaseIterable, Identifiable {
    case noir = 1
    case liquidGlass = 2
    case graphite = 3
    case blanc = 4
    case orRoyal = 5
    case aurora = 6

    var id: Int { rawValue }

    var title: String {
        loc("logo.\(rawValue)")
    }

    var isProOnly: Bool {
        self != .noir
    }

    var assetName: String { "AppLogo\(rawValue)" }

    @MainActor var image: NSImage? {
        if let img = NSImage(named: NSImage.Name(assetName)) {
            return img
        }
        if let bundleImage = Bundle.main.image(forResource: NSImage.Name(assetName)) {
            return bundleImage
        }
        if self == .noir {
            return NSApp.applicationIconImage
        }
        return nil
    }
}

/// Mode d'affichage (comme LaunchOS : plein écran ou fenêtre centrée).
enum DisplayMode: String, CaseIterable, Identifiable {
    case fullScreen, window
    var id: String { rawValue }
    var title: String {
        switch self {
        case .fullScreen: return loc("display.fullscreen")
        case .window: return loc("display.window")
        }
    }
}

enum PinchMode: String, CaseIterable, Identifiable {
    case off, three, fourFive, five
    var id: String { rawValue }
    var title: String { loc("pinch.\(rawValue)") }
    func accepts(_ fingers: Int) -> Bool {
        switch self {
        case .off: false
        case .three: fingers == 3
        case .fourFive: fingers == 4 || fingers == 5
        case .five: fingers == 5
        }
    }
}

enum HotCorner: String, CaseIterable, Identifiable {
    case off, topLeft, topRight, bottomLeft, bottomRight
    var id: String { rawValue }
    var title: String { loc("corner.\(rawValue)") }
    /// Clé du coin actif système (com.apple.dock) correspondant.
    var dockKey: String? {
        switch self {
        case .off: nil
        case .topLeft: "wvous-tl-corner"
        case .topRight: "wvous-tr-corner"
        case .bottomLeft: "wvous-bl-corner"
        case .bottomRight: "wvous-br-corner"
        }
    }
}

enum ScreenTarget: String, CaseIterable, Identifiable {
    case cursor, main, active
    var id: String { rawValue }
    var title: String { loc("screen.\(rawValue)") }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case dark = "dark"
    case light = "light"
    case glass = "glass"
    case liquidGlass = "liquidGlass"

    var id: String { rawValue }
    var title: String { loc("theme.\(rawValue)") }
    var symbol: String {
        switch self {
        case .dark: "moon.fill"
        case .light: "sun.max.fill"
        case .glass: "macwindow"
        case .liquidGlass: "sparkles"
        }
    }
    var subtitle: String { loc("theme.desc.\(rawValue)") }
    var isProOnly: Bool {
        self == .liquidGlass
    }
    var isLight: Bool {
        self == .light
    }
    /// Ne charge pas de fond d'écran image système
    var usesWallpaper: Bool { false }
}

typealias BackgroundStyle = AppTheme

enum SortRule: String, CaseIterable, Identifiable {
    case nameAscending, nameDescending, dateAddedNewest, dateAddedOldest, lastUsedRecent, lastUsedOldest, category
    var id: String { rawValue }
    var title: String { loc("sort.\(rawValue)") }
}

enum FolderPlacement: String, CaseIterable, Identifiable {
    case before, after, mixed
    var id: String { rawValue }
    var title: String { loc("placement.\(rawValue)") }
}

enum Prefs {
    static var defaults: UserDefaults { .standard }

    /// À appeler AVANT `registerDefaults()` : `object(forKey:)` renvoie sinon la valeur enregistrée par défaut.
    static func migrateLegacyValues() {
        if let current = defaults.string(forKey: PrefKey.backgroundStyle), current == "wallpaper" || current == "transparent" {
            defaults.set(AppTheme.liquidGlass.rawValue, forKey: PrefKey.backgroundStyle)
        }
        if defaults.object(forKey: PrefKey.pinchMode) == nil {
            if let legacy = defaults.string(forKey: "LaunchpadTrackpadMode") {
                defaults.set(legacy == "off" ? PinchMode.off.rawValue : PinchMode.three.rawValue, forKey: PrefKey.pinchMode)
            } else if let enabled = defaults.object(forKey: "LaunchpadThreeFingerEnabled") as? Bool, !enabled {
                defaults.set(PinchMode.off.rawValue, forKey: PrefKey.pinchMode)
            }
        }
        if !isProUnlocked && appLogo.isProOnly {
            defaults.set(AppLogo.noir.rawValue, forKey: PrefKey.appLogo)
        }
    }

    static func registerDefaults() {
        defaults.register(defaults: [
            PrefKey.columns: 7,
            PrefKey.rows: 5,
            PrefKey.backgroundOpacity: 0.15,
            PrefKey.backgroundStyle: AppTheme.liquidGlass.rawValue,
            PrefKey.isProUnlocked: false,
            PrefKey.licenseKey: "",
            PrefKey.iconScale: 1.0,
            PrefKey.showLabels: true,
            PrefKey.reduceMotion: false,
            PrefKey.scrollSensitivity: 1.0,
            PrefKey.settingsOpacity: 0.92,
            PrefKey.pinchMode: PinchMode.three.rawValue,
            PrefKey.hotCorner: HotCorner.off.rawValue,
            PrefKey.interceptF4: false,
            PrefKey.hotKeyEnabled: true,
            PrefKey.hotKeyCode: kVK_Space,
            PrefKey.hotKeyModifiers: controlKey,
            PrefKey.hotKeyDisplay: "⌃ Espace",
            PrefKey.screenTarget: ScreenTarget.cursor.rawValue,
            PrefKey.returnToFirstPage: -1,
            PrefKey.showMenuBarIcon: true,
            PrefKey.showDockIcon: false,
            PrefKey.showHiddenInSearch: false,
            PrefKey.showRunningIndicator: true,
            PrefKey.customSources: [String](),
            PrefKey.reorganizeRule: SortRule.nameAscending.rawValue,
            PrefKey.folderPlacement: FolderPlacement.before.rawValue,
            PrefKey.sortFolderContents: false,
            PrefKey.iconStyle: "system",
            PrefKey.displayMode: DisplayMode.fullScreen.rawValue,
            PrefKey.hideDock: true,
            PrefKey.appLogo: AppLogo.noir.rawValue,
            PrefKey.tintedIcons: false,
            PrefKey.tintedIconColor: "accent",
            PrefKey.showFavoritesBar: true,
            PrefKey.favoriteAppIDs: [String](),
            PrefKey.appLanguage: AppLanguage.auto.rawValue,
            PrefKey.showWidgetBanner: true,
            PrefKey.widgetBannerCollapsed: false,
            PrefKey.widgetClockEnabled: true,
            PrefKey.widgetSystemEnabled: true,
            PrefKey.widgetQuickNoteEnabled: true,
            PrefKey.widgetQuickNoteText: "",
        ])
    }

    static var showWidgetBanner: Bool { defaults.bool(forKey: PrefKey.showWidgetBanner) }
    static var iconScale: Double { defaults.double(forKey: PrefKey.iconScale) }
    static var widgetBannerCollapsed: Bool { defaults.bool(forKey: PrefKey.widgetBannerCollapsed) }
    static var widgetClockEnabled: Bool { defaults.bool(forKey: PrefKey.widgetClockEnabled) }
    static var widgetSystemEnabled: Bool { defaults.bool(forKey: PrefKey.widgetSystemEnabled) }
    static var widgetQuickNoteEnabled: Bool { defaults.bool(forKey: PrefKey.widgetQuickNoteEnabled) }
    static var widgetQuickNoteText: String { defaults.string(forKey: PrefKey.widgetQuickNoteText) ?? "" }

    static var appLanguage: AppLanguage { AppLanguage(rawValue: defaults.string(forKey: PrefKey.appLanguage) ?? "") ?? .auto }
    static var appLogo: AppLogo { AppLogo(rawValue: defaults.integer(forKey: PrefKey.appLogo)) ?? .noir }

    static var displayMode: DisplayMode { DisplayMode(rawValue: defaults.string(forKey: PrefKey.displayMode) ?? "") ?? .fullScreen }
    static var hideDock: Bool { defaults.bool(forKey: PrefKey.hideDock) }

    static var columns: Int { min(max(defaults.integer(forKey: PrefKey.columns), 3), 12) }
    static var rows: Int { min(max(defaults.integer(forKey: PrefKey.rows), 2), 9) }
    static var pageSize: Int { columns * rows }
    static var reduceMotion: Bool {
        defaults.bool(forKey: PrefKey.reduceMotion) || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
    static var scrollSensitivity: Double {
        let value = defaults.double(forKey: PrefKey.scrollSensitivity)
        return value == 0 ? 1 : min(max(value, 0.2), 2.0)
    }
    static var pinchMode: PinchMode { PinchMode(rawValue: defaults.string(forKey: PrefKey.pinchMode) ?? "") ?? .three }
    static var hotCorner: HotCorner { HotCorner(rawValue: defaults.string(forKey: PrefKey.hotCorner) ?? "") ?? .off }
    static var interceptF4: Bool { defaults.bool(forKey: PrefKey.interceptF4) }
    static var hotKeyEnabled: Bool { defaults.bool(forKey: PrefKey.hotKeyEnabled) }
    static var hotKeyCode: UInt32 { UInt32(max(0, defaults.integer(forKey: PrefKey.hotKeyCode))) }
    static var hotKeyModifiers: UInt32 { UInt32(max(0, defaults.integer(forKey: PrefKey.hotKeyModifiers))) }
    static var screenTarget: ScreenTarget { ScreenTarget(rawValue: defaults.string(forKey: PrefKey.screenTarget) ?? "") ?? .cursor }
    static var backgroundStyle: BackgroundStyle {
        BackgroundStyle(rawValue: defaults.string(forKey: PrefKey.backgroundStyle) ?? "") ?? .liquidGlass
    }
    static var isProUnlocked: Bool {
        get { defaults.bool(forKey: PrefKey.isProUnlocked) }
        set { defaults.set(newValue, forKey: PrefKey.isProUnlocked) }
    }
    static var licenseKey: String {
        get { defaults.string(forKey: PrefKey.licenseKey) ?? "" }
        set { defaults.set(newValue, forKey: PrefKey.licenseKey) }
    }
    static var tintedIcons: Bool { defaults.bool(forKey: PrefKey.tintedIcons) }
    static var tintedIconColor: String { defaults.string(forKey: PrefKey.tintedIconColor) ?? "accent" }
    static var showFavoritesBar: Bool { defaults.bool(forKey: PrefKey.showFavoritesBar) }
    static var favoriteAppIDs: [String] {
        get { defaults.stringArray(forKey: PrefKey.favoriteAppIDs) ?? [] }
        set { defaults.set(newValue, forKey: PrefKey.favoriteAppIDs) }
    }
    static var returnToFirstPage: Int { defaults.integer(forKey: PrefKey.returnToFirstPage) }
    static var showMenuBarIcon: Bool { defaults.bool(forKey: PrefKey.showMenuBarIcon) }
    static var showDockIcon: Bool { defaults.bool(forKey: PrefKey.showDockIcon) }
    static var showHiddenInSearch: Bool { defaults.bool(forKey: PrefKey.showHiddenInSearch) }
    static var customSources: [String] { defaults.stringArray(forKey: PrefKey.customSources) ?? [] }
    static var allSources: [String] {
        var result: [String] = []
        for path in AppScanner.defaultSources + customSources where !result.contains(path) { result.append(path) }
        return result
    }
}

/// Lecture des réglages système susceptibles d'entrer en conflit (comme le fait LaunchOS).
enum SystemConflicts {
    /// Le geste système « pincer avec 4 doigts » (Launchpad / Apps) est-il actif ?
    static var systemFourFingerPinchEnabled: Bool {
        for domain in ["com.apple.AppleMultitouchTrackpad", "com.apple.driver.AppleBluetoothMultitouch.trackpad"] {
            if let value = CFPreferencesCopyAppValue("TrackpadFourFingerPinchGesture" as CFString, domain as CFString) as? Int, value == 2 {
                return true
            }
        }
        return false
    }

    /// Un coin actif système est-il déjà affecté à ce coin ?
    static func systemHotCornerAssigned(_ corner: HotCorner) -> Bool {
        guard let key = corner.dockKey,
              let value = CFPreferencesCopyAppValue(key as CFString, "com.apple.dock" as CFString) as? Int else { return false }
        return value > 1
    }
}

// MARK: - Notifications Globales de Cycle de Vie
extension Notification.Name {
    public static let launchpadVisibilityDidChange = Notification.Name("LaunchpadVisibilityDidChange")
    public static let settingsVisibilityDidChange = Notification.Name("SettingsVisibilityDidChange")
    public static let iconScalePreviewDidChange = Notification.Name("IconScalePreviewDidChange")
    public static let openSettingsTab = Notification.Name("OpenSettingsTab")
}

