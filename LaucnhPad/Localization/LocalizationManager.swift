import Foundation
import Combine
import SwiftUI

/// État de langue thread-safe accessible depuis n'importe quel contexte
nonisolated private final class LanguageState: @unchecked Sendable {
    nonisolated static let shared = LanguageState()
    private let lock = NSLock()
    private var code: String

    nonisolated init() {
        let saved = UserDefaults.standard.string(forKey: "appLanguage") ?? "auto"
        let lang = AppLanguage(rawValue: saved) ?? .auto
        self.code = lang.code
    }

    nonisolated func get() -> String {
        lock.lock()
        defer { lock.unlock() }
        return code
    }

    nonisolated func set(_ newCode: String) {
        lock.lock()
        defer { lock.unlock() }
        code = newCode
    }
}

/// Gestionnaire central de la localisation et des langues.
@MainActor
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    nonisolated static var activeLanguageCode: String {
        LanguageState.shared.get()
    }

    @Published var currentLanguage: AppLanguage {
        didSet {
            Prefs.defaults.set(currentLanguage.rawValue, forKey: PrefKey.appLanguage)
            updateEffectiveLanguage()
        }
    }

    @Published private(set) var effectiveLanguageCode: String = "fr"

    var effectiveLocale: Locale {
        Locale(identifier: effectiveLanguageCode)
    }

    private init() {
        let saved = Prefs.defaults.string(forKey: PrefKey.appLanguage) ?? AppLanguage.auto.rawValue
        let lang = AppLanguage(rawValue: saved) ?? .auto
        self.currentLanguage = lang
        self.effectiveLanguageCode = lang.code
        LanguageState.shared.set(lang.code)
    }

    func updateEffectiveLanguage() {
        let code = currentLanguage.code
        self.effectiveLanguageCode = code
        LanguageState.shared.set(code)
        objectWillChange.send()
    }

    func localizedString(_ key: String) -> String {
        Translations.string(for: key, languageCode: effectiveLanguageCode)
    }

    func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = effectiveLocale
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }
}

/// Helper global de traduction (non isolé pour être thread-safe et utilisable depuis tout contexte)
nonisolated func loc(_ key: String) -> String {
    Translations.string(for: key, languageCode: LanguageState.shared.get())
}

/// Helper global de traduction avec arguments (non isolé)
nonisolated func loc(_ key: String, _ args: CVarArg...) -> String {
    let code = LanguageState.shared.get()
    let format = Translations.string(for: key, languageCode: code)
    return String(format: format, locale: Locale(identifier: code), arguments: args)
}
