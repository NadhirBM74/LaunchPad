import Foundation
import Combine
import SwiftUI
import os

private struct LanguageSnapshot: Sendable {
    let code: String
    let locale: Locale
    let strings: [String: String]

    nonisolated static func make(code: String) -> LanguageSnapshot {
        LanguageSnapshot(
            code: code,
            locale: Locale(identifier: code),
            strings: Translations.table(for: code)
        )
    }
}

/// État de langue thread-safe et sans contention accessible depuis n'importe quel contexte
nonisolated private final class LanguageState: @unchecked Sendable {
    nonisolated static let shared = LanguageState()
    private let lock: OSAllocatedUnfairLock<LanguageSnapshot>

    nonisolated init() {
        let saved = UserDefaults.standard.string(forKey: PrefKey.appLanguage)
            ?? UserDefaults.standard.string(forKey: "appLanguage")
            ?? "auto"
        let lang = AppLanguage(rawValue: saved) ?? .auto
        self.lock = OSAllocatedUnfairLock(initialState: LanguageSnapshot.make(code: lang.code))
    }

    nonisolated func snapshot() -> LanguageSnapshot {
        lock.withLock { $0 }
    }

    nonisolated func get() -> String {
        lock.withLock { $0.code }
    }

    nonisolated func set(_ newCode: String) {
        let next = LanguageSnapshot.make(code: newCode)
        lock.withLock { $0 = next }
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
            guard currentLanguage != oldValue else { return }
            Prefs.defaults.set(currentLanguage.rawValue, forKey: PrefKey.appLanguage)
            updateEffectiveLanguage()
        }
    }

    @Published private(set) var effectiveLanguageCode: String = "fr"
    private(set) var effectiveLocale: Locale = Locale(identifier: "fr")
    private lazy var decimalFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = effectiveLocale
        return f
    }()

    private init() {
        let saved = Prefs.defaults.string(forKey: PrefKey.appLanguage) ?? AppLanguage.auto.rawValue
        let lang = AppLanguage(rawValue: saved) ?? .auto
        let resolvedCode = lang.code
        self.currentLanguage = lang
        self.effectiveLanguageCode = resolvedCode
        self.effectiveLocale = Locale(identifier: resolvedCode)
        LanguageState.shared.set(resolvedCode)
    }

    func updateEffectiveLanguage() {
        let code = currentLanguage.code
        if code != effectiveLanguageCode {
            self.effectiveLanguageCode = code
            self.effectiveLocale = Locale(identifier: code)
            self.decimalFormatter.locale = self.effectiveLocale
            LanguageState.shared.set(code)
        }
    }

    func localizedString(_ key: String) -> String {
        loc(key)
    }

    func formatNumber(_ number: Int) -> String {
        decimalFormatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }
}

/// Helper global de traduction (non isolé pour être thread-safe et utilisable depuis tout contexte)
nonisolated func loc(_ key: String) -> String {
    let snap = LanguageState.shared.snapshot()
    if let translation = snap.strings[key] {
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

/// Helper global de traduction avec arguments (non isolé)
nonisolated func loc(_ key: String, _ args: CVarArg...) -> String {
    let snap = LanguageState.shared.snapshot()
    let format = snap.strings[key]
        ?? Translations_FR.strings[key]
        ?? Translations_EN.strings[key]
        ?? key
    return String(format: format, locale: snap.locale, arguments: args)
}
