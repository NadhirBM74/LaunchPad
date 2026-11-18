import Foundation
import SwiftUI

// MARK: - Types et Modèles de Widgets Personnalisables

nonisolated enum WidgetCategoryGroup: String, Sendable, Equatable {
    case music, weather, calendar, clock, system, quickNote

    var displayName: String {
        switch self {
        case .music: return loc("widget.cat.music")
        case .weather: return loc("widget.cat.weather")
        case .calendar: return loc("widget.cat.calendar")
        case .clock: return loc("widget.cat.clock")
        case .system: return loc("widget.system.title")
        case .quickNote: return loc("widget.quickNote.title")
        }
    }
}

nonisolated enum WidgetAppearanceMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case light = "light"
    case dark = "dark"

    var id: String { rawValue }
    var title: String { loc("widget.appearance.\(rawValue)") }
    var icon: String { self == .light ? "sun.max.fill" : "moon.fill" }
}

nonisolated enum WidgetKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case vinylPlayer      // Lecteur style Disque Vinyle (inspiré de la référence)
    case mediaWide        // Lecteur Multimédia Full Cover / Éditorial
    case weather          // Bibliothèque Météo (18 thèmes)
    case calendar         // Calendrier & Événements (Style Référence)
    case clock            // Collection d'Horloges (15 styles)
    case system           // Moniteur Système CPU / RAM / Batterie
    case quickNote        // Note rapide / To-do list

    var id: String { rawValue }

    var categoryGroup: WidgetCategoryGroup {
        switch self {
        case .vinylPlayer, .mediaWide: return .music
        case .weather: return .weather
        case .calendar: return .calendar
        case .clock: return .clock
        case .system: return .system
        case .quickNote: return .quickNote
        }
    }

    var title: String {
        let key = "widget.\(rawValue).title"
        let localized = loc(key)
        if localized == key {
            switch self {
            case .calendar: return loc("widget.calendar.title")
            default: return rawValue.capitalized
            }
        }
        return localized
    }

    var subtitle: String {
        let key = "widget.\(rawValue).desc"
        let localized = loc(key)
        if localized == key {
            switch self {
            case .calendar: return loc("widget.calendar.desc")
            default: return ""
            }
        }
        return localized
    }

    var defaultSize: WidgetSize {
        switch self {
        case .vinylPlayer: return .medium
        case .mediaWide: return .medium
        case .weather: return .small
        case .calendar: return .small
        case .clock: return .small
        case .system: return .small
        case .quickNote: return .small
        }
    }

    var allowedSizes: [WidgetSize] {
        switch self {
        case .vinylPlayer: return [.small, .medium, .tall, .large]
        case .mediaWide: return [.small, .medium, .tall, .large]
        case .weather: return [.small, .medium, .tall, .large]
        case .calendar: return [.small, .medium, .tall, .large]
        case .clock: return [.small, .medium, .tall, .large]
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
        let label = slotCount <= 1 ? loc("widget.slot.single") : loc("widget.slots")
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
    var id: String // Correspond à widgetKind.rawValue (ou identifiant unique)
    var kind: WidgetKind
    var isEnabled: Bool
    var size: WidgetSize
    var order: Int

    // Thèmes & Styles Visuels par Catégorie
    var musicStyle: MusicWidgetStyle
    var musicAppearance: WidgetAppearanceMode
    var weatherTheme: WeatherWidgetTheme
    var calendarStyle: CalendarWidgetStyle
    var clockStyle: ClockWidgetStyle

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
    var clockShowSeconds: Bool
    var clockShowDate: Bool
    var clockFontDesign: String
    var clockAccentColor: String
    var clockTimezones: [String]

    // Options Note Rapide
    var noteContent: String

    private static let defaultClockTimezones: [String] = ["Europe/Paris", "America/New_York", "Asia/Tokyo", "Europe/London"]

    init(
        id: String? = nil,
        kind: WidgetKind,
        isEnabled: Bool = true,
        size: WidgetSize? = nil,
        order: Int = 0,
        musicStyle: MusicWidgetStyle? = nil,
        musicAppearance: WidgetAppearanceMode = .light,
        weatherTheme: WeatherWidgetTheme = .appleMinimal,
        calendarStyle: CalendarWidgetStyle = .compactDate,
        clockStyle: ClockWidgetStyle = .appleAnalog,
        weatherCity: String = "Paris",
        weatherUnit: String = "C",
        weatherTemp: Int = 15,
        weatherCondition: String = "Cloudy",
        weatherFeelsLike: Int = 14,
        musicTrack: String = "Red Velvet",
        musicArtist: String = "Past Alone",
        musicAlbum: String = "Water (Deluxe)",
        musicIsPlaying: Bool = true,
        musicElapsedSeconds: Int = 80,
        musicTotalSeconds: Int = 147,
        clockFormat24h: Bool = true,
        clockShowGreeting: Bool = true,
        clockShowSeconds: Bool = true,
        clockShowDate: Bool = true,
        clockFontDesign: String = "rounded",
        clockAccentColor: String = "red",
        clockTimezones: [String] = CustomWidgetConfig.defaultClockTimezones,
        noteContent: String = ""
    ) {
        self.id = id ?? kind.rawValue
        self.kind = kind
        self.isEnabled = isEnabled
        self.size = size ?? kind.defaultSize
        self.order = order
        self.musicStyle = musicStyle ?? (kind == .vinylPlayer ? .vinylSplatterWide : .fullBleedPill)
        self.musicAppearance = musicAppearance
        self.weatherTheme = weatherTheme
        self.calendarStyle = calendarStyle
        self.clockStyle = clockStyle
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
        self.clockShowSeconds = clockShowSeconds
        self.clockShowDate = clockShowDate
        self.clockFontDesign = clockFontDesign
        self.clockAccentColor = clockAccentColor
        self.clockTimezones = clockTimezones
        self.noteContent = noteContent
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, isEnabled, size, order
        case musicStyle, musicAppearance, weatherTheme, calendarStyle, clockStyle
        case weatherCity, weatherUnit, weatherTemp, weatherCondition, weatherFeelsLike
        case musicTrack, musicArtist, musicAlbum, musicIsPlaying, musicElapsedSeconds, musicTotalSeconds
        case clockFormat24h, clockShowGreeting, clockShowSeconds, clockShowDate, clockFontDesign, clockAccentColor, clockTimezones
        case noteContent
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let decodedKind = try c.decode(WidgetKind.self, forKey: .kind)
        self.id = try c.decodeIfPresent(String.self, forKey: .id) ?? decodedKind.rawValue
        self.kind = decodedKind
        self.isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        self.size = try c.decodeIfPresent(WidgetSize.self, forKey: .size) ?? decodedKind.defaultSize
        self.order = try c.decodeIfPresent(Int.self, forKey: .order) ?? 0
        self.musicStyle = try c.decodeIfPresent(MusicWidgetStyle.self, forKey: .musicStyle) ?? (decodedKind == .vinylPlayer ? .vinylSplatterWide : .fullBleedPill)
        self.musicAppearance = try c.decodeIfPresent(WidgetAppearanceMode.self, forKey: .musicAppearance) ?? .light
        self.weatherTheme = try c.decodeIfPresent(WeatherWidgetTheme.self, forKey: .weatherTheme) ?? .appleMinimal
        self.calendarStyle = try c.decodeIfPresent(CalendarWidgetStyle.self, forKey: .calendarStyle) ?? .compactDate
        self.clockStyle = try c.decodeIfPresent(ClockWidgetStyle.self, forKey: .clockStyle) ?? .appleAnalog
        self.weatherCity = try c.decodeIfPresent(String.self, forKey: .weatherCity) ?? "Paris"
        self.weatherUnit = try c.decodeIfPresent(String.self, forKey: .weatherUnit) ?? "C"
        self.weatherTemp = try c.decodeIfPresent(Int.self, forKey: .weatherTemp) ?? 15
        self.weatherCondition = try c.decodeIfPresent(String.self, forKey: .weatherCondition) ?? "Cloudy"
        self.weatherFeelsLike = try c.decodeIfPresent(Int.self, forKey: .weatherFeelsLike) ?? 14
        self.musicTrack = try c.decodeIfPresent(String.self, forKey: .musicTrack) ?? "Red Velvet"
        self.musicArtist = try c.decodeIfPresent(String.self, forKey: .musicArtist) ?? "Past Alone"
        self.musicAlbum = try c.decodeIfPresent(String.self, forKey: .musicAlbum) ?? "Water (Deluxe)"
        self.musicIsPlaying = try c.decodeIfPresent(Bool.self, forKey: .musicIsPlaying) ?? true
        self.musicElapsedSeconds = try c.decodeIfPresent(Int.self, forKey: .musicElapsedSeconds) ?? 80
        self.musicTotalSeconds = try c.decodeIfPresent(Int.self, forKey: .musicTotalSeconds) ?? 147
        self.clockFormat24h = try c.decodeIfPresent(Bool.self, forKey: .clockFormat24h) ?? true
        self.clockShowGreeting = try c.decodeIfPresent(Bool.self, forKey: .clockShowGreeting) ?? true
        self.clockShowSeconds = try c.decodeIfPresent(Bool.self, forKey: .clockShowSeconds) ?? true
        self.clockShowDate = try c.decodeIfPresent(Bool.self, forKey: .clockShowDate) ?? true
        self.clockFontDesign = try c.decodeIfPresent(String.self, forKey: .clockFontDesign) ?? "rounded"
        self.clockAccentColor = try c.decodeIfPresent(String.self, forKey: .clockAccentColor) ?? "red"
        self.clockTimezones = try c.decodeIfPresent([String].self, forKey: .clockTimezones) ?? Self.defaultClockTimezones
        self.noteContent = try c.decodeIfPresent(String.self, forKey: .noteContent) ?? ""
    }
}
