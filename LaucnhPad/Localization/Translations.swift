import Foundation

/// Registre des traductions par code de langue avec système de secours.
nonisolated enum Translations: Sendable {
    nonisolated static func string(for key: String, languageCode: String) -> String {
        let dict: [String: String]
        switch languageCode {
        case "fr": dict = Translations_FR.strings
        case "en": dict = Translations_EN.strings
        case "es": dict = Translations_ES.strings
        case "de": dict = Translations_DE.strings
        case "it": dict = Translations_IT.strings
        case "pt": dict = Translations_PT.strings
        default: dict = Translations_FR.strings
        }

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
