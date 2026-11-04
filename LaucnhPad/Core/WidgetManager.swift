import Foundation
import SwiftUI
import Combine

/// Gestionnaire de widgets personnalisables (Version Pro)
@MainActor
final class WidgetManager: ObservableObject {
    static let shared = WidgetManager()

    @Published var widgets: [CustomWidgetConfig] = []
    @Published var position: WidgetPosition = .leftSide
    @Published var glowColor: WidgetGlowColor = .cyan
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
            self.glowColor = .cyan
        }

        // Coins arrondis
        let radius = defaults.double(forKey: PrefKey.widgetCornerRadius)
        self.cornerRadius = radius > 0 ? CGFloat(radius) : 26.0

        // Opacité du verre
        let opacity = defaults.double(forKey: PrefKey.widgetGlassOpacity)
        self.glassOpacity = opacity > 0 ? opacity : 0.52

        // Widgets
        if let data = defaults.data(forKey: PrefKey.customWidgetsData),
           let decoded = try? JSONDecoder().decode([CustomWidgetConfig].self, from: data),
           !decoded.isEmpty {
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

    func resetToDefaults() {
        self.position = .leftSide
        self.glowColor = .cyan
        self.cornerRadius = 26.0
        self.glassOpacity = 0.52
        self.widgets = Self.defaultWidgets()
        saveSettings()
    }

    // MARK: - Widgets par Défaut (Style de l'image de référence)

    static func defaultWidgets() -> [CustomWidgetConfig] {
        return [
            // 1. Lecteur Vinyle (Haut gauche)
            CustomWidgetConfig(
                kind: .vinylPlayer,
                isEnabled: true,
                size: .medium,
                order: 0,
                musicTrack: "Supercut",
                musicArtist: "Lorde",
                musicAlbum: "Melodrama",
                musicIsPlaying: true,
                musicElapsedSeconds: 43,
                musicTotalSeconds: 192
            ),
            // 2. Météo Grand Format (Bas gauche)
            CustomWidgetConfig(
                kind: .weather,
                isEnabled: true,
                size: .tall,
                order: 1,
                weatherCity: "New York",
                weatherUnit: "F",
                weatherTemp: 69,
                weatherCondition: "Cloudy",
                weatherFeelsLike: 68
            ),
            // 3. Lecteur Horizontal Complet
            CustomWidgetConfig(
                kind: .mediaWide,
                isEnabled: true,
                size: .medium,
                order: 2,
                musicTrack: "Red Velvet",
                musicArtist: "Past Alone",
                musicAlbum: "Water (Deluxe)",
                musicIsPlaying: false,
                musicElapsedSeconds: 6,
                musicTotalSeconds: 257
            ),
            // 4. Horloge Apple Style
            CustomWidgetConfig(
                kind: .clock,
                isEnabled: false,
                size: .small,
                order: 3
            ),
            // 5. Moniteur Système
            CustomWidgetConfig(
                kind: .system,
                isEnabled: false,
                size: .medium,
                order: 4
            ),
            // 6. Note Rapide
            CustomWidgetConfig(
                kind: .quickNote,
                isEnabled: false,
                size: .small,
                order: 5
            ),
        ]
    }
}
