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

    private init() {
        loadSettings()
    }

    // MARK: - Chargement & Sauvegarde

    func loadSettings() {
        let defaults = UserDefaults.standard

        // Position
        if let posRaw = defaults.string(forKey: PrefKey.widgetPosition),
           let pos = WidgetPosition(rawValue: posRaw) {
            self.position = pos
        } else {
            self.position = .leftSide
        }

        // Lueur
        if let glowRaw = defaults.string(forKey: PrefKey.widgetGlowColor),
           let glow = WidgetGlowColor(rawValue: glowRaw) {
            self.glowColor = glow
        } else {
            self.glowColor = .none
        }

        // Coins arrondis
        let radius = defaults.double(forKey: PrefKey.widgetCornerRadius)
        self.cornerRadius = radius > 0 ? CGFloat(radius) : 26.0

        // Opacité du verre
        let opacity = defaults.double(forKey: PrefKey.widgetGlassOpacity)
        self.glassOpacity = opacity > 0 ? opacity : 0.52

        // Widgets
        if let data = defaults.data(forKey: PrefKey.customWidgetsData),
           var decoded = try? JSONDecoder().decode([CustomWidgetConfig].self, from: data),
           !decoded.isEmpty {
            // S'assure que tous les types de widgets (dont Calendrier) existent dans la liste
            for def in Self.defaultWidgets() where !decoded.contains(where: { $0.kind == def.kind }) {
                var copy = def
                copy.order = decoded.count
                decoded.append(copy)
            }
            self.widgets = decoded
        } else {
            self.widgets = Self.defaultWidgets()
            saveWidgets()
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

    private func saveWidgets() {
        if let data = try? JSONEncoder().encode(widgets) {
            UserDefaults.standard.set(data, forKey: PrefKey.customWidgetsData)
        }
    }

    // MARK: - Actions Utilisateur

    func toggleWidget(_ kind: WidgetKind) {
        if let idx = widgets.firstIndex(where: { $0.kind == kind }) {
            widgets[idx].isEnabled.toggle()
        } else {
            var newConfig = CustomWidgetConfig(kind: kind, isEnabled: true)
            newConfig.order = widgets.count
            widgets.append(newConfig)
        }
        normalizeOrders()
        saveWidgets()
    }

    func moveWidget(from sourceKind: WidgetKind, to targetKind: WidgetKind) {
        guard sourceKind != targetKind else { return }
        var enabled = widgets.filter { $0.isEnabled }.sorted { $0.order < $1.order }
        guard let fromIndex = enabled.firstIndex(where: { $0.kind == sourceKind }),
              let toIndex = enabled.firstIndex(where: { $0.kind == targetKind }) else { return }

        let moved = enabled.remove(at: fromIndex)
        enabled.insert(moved, at: toIndex)

        for (newOrder, item) in enabled.enumerated() {
            if let mainIdx = widgets.firstIndex(where: { $0.kind == item.kind }) {
                widgets[mainIdx].order = newOrder
            }
        }
        saveWidgets()
    }

    private func normalizeOrders() {
        let enabled = widgets.filter { $0.isEnabled }.sorted { $0.order < $1.order }
        for (newOrder, item) in enabled.enumerated() {
            if let mainIdx = widgets.firstIndex(where: { $0.kind == item.kind }) {
                widgets[mainIdx].order = newOrder
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
        guard let idx = widgets.firstIndex(where: { $0.kind == kind }) else { return }
        widgets[idx].size = size
        saveWidgets()
    }

    func updateMusicStyle(for kind: WidgetKind, style: MusicWidgetStyle) {
        guard let idx = widgets.firstIndex(where: { $0.kind == kind }) else { return }
        widgets[idx].musicStyle = style
        saveWidgets()
    }

    func updateWeatherTheme(_ theme: WeatherWidgetTheme) {
        guard let idx = widgets.firstIndex(where: { $0.kind == .weather }) else { return }
        widgets[idx].weatherTheme = theme
        saveWidgets()
    }

    func updateCalendarStyle(_ style: CalendarWidgetStyle) {
        guard let idx = widgets.firstIndex(where: { $0.kind == .calendar }) else { return }
        widgets[idx].calendarStyle = style
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
        widgets[idx].clockStyle = style
        if let format24h { widgets[idx].clockFormat24h = format24h }
        if let showSeconds { widgets[idx].clockShowSeconds = showSeconds }
        if let showDate { widgets[idx].clockShowDate = showDate }
        if let fontDesign { widgets[idx].clockFontDesign = fontDesign }
        if let accentColor { widgets[idx].clockAccentColor = accentColor }
        saveWidgets()
    }

    func updateWeather(city: String, unit: String, temp: Int, condition: String, feelsLike: Int) {
        guard let idx = widgets.firstIndex(where: { $0.kind == .weather }) else { return }
        widgets[idx].weatherCity = city
        widgets[idx].weatherUnit = unit
        widgets[idx].weatherTemp = temp
        widgets[idx].weatherCondition = condition
        widgets[idx].weatherFeelsLike = feelsLike
        saveWidgets()
    }

    func updateMusic(track: String, artist: String, album: String) {
        for idx in widgets.indices where widgets[idx].kind == .vinylPlayer || widgets[idx].kind == .mediaWide {
            widgets[idx].musicTrack = track
            widgets[idx].musicArtist = artist
            widgets[idx].musicAlbum = album
        }
        saveWidgets()
    }

    func toggleMusicPlayback(for kind: WidgetKind) {
        guard let idx = widgets.firstIndex(where: { $0.kind == kind }) else { return }
        widgets[idx].musicIsPlaying.toggle()
        saveWidgets()
    }

    func resetWidget(_ kind: WidgetKind) {
        guard let def = Self.defaultWidgets().first(where: { $0.kind == kind }),
              let idx = widgets.firstIndex(where: { $0.kind == kind }) else { return }
        let wasEnabled = widgets[idx].isEnabled
        let order = widgets[idx].order
        widgets[idx] = def
        widgets[idx].isEnabled = wasEnabled
        widgets[idx].order = order
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
                weatherCity: "New York",
                weatherUnit: "F",
                weatherTemp: 69,
                weatherCondition: "Rainy",
                weatherFeelsLike: 69
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
