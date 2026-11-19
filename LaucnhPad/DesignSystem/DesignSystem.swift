import SwiftUI
import AppKit

// MARK: - Design System Global (Inspiré de l'écosystème Apple & Références Visuelles)

enum AppleDesignSystem {

    // MARK: - Couleurs de Référence

    enum Palette {
        // Icônes & Surfaces Sombres (Photo 1 & Photo 4)
        static let iconDarkTop = Color(red: 0.14, green: 0.14, blue: 0.16)
        static let iconDarkBottom = Color(red: 0.06, green: 0.06, blue: 0.08)

        // Icônes & Surfaces Claires (Photo 1 & Photo 2)
        static let iconLightTop = Color(red: 0.99, green: 0.99, blue: 1.00)
        static let iconLightBottom = Color(red: 0.92, green: 0.92, blue: 0.95)

        // Icônes Teintées (Photo 1 - Tinted)
        static let iconTintedTop = Color(red: 0.04, green: 0.11, blue: 0.20)
        static let iconTintedBottom = Color(red: 0.01, green: 0.04, blue: 0.09)

        // Calendrier & Horloge (Photo 2, Photo 6 & Photo 7)
        static let calendarRed = Color(red: 1.00, green: 0.18, blue: 0.24)
        static let calendarHeaderRed = Color(red: 1.00, green: 0.15, blue: 0.30)
        static let calendarStoneBody = Color(red: 0.56, green: 0.53, blue: 0.51)
        static let calendarDarkNavy = Color(red: 0.06, green: 0.09, blue: 0.15)
        static let clockBlack = Color(red: 0.03, green: 0.03, blue: 0.04)
        static let clockPillGray = Color(red: 0.18, green: 0.18, blue: 0.20)

        // Météo (Photo 5)
        static let weatherObsidian = Color(red: 0.05, green: 0.07, blue: 0.12)
        static let weatherCopperGlow = Color(red: 0.72, green: 0.42, blue: 0.22)
        static let weatherPastelPink = Color(red: 0.96, green: 0.78, blue: 1.00)
        static let weatherSunnyYellow = Color(red: 0.99, green: 0.89, blue: 0.48)
        static let weatherSteelBlue = Color(red: 0.36, green: 0.52, blue: 0.66)
        static let weatherSunsetTop = Color(red: 0.55, green: 0.44, blue: 0.68)
        static let weatherSunsetBottom = Color(red: 0.95, green: 0.48, blue: 0.32)
        static let weatherEarthHill = Color(red: 0.48, green: 0.29, blue: 0.12)
        static let weatherSunOrange = Color(red: 1.00, green: 0.30, blue: 0.05)

        // Musique (Photo 3)
        static let musicFrostedCard = Color(red: 0.88, green: 0.89, blue: 0.90)
        static let musicFrostedCardLight = Color(red: 0.94, green: 0.94, blue: 0.95)
        static let musicRedVelvet = Color(red: 0.84, green: 0.18, blue: 0.04)
    }

    // MARK: - Animations Fluides & Naturelles

