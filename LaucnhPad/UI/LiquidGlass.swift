import Combine
import SwiftUI
import AppKit

// MARK: - Apple Liquid Glass Design System
// Conformément à la documentation Apple (https://developer.apple.com/documentation/TechnologyOverviews/liquid-glass)
// Ce système unifie l'esthétique du verre dynamique d'Apple à travers toute l'application :
// - Réfraction et translucidité optique en temps réel (.glassEffect natif sur macOS 26+ et fallback .ultraThinMaterial)
// - Biseau spéculaire (rim highlight) captant la lumière environnante
// - Éclairage intérieur délicat (surface sheen)
// - Réponse tactile et dynamique aux interactions de pointage / survol

public enum LiquidGlassProminence: Sendable {
    case regular
    case clear
    case prominent
}

public enum LiquidGlassStyle {
    /// Biseau spéculaire supérieur-gauche vers inférieur-droit simulant la réfraction sur l'arête du verre (luminosité constante)
    public static let specularBorder = LinearGradient(
        colors: [
            Color.white.opacity(0.68),
            Color.white.opacity(0.24),
            Color.white.opacity(0.06),
            Color.white.opacity(0.20)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static func specularBorder(intensity: Double = 1.0) -> LinearGradient {
        specularBorder
    }

    /// Biseau spéculaire accentué pour les éléments interactifs survolés (luminosité constante)
    public static let specularBorderHovered = LinearGradient(
        colors: [
            Color.white.opacity(0.85),
            Color.white.opacity(0.35),
            Color.white.opacity(0.12),
            Color.white.opacity(0.32)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static func specularBorderHovered(intensity: Double = 1.0) -> LinearGradient {
        specularBorderHovered
    }

    /// Reflet supérieur doux simulant la source de lumière zénithale (luminosité constante)
    public static let surfaceSheen = LinearGradient(
        colors: [
            Color.white.opacity(0.18),
            Color.white.opacity(0.04),
            Color.clear
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    public static func surfaceSheen(intensity: Double = 1.0) -> LinearGradient {
        surfaceSheen
    }

    /// Ombre douce portée caractéristique des surfaces de verre flottantes d'Apple
    public static let shadowColor = Color.black.opacity(0.32)
    public static let shadowRadius: CGFloat = 16
    public static let shadowY: CGFloat = 8
}

// MARK: - Modificateur Liquid Glass Universel

private struct IsJigglingEnvironmentKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    var isJiggling: Bool {
        get { self[IsJigglingEnvironmentKey.self] }
        set { self[IsJigglingEnvironmentKey.self] = newValue }
    }
}

private struct ConditionalHoverModifier: ViewModifier {
    let enabled: Bool
    let reduceMotion: Bool
    @Binding var isHovered: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.onHover { hovering in
                if reduceMotion {
                    isHovered = hovering
                } else {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        isHovered = hovering
                    }
                }
            }
        } else {
            content
        }
    }
}

private struct LiquidGlassFallbackBackground<S: InsettableShape>: View {
    let shape: S
    let tint: Color?
    let prominence: LiquidGlassProminence
    let explicitIntensity: Double?
    let reduceTransparency: Bool
    let isJiggling: Bool

    var body: some View {
        if let explicitIntensity {
            LiquidGlassFallbackContent(
                shape: shape,
                tint: tint,
                prominence: prominence,
                intensity: explicitIntensity,
                reduceTransparency: reduceTransparency,
                isJiggling: isJiggling
            )
        } else {
            LiquidGlassFallbackStoredContent(
                shape: shape,
                tint: tint,
                prominence: prominence,
                reduceTransparency: reduceTransparency,
                isJiggling: isJiggling
            )
        }
    }
}

private struct LiquidGlassFallbackStoredContent<S: InsettableShape>: View {
    let shape: S
    let tint: Color?
    let prominence: LiquidGlassProminence
    let reduceTransparency: Bool
    let isJiggling: Bool
    @AppStorage(PrefKey.liquidGlassIntensity) private var storedIntensity: Double = 0.85

    var body: some View {
        LiquidGlassFallbackContent(
            shape: shape,
            tint: tint,
            prominence: prominence,
            intensity: storedIntensity,
            reduceTransparency: reduceTransparency,
            isJiggling: isJiggling
        )
    }
}

private struct LiquidGlassFallbackContent<S: InsettableShape>: View {
    let shape: S
    let tint: Color?
    let prominence: LiquidGlassProminence
    let intensity: Double
    let reduceTransparency: Bool
    let isJiggling: Bool

    var body: some View {
        let transparency = max(0.0, min(1.0, intensity))
        let opacityFactor = 1.0 - transparency
        ZStack {
            if reduceTransparency {
                shape.fill(Color(nsColor: .windowBackgroundColor).opacity(0.92))
            } else if !isJiggling {
                shape
                    .fill(.ultraThinMaterial)
                    .opacity(0.18 + 0.78 * opacityFactor)
            } else {
                shape
                    .fill(Color.white.opacity(prominence == .clear ? 0.06 * (0.2 + 0.8 * opacityFactor) : 0.14 * (0.25 + 0.75 * opacityFactor)))
            }
            if let tint {
                shape.fill(tint.opacity(0.08 + 0.22 * opacityFactor))
            }
            if prominence != .clear {
                shape.fill(LiquidGlassStyle.surfaceSheen)
            }
        }
    }
}

public struct LiquidGlassModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    let interactive: Bool
    let tint: Color?
    let prominence: LiquidGlassProminence
    let borderLineWidth: CGFloat
    let explicitIntensity: Double?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isJiggling) private var isJiggling
    @State private var isHovered: Bool = false

