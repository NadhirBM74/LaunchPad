import Foundation
import SwiftUI
import Combine

/// Gestionnaire de widgets personnalisables (Version Pro)
@MainActor
final class WidgetManager: ObservableObject {
    static let shared = WidgetManager()

    @Published var widgets: [CustomWidgetConfig] = []
    @Published var position: WidgetPosition = .leftSide
    @Published var glowColor: WidgetGlowColor = .none
    @Published var cornerRadius: CGFloat = 26.0
    @Published var glassOpacity: Double = 0.52

    private var saveWorkTask: Task<Void, Never>?

    private init() {
        loadSettings()
    }

    // MARK: - Chargement & Sauvegarde

    func loadSettings() {
        let defaults = UserDefaults.standard

        let newPosition: WidgetPosition = {
            if let posRaw = defaults.string(forKey: PrefKey.widgetPosition),
               let pos = WidgetPosition(rawValue: posRaw) {
                return pos
            }
            return .leftSide
        }()

        let newGlow: WidgetGlowColor = {
            if let glowRaw = defaults.string(forKey: PrefKey.widgetGlowColor),
               let glow = WidgetGlowColor(rawValue: glowRaw) {
                return glow
            }
            return .none
        }()

        let newRadius: CGFloat
        if defaults.object(forKey: PrefKey.widgetCornerRadius) != nil {
            newRadius = CGFloat(defaults.double(forKey: PrefKey.widgetCornerRadius))
        } else {
            newRadius = 26.0
        }

        let newOpacity: Double
        if defaults.object(forKey: PrefKey.widgetGlassOpacity) != nil {
            newOpacity = defaults.double(forKey: PrefKey.widgetGlassOpacity)
        } else {
            newOpacity = 0.52
        }

        if self.position != newPosition { self.position = newPosition }
        if self.glowColor != newGlow { self.glowColor = newGlow }
        if self.cornerRadius != newRadius { self.cornerRadius = newRadius }
        if self.glassOpacity != newOpacity { self.glassOpacity = newOpacity }

        // Widgets
        if let data = defaults.data(forKey: PrefKey.customWidgetsData),
           var decoded = try? JSONDecoder().decode([CustomWidgetConfig].self, from: data),
           !decoded.isEmpty {
            for def in Self.defaultWidgets() where !decoded.contains(where: { $0.kind == def.kind }) {
                var copy = def
                copy.order = decoded.count
                decoded.append(copy)
            }
            var seenEnabledCategories = Set<WidgetCategoryGroup>()
            for idx in decoded.indices where decoded[idx].isEnabled {
                if !seenEnabledCategories.insert(decoded[idx].kind.categoryGroup).inserted {
                    decoded[idx].isEnabled = false
                }
            }
            if self.widgets != decoded {
                self.widgets = decoded
            }
        } else {
            self.widgets = Self.defaultWidgets()
            saveWidgetsNow()
        }
    }

