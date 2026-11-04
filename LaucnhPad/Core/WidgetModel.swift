import Foundation
import SwiftUI

// MARK: - Types et Modèles de Widgets Personnalisables

nonisolated enum WidgetKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case vinylPlayer      // Lecteur style Disque Vinyle (inspiré de la référence)
    case weather          // Carte Météo grand format typographique
    case mediaWide        // Lecteur Multimédia horizontal complet
    case clock            // Horloge & Date Apple Style
    case system           // Moniteur Système CPU / RAM / Batterie
    case quickNote        // Note rapide / To-do list

    var id: String { rawValue }

    var title: String {
        loc("widget.\(rawValue).title")
    }

    var subtitle: String {
        loc("widget.\(rawValue).desc")
    }

    var defaultSize: WidgetSize {
        switch self {
        case .vinylPlayer: return .medium
        default: return .small
        }
    }

    var allowedSizes: [WidgetSize] {
        switch self {
        case .vinylPlayer: return [.small, .medium, .tall]
        case .weather: return [.small, .medium, .tall]
        case .mediaWide: return [.small, .medium, .tall, .large]
        case .clock: return [.small, .medium]
        case .system: return [.small, .medium]
        case .quickNote: return [.small, .medium]
        }
    }
}

nonisolated enum WidgetSize: String, Codable, CaseIterable, Identifiable, Sendable {
    case small   // Format compact carré ~150x150 (1x1)
    case medium  // Format bannière ~300x150 (2x1)
    case tall    // Vertical haut ~150x310 (2x4)
    case large   // Grand format ~310x310 (4x4)

    var id: String { rawValue }

    var title: String {
        loc("widget.size.\(rawValue)")
    }

    var width: CGFloat {
        switch self {
        case .small: return 150
        case .medium: return 300
        case .tall: return 150
        case .large: return 310
        }
    }

    var height: CGFloat {
        switch self {
        case .small: return 150
        case .medium: return 150
        case .tall: return 310
        case .large: return 310
        }
    }

    /// Nombre de colonnes et de rangées d'applications occupées sur la grille
    nonisolated func span(maxColumns: Int, maxRows: Int) -> (cols: Int, rows: Int) {
        switch self {
        case .small:
            // Petit : 1 emplacement d'application (1x1)
            return (min(1, maxColumns), min(1, maxRows))
        case .medium:
            // Moyen : 2 emplacements d'application (2x1)
            return (min(2, maxColumns), min(1, maxRows))
        case .tall:
            // Haut : 8 emplacements verticaux (2x4)
            return (min(2, maxColumns), min(4, maxRows))
        case .large:
            // Grand : davantage d'emplacements (4x4 = 16 emplacements)
            return (min(4, maxColumns), min(4, maxRows))
        }
    }

    /// Nombre total d'emplacements d'application occupés
    nonisolated var slotCount: Int {
        switch self {
        case .small: return 1
        case .medium: return 2
        case .tall: return 8
        case .large: return 16
        }
    }

    var slotDescription: String {
        let label = slotCount <= 1 ? (loc("widget.slot.single") == "widget.slot.single" ? "emplacement" : loc("widget.slot.single")) : loc("widget.slots")
        switch self {
        case .small: return "1×1 (\(slotCount) \(label))"
        case .medium: return "2×1 (\(slotCount) \(label))"
        case .tall: return "2×4 (\(slotCount) \(label))"
        case .large: return "4×4 (\(slotCount) \(label))"
        }
    }
}

nonisolated enum WidgetPosition: String, Codable, CaseIterable, Identifiable, Sendable {
    case leftSide   // Volet latéral gauche (comme sur la capture de référence)
    case topBanner  // Bandeau supérieur au-dessus de la recherche

    var id: String { rawValue }

    var title: String {
        loc("widget.position.\(rawValue)")
    }
}

nonisolated enum WidgetGlowColor: String, Codable, CaseIterable, Identifiable, Sendable {
    case cyan     // Bleu néon électrique
    case amber    // Ambre / Orange chaleureux
    case white    // Blanc givré
    case purple   // Violet néon
    case none     // Discret sans lueur

    var id: String { rawValue }

    var title: String {
        loc("widget.glow.\(rawValue)")
    }

    var primaryColor: Color {
        switch self {
        case .cyan: return Color(red: 0.20, green: 0.85, blue: 1.00)
        case .amber: return Color(red: 1.00, green: 0.60, blue: 0.20)
        case .white: return Color.white
        case .purple: return Color(red: 0.75, green: 0.45, blue: 1.00)
        case .none: return Color.clear
        }
    }
}