    public init(
        shape: S,
        interactive: Bool = false,
        tint: Color? = nil,
        prominence: LiquidGlassProminence = .regular,
        borderLineWidth: CGFloat = 1.0,
        intensity: Double? = nil
    ) {
        self.shape = shape
        self.interactive = interactive
        self.tint = tint
        self.prominence = prominence
        self.borderLineWidth = borderLineWidth
        self.explicitIntensity = intensity
    }

    public func body(content: Content) -> some View {
        if #available(macOS 26.0, *), !isJiggling {
            let glassBase: Glass = {
                switch prominence {
                case .clear: return .clear
                case .prominent, .regular: return .regular
                }
            }()
            let configuredGlass: Glass = {
                var g = interactive ? glassBase.interactive() : glassBase
                if let tint {
                    g = g.tint(tint)
                }
                return g
            }()

            content
                .glassEffect(configuredGlass, in: shape)
                .overlay {
                    if prominence != .clear {
                        shape
                            .fill(LiquidGlassStyle.surfaceSheen)
                            .allowsHitTesting(false)
                    }
                }
                .overlay {
                    shape
                        .strokeBorder(
                            isHovered && interactive
                                ? LiquidGlassStyle.specularBorderHovered
                                : LiquidGlassStyle.specularBorder,
                            lineWidth: borderLineWidth
                        )
                        .allowsHitTesting(false)
                }
                .modifier(ConditionalHoverModifier(enabled: interactive, reduceMotion: reduceMotion, isHovered: $isHovered))
        } else {
            // Fallback haute fidélité pour macOS antérieur ou rotation animée (jiggle)
            content
                .background {
                    LiquidGlassFallbackBackground(
                        shape: shape,
                        tint: tint,
                        prominence: prominence,
                        explicitIntensity: explicitIntensity,
                        reduceTransparency: reduceTransparency,
                        isJiggling: isJiggling
                    )
                }
                .overlay {
                    shape
                        .strokeBorder(
                            isHovered && interactive
                                ? LiquidGlassStyle.specularBorderHovered
                                : LiquidGlassStyle.specularBorder,
                            lineWidth: borderLineWidth
                        )
                        .allowsHitTesting(false)
                }
                .modifier(ConditionalHoverModifier(enabled: interactive, reduceMotion: reduceMotion, isHovered: $isHovered))
        }
    }
}

// MARK: - Conteneur d'effet Liquid Glass
// Permet de grouper plusieurs éléments de verre pour unifier leurs réfractions mutuelles

public struct LiquidGlassContainer<Content: View>: View {
    let spacing: CGFloat?
    @ViewBuilder let content: () -> Content

    public init(spacing: CGFloat? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    public var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                HStack(spacing: spacing) {
                    content()
                }
            }
        } else {
            HStack(spacing: spacing) {
                content()
            }
        }
    }
}

// MARK: - Style de bouton Liquid Glass natif / cohérent

public struct LiquidGlassButtonStyle: ButtonStyle {
    public var prominent: Bool = false

