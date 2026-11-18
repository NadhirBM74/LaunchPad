import Foundation

/// Registre des traductions par code de langue avec système de secours.
nonisolated enum Translations: Sendable {
    nonisolated static func table(for languageCode: String) -> [String: String] {
        switch languageCode {
        case "fr": return Translations_FR.strings
        case "en": return Translations_EN.strings
        case "es": return Translations_ES.strings
        case "de": return Translations_DE.strings
        case "it": return Translations_IT.strings
        case "pt": return Translations_PT.strings
        default: return Translations_FR.strings
        }
    }

    nonisolated static func string(for key: String, languageCode: String) -> String {
        let dict = table(for: languageCode)
        if let translation = dict[key] {
            return translation
        }
        if let fallbackFr = Translations_FR.strings[key] {
            return fallbackFr
        }
        if let fallbackEn = Translations_EN.strings[key] {
            return fallbackEn
        }
        return key
    }
}