    func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(position.rawValue, forKey: PrefKey.widgetPosition)
        defaults.set(glowColor.rawValue, forKey: PrefKey.widgetGlowColor)
        defaults.set(Double(cornerRadius), forKey: PrefKey.widgetCornerRadius)
        defaults.set(glassOpacity, forKey: PrefKey.widgetGlassOpacity)
        saveWidgets()
    }

    func saveWidgetsNow() {
        saveWorkTask?.cancel()
        saveWorkTask = nil
        if let data = try? JSONEncoder().encode(widgets) {
            UserDefaults.standard.set(data, forKey: PrefKey.customWidgetsData)
        }
    }

    private func saveWidgets() {
        saveWorkTask?.cancel()
        let snapshot = widgets
        saveWorkTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, self != nil else { return }
            let encoded = await Task.detached(priority: .utility) {
                try? JSONEncoder().encode(snapshot)
            }.value
            guard !Task.isCancelled, let encoded else { return }
            UserDefaults.standard.set(encoded, forKey: PrefKey.customWidgetsData)
        }
    }

    // MARK: - Actions Utilisateur

    func toggleWidget(_ kind: WidgetKind) {
        var updated = widgets
        let shouldEnable: Bool
        if let idx = updated.firstIndex(where: { $0.kind == kind }) {
            shouldEnable = !updated[idx].isEnabled
            updated[idx].isEnabled = shouldEnable
        } else {
            shouldEnable = true
            var newConfig = CustomWidgetConfig(kind: kind, isEnabled: true)
            newConfig.order = updated.count
            updated.append(newConfig)
        }
        if shouldEnable {
            for idx in updated.indices where updated[idx].kind != kind && updated[idx].kind.categoryGroup == kind.categoryGroup {
                updated[idx].isEnabled = false
            }
        }
        normalizeOrders(in: &updated)
        widgets = updated
        saveWidgets()
    }

    func moveWidget(from sourceKind: WidgetKind, to targetKind: WidgetKind) {
        guard sourceKind != targetKind else { return }
        var updated = widgets
        var enabled = updated.filter { $0.isEnabled }.sorted { $0.order < $1.order }
        guard let fromIndex = enabled.firstIndex(where: { $0.kind == sourceKind }),
              let toIndex = enabled.firstIndex(where: { $0.kind == targetKind }) else { return }

        let moved = enabled.remove(at: fromIndex)
        enabled.insert(moved, at: toIndex)

        for (newOrder, item) in enabled.enumerated() {
            if let mainIdx = updated.firstIndex(where: { $0.kind == item.kind }) {
                updated[mainIdx].order = newOrder
            }
        }
        if updated != widgets {
            widgets = updated
            saveWidgets()
        }
    }

    private func normalizeOrders(in list: inout [CustomWidgetConfig]) {
        let enabled = list.filter { $0.isEnabled }.sorted { $0.order < $1.order }
        for (newOrder, item) in enabled.enumerated() {
            if let mainIdx = list.firstIndex(where: { $0.kind == item.kind }) {
                list[mainIdx].order = newOrder
            }
        }
    }

    func calculateLeftShelfWidth(windowWidth: CGFloat) -> CGFloat {
        let enabled = widgets.filter { $0.isEnabled }.sorted { $0.order < $1.order }
        guard !enabled.isEmpty else { return 0 }
        let leftMargin = max(24, windowWidth * 0.03)
        let twoColumns = windowWidth >= 1050 && enabled.count > 2
        if twoColumns {
            let firstCol = enabled.prefix(2)
            let remaining = enabled.dropFirst(2)
            let col1Width = firstCol.map { $0.size.width }.max() ?? 180
            let col2Width = remaining.map { $0.size.width }.max() ?? 0
            return leftMargin + col1Width + 14 + col2Width
        } else {
            let maxColWidth = enabled.map { $0.size.width }.max() ?? 180
            return leftMargin + maxColWidth
        }
    }

    func isEnabled(_ kind: WidgetKind) -> Bool {
        widgets.first(where: { $0.kind == kind })?.isEnabled ?? false
    }

    func config(for kind: WidgetKind) -> CustomWidgetConfig? {
        widgets.first(where: { $0.kind == kind })
    }

    func updateSize(for kind: WidgetKind, size: WidgetSize) {
        guard let idx = widgets.firstIndex(where: { $0.kind == kind }), widgets[idx].size != size else { return }
        var updated = widgets
        updated[idx].size = size
        widgets = updated
        saveWidgets()
    }

    func updateMusicStyle(for kind: WidgetKind, style: MusicWidgetStyle) {
        guard let idx = widgets.firstIndex(where: { $0.kind == kind }), widgets[idx].musicStyle != style else { return }
        var updated = widgets
        updated[idx].musicStyle = style
        widgets = updated
        saveWidgets()
    }

    func updateMusicAppearance(for kind: WidgetKind, appearance: WidgetAppearanceMode) {
        guard let idx = widgets.firstIndex(where: { $0.kind == kind }), widgets[idx].musicAppearance != appearance else { return }
        var updated = widgets
        updated[idx].musicAppearance = appearance
        widgets = updated
        saveWidgets()
    }

    func updateWeatherTheme(_ theme: WeatherWidgetTheme) {
        guard let idx = widgets.firstIndex(where: { $0.kind == .weather }), widgets[idx].weatherTheme != theme else { return }
        var updated = widgets
        updated[idx].weatherTheme = theme
        widgets = updated
        saveWidgets()
    }

    func updateCalendarStyle(_ style: CalendarWidgetStyle) {
        guard let idx = widgets.firstIndex(where: { $0.kind == .calendar }), widgets[idx].calendarStyle != style else { return }
        var updated = widgets
        updated[idx].calendarStyle = style
        widgets = updated
        saveWidgets()
    }

    func updateClockStyle(
        _ style: ClockWidgetStyle,
        format24h: Bool? = nil,
        showSeconds: Bool? = nil,
        showDate: Bool? = nil,
        fontDesign: String? = nil,
        accentColor: String? = nil
    ) {
        guard let idx = widgets.firstIndex(where: { $0.kind == .clock }) else { return }
        var updated = widgets
        updated[idx].clockStyle = style
        if let format24h { updated[idx].clockFormat24h = format24h }
        if let showSeconds { updated[idx].clockShowSeconds = showSeconds }
        if let showDate { updated[idx].clockShowDate = showDate }
        if let fontDesign { updated[idx].clockFontDesign = fontDesign }
        if let accentColor { updated[idx].clockAccentColor = accentColor }
        if updated != widgets {
            widgets = updated
            saveWidgets()
        }
    }

    func updateWeather(city: String, unit: String, temp: Int, condition: String, feelsLike: Int) {
        guard let idx = widgets.firstIndex(where: { $0.kind == .weather }) else { return }
        var updated = widgets
        updated[idx].weatherCity = city
        updated[idx].weatherUnit = unit
        updated[idx].weatherTemp = temp
        updated[idx].weatherCondition = condition
        updated[idx].weatherFeelsLike = feelsLike
        if updated != widgets {
            widgets = updated
            saveWidgets()
        }
    }

    func updateMusic(track: String, artist: String, album: String) {
        var updated = widgets
        for idx in updated.indices where updated[idx].kind == .vinylPlayer || updated[idx].kind == .mediaWide {
            updated[idx].musicTrack = track
            updated[idx].musicArtist = artist
            updated[idx].musicAlbum = album
        }
        if updated != widgets {
            widgets = updated
            saveWidgets()
        }
    }

    func toggleMusicPlayback(for kind: WidgetKind) {
        guard let idx = widgets.firstIndex(where: { $0.kind == kind }) else { return }
        var updated = widgets
        updated[idx].musicIsPlaying.toggle()
        widgets = updated
        saveWidgets()
    }

    func resetWidget(_ kind: WidgetKind) {
        guard let def = Self.defaultWidgets().first(where: { $0.kind == kind }),
              let idx = widgets.firstIndex(where: { $0.kind == kind }) else { return }
        var updated = widgets
        var copy = def
        copy.isEnabled = updated[idx].isEnabled
        copy.order = updated[idx].order
        updated[idx] = copy
        widgets = updated
        saveWidgets()
    }

    func resetToDefaults() {
        self.position = .leftSide
        self.glowColor = .none
        self.cornerRadius = 26.0
        self.glassOpacity = 0.52
        self.widgets = Self.defaultWidgets()
        saveSettings()
    }

    // MARK: - Widgets par Défaut (Style de l'image de référence)

    static func defaultWidgets() -> [CustomWidgetConfig] {
        return [
            // 1. Lecteur Vinyle Marbré Cyan (Photo de Référence 3)
            CustomWidgetConfig(
                kind: .vinylPlayer,
                isEnabled: true,
                size: .medium,
                order: 0,
                musicStyle: .vinylSplatterWide,
                musicTrack: "Red Velvet",
                musicArtist: "Past Alone",
                musicAlbum: "Water (Deluxe)",
                musicIsPlaying: true,
                musicElapsedSeconds: 80,
                musicTotalSeconds: 147
            ),
            // 2. Météo Grand Format (Photo de Référence 5)
            CustomWidgetConfig(
                kind: .weather,
                isEnabled: true,
                size: .tall,
                order: 1,
                weatherTheme: .appleMinimal,
                weatherCity: "Paris",
                weatherUnit: "C",
                weatherTemp: 15,
                weatherCondition: "Cloudy",
                weatherFeelsLike: 14
            ),
            // 3. Lecteur Full Cover + Pilule (Photo de Référence 3)
            CustomWidgetConfig(
                kind: .mediaWide,
                isEnabled: true,
                size: .medium,
                order: 2,
                musicStyle: .fullBleedPill,
                musicTrack: "Red Velvet",
                musicArtist: "Past Alone",
                musicAlbum: "Water (Deluxe)",
                musicIsPlaying: false,
                musicElapsedSeconds: 80,
                musicTotalSeconds: 147
            ),
            // 4. Calendrier Date Compacte (Photo de Référence 6)
            CustomWidgetConfig(
                kind: .calendar,
                isEnabled: false,
                size: .small,
                order: 3,
                calendarStyle: .compactDate
            ),
            // 5. Horloge Apple Analogique Floutée (Photo de Référence 7)
            CustomWidgetConfig(
                kind: .clock,
                isEnabled: false,
                size: .small,
                order: 4,
                clockStyle: .appleAnalog
            ),
            // 6. Moniteur Système
            CustomWidgetConfig(
                kind: .system,
                isEnabled: false,
                size: .medium,
                order: 5
            ),
            // 7. Note Rapide
            CustomWidgetConfig(
                kind: .quickNote,
                isEnabled: false,
                size: .small,
                order: 6
            ),
        ]
    }
}