    public init(prominent: Bool = false) {
        self.prominent = prominent
    }

    public func makeBody(configuration: Configuration) -> some View {
        if #available(macOS 26.0, *) {
            configuration.label
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .glassEffect(prominent ? .regular.interactive() : .clear.interactive(), in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(
                            configuration.isPressed
                                ? Color.white.opacity(0.8)
                                : Color.white.opacity(0.35),
                            lineWidth: 1
                        )
                        .allowsHitTesting(false)
                }
                .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
                .animation(.spring(response: 0.2, dampingFraction: 0.75), value: configuration.isPressed)
        } else {
            configuration.label
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background {
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(Capsule().fill(LiquidGlassStyle.surfaceSheen))
                }
                .overlay {
                    Capsule()
                        .strokeBorder(
                            configuration.isPressed
                                ? LiquidGlassStyle.specularBorderHovered
                                : LiquidGlassStyle.specularBorder,
                            lineWidth: 1
                        )
                        .allowsHitTesting(false)
                }
                .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
                .animation(.spring(response: 0.2, dampingFraction: 0.75), value: configuration.isPressed)
        }
    }
}

// MARK: - Extensions pratiques pour SwiftUI

public extension View {
    /// Applique le matériau Apple Liquid Glass avec réfraction, biseau spéculaire et interaction fluide
    func liquidGlass<S: InsettableShape>(
        in shape: S,
        interactive: Bool = false,
        tint: Color? = nil,
        prominence: LiquidGlassProminence = .regular,
        borderLineWidth: CGFloat = 1.0,
        intensity: Double? = nil
    ) -> some View {
        modifier(LiquidGlassModifier(
            shape: shape,
            interactive: interactive,
            tint: tint,
            prominence: prominence,
            borderLineWidth: borderLineWidth,
            intensity: intensity
        ))
    }

    /// Applique le matériau Liquid Glass à une carte rectangulaire à coins arrondis
    func liquidGlassCard(
        cornerRadius: CGFloat = 20,
        interactive: Bool = false,
        tint: Color? = nil,
        prominence: LiquidGlassProminence = .regular,
        borderLineWidth: CGFloat = 1.0,
        intensity: Double? = nil
    ) -> some View {
        liquidGlass(
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
            interactive: interactive,
            tint: tint,
            prominence: prominence,
            borderLineWidth: borderLineWidth,
            intensity: intensity
        )
    }

    /// Applique le matériau Liquid Glass à une capsule (barre de recherche, boutons de commande, badges)
    func liquidGlassCapsule(
        interactive: Bool = false,
        tint: Color? = nil,
        prominence: LiquidGlassProminence = .regular,
        borderLineWidth: CGFloat = 1.0,
        intensity: Double? = nil
    ) -> some View {
        liquidGlass(
            in: Capsule(),
            interactive: interactive,
            tint: tint,
            prominence: prominence,
            borderLineWidth: borderLineWidth,
            intensity: intensity
        )
    }
}

// MARK: - Rendu Unifié « Version 1 — Cristal Pur » (Icônes, Dossiers & Barre Dock)

public struct CrystalGlassSpec {
    public let tint: Color?
    public let surfaceSheenColors: [Color]
    public let specularRimColors: [Color]
    public let fallbackTintOpacity: Double
    public let fallbackMaterialOpacity: Double
    public let glassIntensity: Double

    nonisolated public static var currentGlassIntensity: Double {
        let d = UserDefaults.standard
        guard d.object(forKey: PrefKey.liquidGlassIntensity) != nil else { return 0.85 }
        return max(0.0, min(1.0, d.double(forKey: PrefKey.liquidGlassIntensity)))
    }

