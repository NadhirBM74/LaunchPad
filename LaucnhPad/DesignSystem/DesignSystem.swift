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

// MARK: - Badge Vérifié Animé (Bleu Pro / Jaune Essai)

/// Badge officiel en rosace crénelée animé : seuls les pics extérieurs tournent, la coche centrale reste fixe.
/// Bleu vif pour LaunchPad Pro, jaune doré pendant l'essai gratuit.
struct AnimatedVerifiedSealBadge: View {
    let isTrial: Bool
    var size: CGFloat = 24

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage(PrefKey.reduceMotion) private var userReduceMotion = false

    private var reduceMotion: Bool {
        systemReduceMotion || userReduceMotion
    }

    private var badgeGradient: LinearGradient {
        if isTrial {
            return LinearGradient(
                colors: [
                    Color(red: 1.00, green: 0.86, blue: 0.16),
                    Color(red: 0.96, green: 0.65, blue: 0.00)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [
                    Color(red: 0.14, green: 0.64, blue: 1.00),
                    Color(red: 0.00, green: 0.45, blue: 0.96)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var glowColor: Color {
        isTrial
            ? Color(red: 1.00, green: 0.78, blue: 0.05)
            : Color(red: 0.05, green: 0.56, blue: 1.00)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(glowColor.opacity(0.24))
                .frame(width: size * 1.15, height: size * 1.15)
                .blur(radius: max(1.8, size * 0.12))

            // Seule la rosace extérieure (les pics crénelés) tourne en continu
            TimelineView(.animation(paused: reduceMotion)) { timeline in
                let period: Double = 8.0
                let angle: Double = reduceMotion
                    ? 0.0
                    : (timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period) * 360.0

                Rectangle()
                    .fill(badgeGradient)
                    .frame(width: size * 1.12, height: size * 1.12)
                    .mask(
                        Image(systemName: "seal.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: size, height: size)
                            .rotationEffect(.degrees(angle))
                    )
            }
            .shadow(color: glowColor.opacity(0.45), radius: max(2.0, size * 0.15), y: 1.2)

            // Le "V" (coche blanche) au milieu reste strictement immobile
            Image(systemName: "checkmark")
                .font(.system(size: size * 0.43, weight: .heavy))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.22), radius: 1, y: 0.5)
        }
        .frame(width: size * 1.20, height: size * 1.20)
    }
}
