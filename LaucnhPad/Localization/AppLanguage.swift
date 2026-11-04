import Foundation

/// Langues prises en charge par l'application.
nonisolated enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case auto = "auto"
    case fr = "fr"
    case en = "en"
    case es = "es"
    case de = "de"
    case it = "it"
    case pt = "pt"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return loc("lang.auto")
        case .fr: return "Français"
        case .en: return "English"
        case .es: return "Español"
        case .de: return "Deutsch"
        case .it: return "Italiano"
        case .pt: return "Português"
        }
    }

    /// Code ISO résolu (2 lettres)
    var code: String {
        switch self {
        case .auto:
            return AppLanguage.resolveSystemLanguageCode()
        case .fr, .en, .es, .de, .it, .pt:
            return rawValue
        }
    }

    static func resolveSystemLanguageCode() -> String {
        let preferred = Locale.preferredLanguages
        for lang in preferred {
            let lower = lang.lowercased()
            if lower.hasPrefix("fr") { return "fr" }
            if lower.hasPrefix("en") { return "en" }
            if lower.hasPrefix("es") { return "es" }
            if lower.hasPrefix("de") { return "de" }
            if lower.hasPrefix("it") { return "it" }
            if lower.hasPrefix("pt") { return "pt" }
        }
        return "fr"
    }
}