    public static func resolve(
        style: IconAppearanceStyle,
        tintColor: Color? = nil,
        isFolder: Bool = false,
        customFolderColor: Color? = nil,
        isPureLightPreset: Bool = false,
        glassIntensity: Double = CrystalGlassSpec.currentGlassIntensity
    ) -> CrystalGlassSpec {
        // 100 % (1.0) = transparence maximale ; 0 % (0.0) = opacité maximale (moins transparent)
        let t = max(0.0, min(1.0, glassIntensity))
        let opacityFactor = 1.0 - t
        let scale = 0.08 + 1.38 * opacityFactor
        let rimScale = 0.42 + 0.68 * opacityFactor
        let materialScale = max(0.06, min(1.0, 0.06 + 0.94 * opacityFactor))

        @inline(__always)
        func s(_ opacity: Double) -> Double { min(1.0, max(0.0, opacity * scale)) }
        @inline(__always)
        func r(_ opacity: Double) -> Double { min(1.0, max(0.0, opacity * rimScale)) }

        if isFolder && isPureLightPreset {
            return CrystalGlassSpec(
                tint: Color.white.opacity(s(0.24)),
                surfaceSheenColors: [
                    Color.white.opacity(s(0.22)),
                    Color.white.opacity(s(0.06)),
                    Color.white.opacity(s(0.12))
                ],
                specularRimColors: [
                    Color.white.opacity(r(0.88)),
                    Color.white.opacity(r(0.26)),
                    Color.white.opacity(r(0.18)),
                    Color.white.opacity(r(0.50))
                ],
                fallbackTintOpacity: s(0.22),
                fallbackMaterialOpacity: min(1.0, 0.72 * materialScale),
                glassIntensity: t
            )
        }

        switch style {
        case .transparent, .clearLiquid, .original, .system:
            return CrystalGlassSpec(
                tint: isFolder ? customFolderColor?.opacity(s(0.20)) : nil,
                surfaceSheenColors: [
                    Color.white.opacity(s(0.11)),
                    Color.white.opacity(s(0.03)),
                    Color.white.opacity(s(0.07))
                ],
                specularRimColors: [
                    Color.white.opacity(r(0.78)),
                    Color.white.opacity(r(0.18)),
                    Color.white.opacity(r(0.14)),
                    Color.white.opacity(r(0.42))
                ],
                fallbackTintOpacity: customFolderColor != nil && isFolder ? s(0.18) : s(0.12),
                fallbackMaterialOpacity: min(1.0, 0.75 * materialScale),
                glassIntensity: t
            )

        case .clearDark:
            return CrystalGlassSpec(
                tint: Color(red: 0.04, green: 0.05, blue: 0.10).opacity(s(0.55)),
                surfaceSheenColors: [
                    Color(red: 0.08, green: 0.09, blue: 0.15).opacity(s(0.46)),
                    Color(red: 0.03, green: 0.04, blue: 0.08).opacity(s(0.58))
                ],
                specularRimColors: [
                    Color.white.opacity(r(0.52)),
                    Color.white.opacity(r(0.14)),
                    Color.white.opacity(r(0.08)),
                    Color.white.opacity(r(0.30))
                ],
                fallbackTintOpacity: s(0.52),
                fallbackMaterialOpacity: min(1.0, 0.78 * materialScale),
                glassIntensity: t
            )

        case .frostedGlass:
            return CrystalGlassSpec(
                tint: Color.white.opacity(s(0.22)),
                surfaceSheenColors: [
                    Color.white.opacity(s(0.26)),
                    Color(red: 0.88, green: 0.92, blue: 1.0).opacity(s(0.14)),
                    Color.white.opacity(s(0.20))
                ],
                specularRimColors: [
                    Color.white.opacity(r(0.86)),
                    Color.white.opacity(r(0.26)),
                    Color.white.opacity(r(0.16)),
                    Color.white.opacity(r(0.50))
                ],
                fallbackTintOpacity: s(0.28),
                fallbackMaterialOpacity: min(1.0, 0.85 * materialScale),
                glassIntensity: t
            )

        case .dark:
            return CrystalGlassSpec(
                tint: Color(red: 0.05, green: 0.06, blue: 0.10).opacity(s(isFolder ? 0.62 : 0.68)),
                surfaceSheenColors: [
                    Color(red: 0.08, green: 0.09, blue: 0.13).opacity(s(isFolder ? 0.56 : 0.62)),
                    Color(red: 0.03, green: 0.035, blue: 0.06).opacity(s(isFolder ? 0.68 : 0.76))
                ],
                specularRimColors: [
                    Color.white.opacity(r(0.48)),
                    Color.white.opacity(r(0.13)),
                    Color.white.opacity(r(0.08)),
                    Color.white.opacity(r(0.28))
                ],
                fallbackTintOpacity: s(0.62),
                fallbackMaterialOpacity: min(1.0, 0.82 * materialScale),
                glassIntensity: t
            )

        case .light:
            return CrystalGlassSpec(
                tint: Color.white.opacity(s(isFolder ? 0.36 : 0.42)),
                surfaceSheenColors: [
                    Color.white.opacity(s(isFolder ? 0.46 : 0.54)),
                    Color(red: 0.93, green: 0.95, blue: 1.0).opacity(s(isFolder ? 0.32 : 0.38)),
                    Color.white.opacity(s(isFolder ? 0.40 : 0.48))
                ],
                specularRimColors: [
                    Color.white.opacity(r(0.92)),
                    Color.white.opacity(r(0.30)),
                    Color.white.opacity(r(0.20)),
                    Color.white.opacity(r(0.56))
                ],
                fallbackTintOpacity: s(0.48),
                fallbackMaterialOpacity: min(1.0, 0.88 * materialScale),
                glassIntensity: t
            )

        case .tinted:
            let accent = tintColor ?? customFolderColor ?? Color(red: 0.12, green: 0.56, blue: 1.0)
            return CrystalGlassSpec(
                tint: accent.opacity(s(isFolder ? 0.34 : 0.38)),
                surfaceSheenColors: [
                    accent.opacity(s(0.22)),
                    Color.white.opacity(s(0.06)),
                    accent.opacity(s(0.15))
                ],
                specularRimColors: [
                    accent.opacity(r(0.84)),
                    Color.white.opacity(r(0.28)),
                    accent.opacity(r(0.18)),
                    accent.opacity(r(0.48))
                ],
                fallbackTintOpacity: s(0.42),
                fallbackMaterialOpacity: min(1.0, 0.80 * materialScale),
                glassIntensity: t
            )

        case .monochrome:
            return CrystalGlassSpec(
                tint: Color(white: 0.16).opacity(s(0.36)),
                surfaceSheenColors: [
                    Color(white: 0.24).opacity(s(0.38)),
                    Color(white: 0.12).opacity(s(0.48))
                ],
                specularRimColors: [
                    Color.white.opacity(r(0.74)),
                    Color.white.opacity(r(0.20)),
                    Color.white.opacity(r(0.12)),
                    Color.white.opacity(r(0.40))
                ],
                fallbackTintOpacity: s(0.42),
                fallbackMaterialOpacity: min(1.0, 0.80 * materialScale),
                glassIntensity: t
            )

        case .classicApple:
            return CrystalGlassSpec(
                tint: isFolder ? customFolderColor?.opacity(s(0.18)) : nil,
                surfaceSheenColors: [
                    Color.white.opacity(s(0.10)),
                    Color.white.opacity(s(0.02)),
                    Color.white.opacity(s(0.05))
                ],
                specularRimColors: [
                    Color.white.opacity(r(0.78)),
                    Color.white.opacity(r(0.20)),
                    Color.white.opacity(r(0.12)),
                    Color.white.opacity(r(0.42))
                ],
                fallbackTintOpacity: s(0.15),
                fallbackMaterialOpacity: min(1.0, 0.65 * materialScale),
                glassIntensity: t
            )
        }
    }