    enum Springs {
        static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.80)
        static let smooth = Animation.spring(response: 0.38, dampingFraction: 0.84)
        static let gentle = Animation.spring(response: 0.48, dampingFraction: 0.86)
        static let bouncy = Animation.spring(response: 0.42, dampingFraction: 0.68)
    }

    // MARK: - Forme Squircle Continue (Rayon Apple ~22.5%)

    static func squircle(for size: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
    }

    // MARK: - Bordures Spéculaires de Verre

    static func glassRimGradient(opacity: Double = 1.0) -> LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color.white.opacity(0.75 * opacity), location: 0.0),
                .init(color: Color.white.opacity(0.28 * opacity), location: 0.35),
                .init(color: Color.white.opacity(0.08 * opacity), location: 0.70),
                .init(color: Color.white.opacity(0.38 * opacity), location: 1.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func diagonalGlassSheen(opacity: Double = 1.0) -> LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color.white.opacity(0.38 * opacity), location: 0.0),
                .init(color: Color.white.opacity(0.14 * opacity), location: 0.28),
                .init(color: Color.clear, location: 0.52),
                .init(color: Color.white.opacity(0.08 * opacity), location: 0.78),
                .init(color: Color.white.opacity(0.22 * opacity), location: 1.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Badge Vérifié Animé (Violet Pro / Jaune Essai)

/// Badge officiel en rosace crénelée animé : seuls les pics extérieurs tournent, la coche centrale reste fixe.
/// Violet lumineux pour LaunchPad Pro, jaune doré pendant l'essai gratuit.
struct AnimatedVerifiedSealBadge: View {
    let isTrial: Bool
    var size: CGFloat = 24

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage(PrefKey.reduceMotion) private var userReduceMotion = false
    @State private var spinning = false

    private var reduceMotion: Bool {
        systemReduceMotion || userReduceMotion
    }

    private static let trialBadgeGradient = LinearGradient(
        colors: [
            Color(red: 1.00, green: 0.86, blue: 0.16),
            Color(red: 0.96, green: 0.65, blue: 0.00)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private static let proBadgeGradient = LinearGradient(
        colors: [
            Color(red: 0.72, green: 0.38, blue: 0.94),
            Color(red: 0.52, green: 0.22, blue: 0.80)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private static let trialGlowGradient = RadialGradient(
        colors: [
            Color(red: 1.00, green: 0.78, blue: 0.05).opacity(0.28),
            Color(red: 1.00, green: 0.78, blue: 0.05).opacity(0.08),
            Color.clear
        ],
        center: .center,
        startRadius: 0,
        endRadius: 24
    )

    private static let proGlowGradient = RadialGradient(
        colors: [
            Color(red: 0.68, green: 0.36, blue: 0.88).opacity(0.28),
            Color(red: 0.68, green: 0.36, blue: 0.88).opacity(0.08),
            Color.clear
        ],
        center: .center,
        startRadius: 0,
        endRadius: 24
    )

    private var glowColor: Color {
        isTrial
            ? Color(red: 1.00, green: 0.78, blue: 0.05)
            : Color(red: 0.68, green: 0.36, blue: 0.88)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(isTrial ? Self.trialGlowGradient : Self.proGlowGradient)
                .frame(width: size * 1.32, height: size * 1.32)

            // Seule la rosace extérieure tourne sur le GPU CoreAnimation sans réévaluer SwiftUI à 120 Hz
            Rectangle()
                .fill(isTrial ? Self.trialBadgeGradient : Self.proBadgeGradient)
                .frame(width: size * 1.12, height: size * 1.12)
                .mask(
                    Image(systemName: "seal.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: size, height: size)
                        .rotationEffect(.degrees(spinning && !reduceMotion ? 360 : 0))
                        .animation(
                            reduceMotion ? nil : .linear(duration: 8.0).repeatForever(autoreverses: false),
                            value: spinning
                        )
                )
                .drawingGroup()
                .shadow(color: glowColor.opacity(0.45), radius: max(2.0, size * 0.15), y: 1.2)

            // Le "V" (coche blanche) au milieu reste strictement immobile
            Image(systemName: "checkmark")
                .font(.system(size: size * 0.43, weight: .heavy))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.22), radius: 1, y: 0.5)
        }
        .frame(width: size * 1.20, height: size * 1.20)
        .onAppear {
            if !reduceMotion { spinning = true }
        }
        .onDisappear {
            spinning = false
        }
        .onChange(of: reduceMotion) { _, reduce in
            spinning = !reduce
        }
    }
}

// MARK: - Système Visuel Unifié « Aura Nocturne Velvet » (Variante 4C — Réglages & Menu Widgets)

struct VelvetAuraTheme: Equatable {
    let theme: AppTheme
    var liquidGlassIntensity: Double = 0.85

    var isLight: Bool { theme == .light }
    var windowCornerRadius: CGFloat { 22 }
    var cardCornerRadius: CGFloat { 15 }

    var accent: Color {
        isLight
            ? Color(red: 0.635, green: 0.110, blue: 0.686) // #a21caf
            : Color(red: 0.816, green: 0.447, blue: 0.949) // #d072f2
    }

    var accentGradient: LinearGradient {
        if isLight {
            return LinearGradient(
                colors: [
                    Color(red: 0.753, green: 0.149, blue: 0.827), // #c026d3
                    Color(red: 0.486, green: 0.227, blue: 0.929)  // #7c3aed
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [
                Color(red: 0.851, green: 0.275, blue: 0.937), // #d946ef
                Color(red: 0.545, green: 0.361, blue: 0.965)  // #8b5cf6
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var accentSoft: Color {
        isLight
            ? Color(red: 0.753, green: 0.149, blue: 0.827).opacity(0.13)
            : Color(red: 0.851, green: 0.275, blue: 0.937).opacity(0.20)
    }

    var primaryText: Color {
        switch theme {
        case .light: return Color(red: 0.102, green: 0.051, blue: 0.180) // #1a0d2e
        case .dark: return Color(red: 0.980, green: 0.961, blue: 1.000)  // #faf5ff
        case .liquidGlass: return .white
        }
    }

    var secondaryText: Color {
        switch theme {
        case .light: return Color(red: 0.231, green: 0.118, blue: 0.376).opacity(0.66)
        case .dark: return Color(red: 0.816, green: 0.776, blue: 0.902).opacity(0.58)
        case .liquidGlass: return Color(red: 0.847, green: 0.816, blue: 0.925).opacity(0.62)
        }
    }

    var sidebarBackground: Color {
        switch theme {
        case .light: return Color(red: 0.925, green: 0.902, blue: 0.973).opacity(0.92) // #ece6f8
        case .dark: return Color(red: 0.043, green: 0.039, blue: 0.067)                // #0b0a11
        case .liquidGlass: return Color(red: 0.035, green: 0.031, blue: 0.059).opacity(0.66)
        }
    }

    var contentTint: Color {
        switch theme {
        case .light: return Color.white.opacity(0.18)
        case .dark: return Color.clear
        case .liquidGlass: return Color.white.opacity(0.015)
        }
    }

    var divider: Color {
        switch theme {
        case .light: return Color(red: 0.345, green: 0.110, blue: 0.529).opacity(0.10)
        case .dark: return Color.white.opacity(0.07)
        case .liquidGlass: return Color.white.opacity(0.085)
        }
    }

    var pillFill: Color {
        switch theme {
        case .light: return Color(red: 0.494, green: 0.133, blue: 0.808).opacity(0.065)
        case .dark: return Color.white.opacity(0.065)
        case .liquidGlass: return Color.white.opacity(0.075)
        }
    }

    var pillBorder: Color {
        switch theme {
        case .light: return Color(red: 0.494, green: 0.133, blue: 0.808).opacity(0.14)
        case .dark: return Color.white.opacity(0.10)
        case .liquidGlass: return Color.white.opacity(0.12)
        }
    }

    var searchFill: Color {
        switch theme {
        case .light: return Color.white.opacity(0.94)
        case .dark: return Color(red: 0.086, green: 0.078, blue: 0.129) // #161421
        case .liquidGlass: return Color.white.opacity(0.06)
        }
    }

    var footerBackground: Color {
        switch theme {
        case .light: return Color(red: 0.933, green: 0.910, blue: 0.980).opacity(0.96) // #eee8fa
        case .dark: return Color(red: 0.035, green: 0.031, blue: 0.059)                // #09080f
        case .liquidGlass: return Color(red: 0.031, green: 0.027, blue: 0.055).opacity(0.74)
        }
    }

    var previewBannerBackground: Color {
        switch theme {
        case .light: return Color(red: 0.955, green: 0.938, blue: 0.988).opacity(0.90)
        case .dark: return Color(red: 0.055, green: 0.047, blue: 0.086)
        case .liquidGlass: return Color(red: 0.047, green: 0.039, blue: 0.078).opacity(0.56)
        }
    }

    var navActiveText: Color {
        isLight ? Color(red: 0.345, green: 0.110, blue: 0.529) : .white // #581c87 in Light
    }

    var navActiveFill: LinearGradient {
        switch theme {
        case .light:
            return LinearGradient(
                colors: [
                    Color(red: 0.659, green: 0.333, blue: 0.969).opacity(0.18),
                    Color(red: 0.545, green: 0.361, blue: 0.965).opacity(0.06)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .dark:
            return LinearGradient(
                colors: [
                    Color(red: 0.851, green: 0.275, blue: 0.937).opacity(0.26),
                    Color(red: 0.545, green: 0.361, blue: 0.965).opacity(0.10)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .liquidGlass:
            return LinearGradient(
                colors: [
                    Color(red: 0.776, green: 0.376, blue: 0.933).opacity(0.34),
                    Color(red: 0.486, green: 0.361, blue: 1.000).opacity(0.12)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    var navActiveBorder: Color {
        switch theme {
        case .light: return Color(red: 0.659, green: 0.333, blue: 0.969).opacity(0.26)
        case .dark: return Color(red: 0.851, green: 0.275, blue: 0.937).opacity(0.28)
        case .liquidGlass: return Color(red: 0.847, green: 0.706, blue: 0.996).opacity(0.26)
        }
    }

    var outerBorder: Color {
        switch theme {
        case .light: return Color(red: 0.659, green: 0.333, blue: 0.969).opacity(0.22)
        case .dark: return Color(red: 0.847, green: 0.706, blue: 0.996).opacity(0.18)
        case .liquidGlass: return Color(red: 0.847, green: 0.706, blue: 0.996).opacity(0.24)
        }
    }

    var topRimGradient: LinearGradient {
        switch theme {
        case .light:
            return LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.08),
                    .init(color: Color(red: 0.753, green: 0.149, blue: 0.827).opacity(0.58), location: 0.50),
                    .init(color: .clear, location: 0.92)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .dark:
            return LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.08),
                    .init(color: Color(red: 0.851, green: 0.275, blue: 0.937).opacity(0.72), location: 0.50),
                    .init(color: .clear, location: 0.92)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .liquidGlass:
            return LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.06),
                    .init(color: Color(red: 0.847, green: 0.706, blue: 0.996).opacity(0.75), location: 0.34),
                    .init(color: Color(red: 0.910, green: 0.475, blue: 0.976).opacity(0.95), location: 0.54),
                    .init(color: Color(red: 0.506, green: 0.549, blue: 0.973).opacity(0.65), location: 0.76),
                    .init(color: .clear, location: 0.94)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    var headerAuraColor: Color {
        switch theme {
        case .light: return Color(red: 0.851, green: 0.275, blue: 0.937).opacity(0.14)
        case .dark: return Color(red: 0.851, green: 0.275, blue: 0.937).opacity(0.20)
        case .liquidGlass: return Color(red: 0.851, green: 0.275, blue: 0.937).opacity(0.28)
        }
    }

    var cardStrokeColor: Color {
        switch theme {
        case .light: return Color(red: 0.494, green: 0.133, blue: 0.808).opacity(0.11)
        case .dark: return Color.white.opacity(0.075)
        case .liquidGlass: return Color.white.opacity(0.095)
        }
    }

    var cardShadowColor: Color {
        switch theme {
        case .light: return Color(red: 0.345, green: 0.110, blue: 0.529).opacity(0.06)
        case .dark: return Color.black.opacity(0.26)
        case .liquidGlass: return Color.black.opacity(0.24)
        }
    }
}

/// Fond de fenêtre unifié Aura Nocturne Velvet (Réglages & Menu Widgets)
struct VelvetAuraWindowBackground: View {
    let theme: AppTheme
    var liquidGlassIntensity: Double = 0.85

    var body: some View {
        let aura = VelvetAuraTheme(theme: theme, liquidGlassIntensity: liquidGlassIntensity)
        let i = max(0.05, min(1.0, liquidGlassIntensity))

        ZStack(alignment: .top) {
            switch theme {
            case .dark:
                VisualEffectBackground(material: .fullScreenUI)
                LinearGradient(
                    colors: [
                        Color(red: 0.067, green: 0.059, blue: 0.102), // #110f1a
                        Color(red: 0.039, green: 0.035, blue: 0.063)  // #0a0910
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .light:
                VisualEffectBackground(material: .underWindowBackground)
                LinearGradient(
                    colors: [
                        Color(red: 0.992, green: 0.988, blue: 1.000).opacity(0.95), // #fdfcff
                        Color(red: 0.953, green: 0.937, blue: 0.988).opacity(0.96)  // #f3effc
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .liquidGlass:
                VisualEffectBackground(material: .fullScreenUI)
                    .opacity(0.32 + 0.68 * i)
                LinearGradient(
                    colors: [
                        Color(red: 0.078, green: 0.063, blue: 0.125).opacity(0.82), // rgba(20,16,32,0.82)
                        Color(red: 0.043, green: 0.039, blue: 0.071).opacity(0.90)  // rgba(11,10,18,0.90)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            // Lueur ambiante diffuse au sommet du panneau (signature 4C)
            RadialGradient(
                colors: [aura.headerAuraColor, Color.clear],
                center: UnitPoint(x: 0.56, y: -0.10),
                startRadius: 10,
                endRadius: 290
            )
            .frame(height: 190)
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

/// Bordure extérieure + filet lumineux 1.5 pt au sommet (signature 4C)
struct VelvetAuraWindowOverlay: View {
    let theme: AppTheme
    var cornerRadius: CGFloat = 22

    var body: some View {
        let aura = VelvetAuraTheme(theme: theme)
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        ZStack(alignment: .top) {
            shape
                .strokeBorder(aura.outerBorder, lineWidth: 1.0)

            // Reflet supérieur doux interne
            shape
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(theme == .light ? 0.85 : (theme == .liquidGlass ? 0.18 : 0.08)),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .center
                    ),
                    lineWidth: 0.8
                )

            // Filet lumineux signature 4C au sommet de la fenêtre
            Rectangle()
                .fill(aura.topRimGradient)
                .frame(height: 1.5)
                .padding(.horizontal, cornerRadius * 0.45)
        }
        .clipShape(shape)
        .allowsHitTesting(false)
    }
}

/// Surface de carte veloutée unifiée (Réglages & Cartes Widgets)
struct VelvetAuraCardBackground: View {
    let theme: AppTheme
    var cornerRadius: CGFloat = 15
    var isSelected: Bool = false
    var isHovered: Bool = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let aura = VelvetAuraTheme(theme: theme)

        Group {
            switch theme {
            case .dark:
                shape.fill(
                    isSelected
                        ? Color(red: 0.125, green: 0.102, blue: 0.192)
                        : (isHovered ? Color(red: 0.105, green: 0.094, blue: 0.155) : Color(red: 0.086, green: 0.078, blue: 0.129))
                )
            case .light:
                shape.fill(
                    isSelected
                        ? Color.white
                        : (isHovered ? Color.white.opacity(0.98) : Color.white.opacity(0.92))
                )
            case .liquidGlass:
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isSelected ? 0.13 : (isHovered ? 0.095 : 0.068)),
                            Color.white.opacity(isSelected ? 0.06 : (isHovered ? 0.04 : 0.024))
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .shadow(
            color: isSelected ? aura.accent.opacity(theme == .light ? 0.14 : 0.24) : aura.cardShadowColor,
            radius: isSelected ? 12 : (theme == .light ? 6 : 8),
            y: isSelected ? 4 : 3
        )
    }
}

/// Contour de carte fondu unifié avec léger reflet supérieur
struct VelvetAuraCardOverlay: View {
    let theme: AppTheme
    var cornerRadius: CGFloat = 15
    var isSelected: Bool = false

    var body: some View {
        let aura = VelvetAuraTheme(theme: theme)
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        ZStack {
            shape.strokeBorder(
                isSelected ? aura.accent.opacity(theme == .light ? 0.85 : 0.90) : aura.cardStrokeColor,
                lineWidth: isSelected ? 1.5 : 1.0
            )
            if !isSelected && theme != .light {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(theme == .liquidGlass ? 0.13 : 0.07),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .center
                    ),
                    lineWidth: 0.8
                )
            }
        }
        .allowsHitTesting(false)
    }
}

/// Fond d'onglet de barre latérale unifié avec barre verticale lumineuse 3 pt à gauche (signature 4C)
struct VelvetAuraSidebarRowBackground: View {
    let theme: AppTheme
    let isSelected: Bool
    var isHovered: Bool = false

    var body: some View {
        let aura = VelvetAuraTheme(theme: theme)
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)

        ZStack(alignment: .leading) {
            if isSelected {
                shape
                    .fill(aura.navActiveFill)
                    .overlay(shape.strokeBorder(aura.navActiveBorder, lineWidth: 1.0))
                    .shadow(
                        color: theme == .liquidGlass ? aura.accent.opacity(0.20) : .clear,
                        radius: 8,
                        y: 2
                    )

                // Barre verticale lumineuse signature 4C sur le bord gauche
                Capsule(style: .continuous)
                    .fill(aura.accentGradient)
                    .frame(width: 3, height: 18)
                    .shadow(color: aura.accent.opacity(theme == .light ? 0.35 : 0.70), radius: 5, x: 0, y: 0)
                    .padding(.leading, 2)
            } else if isHovered {
                shape.fill(aura.pillFill)
            }
        }
    }
}

/// Synchronise l'apparence AppKit de la fenêtre NSWindow avec le thème LaunchPad choisi
/// afin d'éviter toute inversion de contraste sur les contrôles système (macOS Clair vs Sombre).
struct WindowAppearanceSync: NSViewRepresentable {
    let isLight: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            applyAppearance(to: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            applyAppearance(to: nsView.window)
        }
    }

    private func applyAppearance(to window: NSWindow?) {
        guard let window else { return }
        let targetName: NSAppearance.Name = isLight ? .aqua : .darkAqua
        if window.appearance?.name != targetName {
            window.appearance = NSAppearance(named: targetName)
        }
    }
}