// MARK: - Configuration Individuelle d'un Widget

nonisolated struct CustomWidgetConfig: Codable, Identifiable, Sendable, Equatable, Hashable {
    var id: String // Correspond à widgetKind.rawValue
    var kind: WidgetKind
    var isEnabled: Bool
    var size: WidgetSize
    var order: Int

    // Options Météo
    var weatherCity: String
    var weatherUnit: String // "C" ou "F"
    var weatherTemp: Int
    var weatherCondition: String // "Cloudy", "Sunny", "Rainy", "Clear"
    var weatherFeelsLike: Int

    // Options Musique
    var musicTrack: String
    var musicArtist: String
    var musicAlbum: String
    var musicIsPlaying: Bool
    var musicElapsedSeconds: Int
    var musicTotalSeconds: Int

    // Options Horloge
    var clockFormat24h: Bool
    var clockShowGreeting: Bool

    // Options Note Rapide
    var noteContent: String

    init(
        kind: WidgetKind,
        isEnabled: Bool = true,
        size: WidgetSize? = nil,
        order: Int = 0,
        weatherCity: String = "New York",
        weatherUnit: String = "F",
        weatherTemp: Int = 69,
        weatherCondition: String = "Cloudy",
        weatherFeelsLike: Int = 68,
        musicTrack: String = "Past Alone",
        musicArtist: String = "Red Velvet",
        musicAlbum: String = "Water (Deluxe)",
        musicIsPlaying: Bool = true,
        musicElapsedSeconds: Int = 43,
        musicTotalSeconds: Int = 192,
        clockFormat24h: Bool = true,
        clockShowGreeting: Bool = true,
        noteContent: String = ""
    ) {
        self.id = kind.rawValue
        self.kind = kind
        self.isEnabled = isEnabled
        self.size = size ?? kind.defaultSize
        self.order = order
        self.weatherCity = weatherCity
        self.weatherUnit = weatherUnit
        self.weatherTemp = weatherTemp
        self.weatherCondition = weatherCondition
        self.weatherFeelsLike = weatherFeelsLike
        self.musicTrack = musicTrack
        self.musicArtist = musicArtist
        self.musicAlbum = musicAlbum
        self.musicIsPlaying = musicIsPlaying
        self.musicElapsedSeconds = musicElapsedSeconds
        self.musicTotalSeconds = musicTotalSeconds
        self.clockFormat24h = clockFormat24h
        self.clockShowGreeting = clockShowGreeting
        self.noteContent = noteContent
    }

    nonisolated static func == (lhs: CustomWidgetConfig, rhs: CustomWidgetConfig) -> Bool {
        lhs.id == rhs.id &&
        lhs.kind == rhs.kind &&
        lhs.isEnabled == rhs.isEnabled &&
        lhs.size == rhs.size &&
        lhs.order == rhs.order &&
        lhs.weatherCity == rhs.weatherCity &&
        lhs.weatherUnit == rhs.weatherUnit &&
        lhs.weatherTemp == rhs.weatherTemp &&
        lhs.weatherCondition == rhs.weatherCondition &&
        lhs.weatherFeelsLike == rhs.weatherFeelsLike &&
        lhs.musicTrack == rhs.musicTrack &&
        lhs.musicArtist == rhs.musicArtist &&
        lhs.musicAlbum == rhs.musicAlbum &&
        lhs.musicIsPlaying == rhs.musicIsPlaying &&
        lhs.musicElapsedSeconds == rhs.musicElapsedSeconds &&
        lhs.musicTotalSeconds == rhs.musicTotalSeconds &&
        lhs.clockFormat24h == rhs.clockFormat24h &&
        lhs.clockShowGreeting == rhs.clockShowGreeting &&
        lhs.noteContent == rhs.noteContent
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(kind)
        hasher.combine(isEnabled)
        hasher.combine(size)
        hasher.combine(order)
        hasher.combine(weatherCity)
        hasher.combine(weatherUnit)
        hasher.combine(weatherTemp)
        hasher.combine(weatherCondition)
        hasher.combine(weatherFeelsLike)
        hasher.combine(musicTrack)
        hasher.combine(musicArtist)
        hasher.combine(musicAlbum)
        hasher.combine(musicIsPlaying)
        hasher.combine(musicElapsedSeconds)
        hasher.combine(musicTotalSeconds)
        hasher.combine(clockFormat24h)
        hasher.combine(clockShowGreeting)
        hasher.combine(noteContent)
    }
}