    public static func activeTintColor(forKey key: String) -> Color {
        switch key {
        case "graphite": return Color(white: 0.80)
        case "purple": return Color(red: 0.72, green: 0.45, blue: 0.98)
        case "orange": return Color(red: 1.0, green: 0.58, blue: 0.15)
        case "mint": return Color(red: 0.25, green: 0.82, blue: 0.65)
        case "rose": return Color(red: 1.0, green: 0.35, blue: 0.55)
        case "gold": return Color(red: 0.98, green: 0.80, blue: 0.25)
        case "blue": return Color(red: 0.20, green: 0.60, blue: 1.0)
        default: return Color.accentColor
        }
    }
}

/// Lentille optique macOS 26 (`Glass.clear`) façon Version 1 « Cristal Pur ».
public struct CrystalGlassBackdrop<S: InsettableShape>: View {
    public let shape: S
    public let spec: CrystalGlassSpec
    public var interactive: Bool = false
    /// Désactiver `.glassEffect` pendant les rotations animées (ex. mode jiggle) évite que le calque backdrop reste à 0°.
    public var preferRotatedMaterial: Bool = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(shape: S, spec: CrystalGlassSpec, interactive: Bool = false, preferRotatedMaterial: Bool = false) {
        self.shape = shape
        self.spec = spec
        self.interactive = interactive
        self.preferRotatedMaterial = preferRotatedMaterial
    }

