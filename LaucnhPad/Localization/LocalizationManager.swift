import Foundation
import Combine
import SwiftUI
import os

nonisolated private final class LanguageSnapshot: @unchecked Sendable {
    let code: String
    let locale: Locale
    let strings: [String: String]

    nonisolated private init(code: String, locale: Locale, strings: [String: String]) {
        self.code = code
        self.locale = locale
        self.strings = strings
    }

    nonisolated static func make(code: String) -> LanguageSnapshot {
        // Pré-fusionne une seule fois les tables de secours (EN → FR → langue active)
        // afin que chaque appel `loc()` effectue une unique recherche O(1) dans un dictionnaire plat.
        let primary = Translations.table(for: code)
        var merged = Translations_EN.strings
        for (k, v) in Translations_FR.strings { merged[k] = v }
        if code != "fr" {
            for (k, v) in primary { merged[k] = v }
        }
        return LanguageSnapshot(
            code: code,
            locale: Locale(identifier: code),
            strings: merged
        )
    }
}

/// État de langue thread-safe avec chemin rapide sans verrou sur le thread principal (`@MainActor`).
nonisolated private final class LanguageState: @unchecked Sendable {
    nonisolated static let shared = LanguageState()
    private let lock: OSAllocatedUnfairLock<LanguageSnapshot>
    /// Copie miroir lue uniquement sur le thread principal (zéro acquisition de verrou sur 100 % des rendus UI).
    nonisolated(unsafe) private var mainThreadSnapshot: LanguageSnapshot

    nonisolated init() {
        let saved = UserDefaults.standard.string(forKey: PrefKey.appLanguage)
            ?? UserDefaults.standard.string(forKey: "appLanguage")
            ?? "auto"
        let lang = AppLanguage(rawValue: saved) ?? .auto
        let initial = LanguageSnapshot.make(code: lang.code)
        self.lock = OSAllocatedUnfairLock(initialState: initial)
        self.mainThreadSnapshot = initial
    }

    @inline(__always)
    nonisolated func snapshot() -> LanguageSnapshot {
        if Thread.isMainThread {
            return mainThreadSnapshot
        }
        return lock.withLock { $0 }
    }

    @inline(__always)
    nonisolated func get() -> String {
        snapshot().code
    }

    nonisolated func set(_ newCode: String) {
        let currentCode = lock.withLock { $0.code }
        guard currentCode != newCode else { return }
        let next = LanguageSnapshot.make(code: newCode)
        lock.withLock { $0 = next }
        if Thread.isMainThread {
            mainThreadSnapshot = next
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.mainThreadSnapshot = next
            }
        }
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

/// Helper global de traduction (chemin sans verrou sur le thread principal, 1 seul lookup O(1))
@inline(__always)
nonisolated func loc(_ key: String) -> String {
    LanguageState.shared.snapshot().strings[key] ?? key
}

/// Helper global de traduction avec arguments (non isolé)
nonisolated func loc(_ key: String, _ args: CVarArg...) -> String {
    let snap = LanguageState.shared.snapshot()
    let format = snap.strings[key] ?? key
    return String(format: format, locale: snap.locale, arguments: args)
}
