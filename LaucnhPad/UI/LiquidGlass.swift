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
    public static var specularBorder: LinearGradient { specularBorder() }

    public static func specularBorder(intensity: Double = 1.0) -> LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.68),
                Color.white.opacity(0.24),
                Color.white.opacity(0.06),
                Color.white.opacity(0.20)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Biseau spéculaire accentué pour les éléments interactifs survolés (luminosité constante)
    public static var specularBorderHovered: LinearGradient { specularBorderHovered() }

    public static func specularBorderHovered(intensity: Double = 1.0) -> LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.85),
                Color.white.opacity(0.35),
                Color.white.opacity(0.12),
                Color.white.opacity(0.32)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Reflet supérieur doux simulant la source de lumière zénithale (luminosité constante)
    public static var surfaceSheen: LinearGradient { surfaceSheen() }

    public static func surfaceSheen(intensity: Double = 1.0) -> LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.18),
                Color.white.opacity(0.04),
                Color.clear
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Ombre douce portée caractéristique des surfaces de verre flottantes d'Apple
    public static let shadowColor = Color.black.opacity(0.32)
    public static let shadowRadius: CGFloat = 16
    public static let shadowY: CGFloat = 8
}

// MARK: - Modificateur Liquid Glass Universel

public struct LiquidGlassModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    let interactive: Bool
    let tint: Color?
    let prominence: LiquidGlassProminence
    let borderLineWidth: CGFloat
    let explicitIntensity: Double?

    @AppStorage(PrefKey.liquidGlassIntensity) private var storedIntensity: Double = 0.85
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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

    private var effectiveIntensity: Double {
        max(0.0, min(1.0, explicitIntensity ?? storedIntensity))
    }

    public func body(content: Content) -> some View {
        let i = effectiveIntensity
        if #available(macOS 26.0, *) {
            let glassBase: Glass = {
                switch prominence {
                case .clear: return .clear
                case .prominent: return .regular
                case .regular: return .regular
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
                .background {
                    // La translucidité du fond varie selon le curseur sans JAMAIS altérer la luminosité du contenu
                    shape
                        .fill(Color.white.opacity(0.001))
                        .glassEffect(configuredGlass, in: shape)
                        .opacity(0.25 + 0.75 * i)
                }
                .overlay {
                    shape
                        .fill(LiquidGlassStyle.surfaceSheen)
                        .allowsHitTesting(false)
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
                .onHover { hovering in
                    guard interactive else { return }
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        isHovered = hovering
                    }
                }
        } else {
            // Fallback haute fidélité pour macOS antérieur avec support d'Accessibilité (Réduire la transparence)
            content
                .background {
                    shape
                        .fill(reduceTransparency ? Color(nsColor: .windowBackgroundColor).opacity(0.92) : Color.clear)
                }
                .background {
                    // Modulation de la transparence du matériau sans altérer la luminosité des reflets et du texte
                    shape
                        .fill(.ultraThinMaterial)
                        .opacity(0.25 + 0.75 * i)
                        .overlay {
                            if let tint {
                                shape.fill(tint.opacity(0.15))
                            }
                        }
                        .overlay {
                            shape.fill(LiquidGlassStyle.surfaceSheen)
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
                .onHover { hovering in
                    guard interactive else { return }
                    if reduceMotion {
                        isHovered = hovering
                    } else {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            isHovered = hovering
                        }
                    }
                }
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