    public var body: some View {
        let opacityFactor = 1.0 - max(0.0, min(1.0, spec.glassIntensity))

        ZStack {
            if #available(macOS 26.0, *), !reduceTransparency, !preferRotatedMaterial {
                let glass: Glass = {
                    var g: Glass = interactive ? .clear.interactive() : .clear
                    if let tint = spec.tint {
                        g = g.tint(tint)
                    }
                    return g
                }()
                if opacityFactor > 0.08 {
                    shape
                        .fill(.ultraThinMaterial)
                        .opacity(0.68 * opacityFactor)
                }
                Color.clear
                    .glassEffect(glass, in: shape)
                    .opacity(0.12 + 0.88 * opacityFactor)
                if let tint = spec.tint {
                    shape.fill(tint.opacity(0.50 * opacityFactor))
                } else if opacityFactor > 0.08 {
                    shape.fill(Color.white.opacity(0.14 * opacityFactor))
                }
            } else {
                shape
                    .fill(reduceTransparency ? Color(nsColor: .windowBackgroundColor).opacity(0.86) : Color.clear)
                if !reduceTransparency && !preferRotatedMaterial {
                    shape
                        .fill(.ultraThinMaterial)
                        .opacity(spec.fallbackMaterialOpacity)
                } else if !reduceTransparency {
                    shape
                        .fill(Color.white.opacity(0.08 * (0.1 + 0.9 * opacityFactor)))
                }
                if let tint = spec.tint {
                    shape.fill(tint.opacity(preferRotatedMaterial ? 0.55 * opacityFactor : spec.fallbackTintOpacity))
                } else if !reduceTransparency && opacityFactor > 0.05 {
                    shape.fill(Color.white.opacity(0.22 * opacityFactor))
                }
            }

            shape
                .fill(
                    LinearGradient(
                        colors: spec.surfaceSheenColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    public static func specularRim(shape: S, spec: CrystalGlassSpec, lineWidth: CGFloat) -> some View {
        shape
            .strokeBorder(
                LinearGradient(
                    colors: spec.specularRimColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: lineWidth
            )
            .allowsHitTesting(false)
    }
}

/// Rendu unifié des icônes d'applications (Version 1 Cristal Pur lorsque le thème & Pro l'activent).
public struct CrystalAppIconImage: View, Equatable {
    public let image: NSImage
    public let size: CGFloat
    public let style: IconAppearanceStyle
    public let isPro: Bool
    public let tintColor: Color?
    public var glassIntensity: Double = CrystalGlassSpec.currentGlassIntensity
    public var useLiveGlass: Bool = true
    public var isJiggling: Bool = false

    public init(
        image: NSImage,
        size: CGFloat,
        style: IconAppearanceStyle,
        isPro: Bool,
        tintColor: Color? = nil,
        glassIntensity: Double = CrystalGlassSpec.currentGlassIntensity,
        useLiveGlass: Bool = true,
        isJiggling: Bool = false
    ) {
        self.image = image
        self.size = size
        self.style = style
        self.isPro = isPro
        self.tintColor = tintColor
        self.glassIntensity = glassIntensity
        self.useLiveGlass = useLiveGlass
        self.isJiggling = isJiggling
    }

    public static func == (lhs: CrystalAppIconImage, rhs: CrystalAppIconImage) -> Bool {
        lhs.image === rhs.image
            && lhs.size == rhs.size
            && lhs.style == rhs.style
            && lhs.isPro == rhs.isPro
            && lhs.glassIntensity == rhs.glassIntensity
            && lhs.useLiveGlass == rhs.useLiveGlass
            && lhs.isJiggling == rhs.isJiggling
            && lhs.tintColor == rhs.tintColor
    }

    public var body: some View {
        let usesCrystal = style.usesCrystalGlassBackdrop(isPro: isPro)
        if !usesCrystal {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            let bodySize = size * 0.818
            let shape = RoundedRectangle(cornerRadius: bodySize * 0.225, style: .continuous)
            let spec = CrystalGlassSpec.resolve(style: style, tintColor: tintColor, glassIntensity: glassIntensity)
            let rimWidth = max(useLiveGlass ? 0.88 : 0.48, min(1.35, bodySize * 0.0155))

            let iconStack = ZStack {
                if useLiveGlass {
                    CrystalGlassBackdrop(shape: shape, spec: spec, preferRotatedMaterial: isJiggling)
                        .frame(width: bodySize, height: bodySize)
                } else {
                    // Version légère sans réfraction imbriquée pour les mini-icônes 3×3 des dossiers
                    let miniOpacityFactor = 1.0 - max(0.0, min(1.0, spec.glassIntensity))
                    ZStack {
                        if let tint = spec.tint {
                            shape.fill(tint.opacity(0.12 + 0.65 * miniOpacityFactor))
                        } else {
                            shape.fill(Color.white.opacity(0.04 + 0.24 * miniOpacityFactor))
                        }
                        shape.fill(
                            LinearGradient(
                                colors: spec.surfaceSheenColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    }
                    .frame(width: bodySize, height: bodySize)
                }

                if useLiveGlass {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: size, height: size)
                        .shadow(
                            color: .black.opacity(0.20),
                            radius: max(0.5, size * 0.020),
                            y: max(0.4, size * 0.010)
                        )
                } else {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: size, height: size)
                }

                CrystalGlassBackdrop.specularRim(shape: shape, spec: spec, lineWidth: rimWidth)
                    .frame(width: bodySize, height: bodySize)
            }
            .frame(width: size, height: size)
            .shadow(
                color: .black.opacity(useLiveGlass ? 0.24 : 0.15),
                radius: max(1.0, size * (useLiveGlass ? 0.055 : 0.032)),
                y: max(0.5, size * (useLiveGlass ? 0.028 : 0.016))
            )

            // En mode édition (jiggle), le matériau statique est déjà actif : aplatir en 1 texture Metal
            // évite 70-140 passes d'ombres offscreen par seconde à 120 Hz, à rendu visuel identique.
            if isJiggling && useLiveGlass {
                let pad = max(8, size * 0.14)
                iconStack
                    .padding(pad)
                    .drawingGroup()
                    .padding(-pad)
            } else {
                iconStack
            }
        }
    }
}

@MainActor
private final class AppIconAppearanceState: ObservableObject {
    static let shared = AppIconAppearanceState()
    @Published private(set) var style: IconAppearanceStyle = .original
    @Published private(set) var isPro: Bool = false
    @Published private(set) var tint: Color? = nil
    @Published private(set) var glassIntensity: Double = 0.85

    private var observer: NSObjectProtocol?

    private init() {
        refresh()
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
    }

    func refresh() {
        let d = UserDefaults.standard
        let pro = d.bool(forKey: PrefKey.isProUnlocked)
        let tinted = d.bool(forKey: PrefKey.tintedIcons)
        let raw = d.string(forKey: PrefKey.iconStyle) ?? "original"
        let intensity = CrystalGlassSpec.currentGlassIntensity
        let resolved: IconAppearanceStyle
        if tinted && pro {
            resolved = .tinted
        } else {
            let parsed = IconAppearanceStyle(rawValue: raw) ?? .original
            resolved = (parsed.requiresPro && !pro) ? .original : parsed
        }
        let nextTint: Color? = (tinted && pro)
            ? CrystalGlassSpec.activeTintColor(forKey: d.string(forKey: PrefKey.tintedIconColor) ?? "accent")
            : nil
        if style != resolved { style = resolved }
        if isPro != pro { isPro = pro }
        if tint != nextTint { tint = nextTint }
        if glassIntensity != intensity { glassIntensity = intensity }
    }
}

/// Enveloppe légère qui suit automatiquement les préférences globales d'apparence (hors grille 120 Hz).
public struct LiveAppIconView: View {
    public let image: NSImage
    public let size: CGFloat
    public var useLiveGlass: Bool = true

    @ObservedObject private var state = AppIconAppearanceState.shared

    public init(image: NSImage, size: CGFloat, useLiveGlass: Bool = true) {
        self.image = image
        self.size = size
        self.useLiveGlass = useLiveGlass
    }

    public var body: some View {
        CrystalAppIconImage(
            image: image,
            size: size,
            style: state.style,
            isPro: state.isPro,
            tintColor: state.tint,
            glassIntensity: state.glassIntensity,
            useLiveGlass: useLiveGlass
        )
        .equatable()
    }
}
