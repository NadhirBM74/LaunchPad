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
                                shape.fill(tint.opacity(0.16 + 0.10 * i))
                            }
                        }
                        .overlay {
                            if prominence != .clear {
                                shape.fill(LiquidGlassStyle.surfaceSheen)
                            }
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

// MARK: - Rendu Unifié « Version 1 — Cristal Pur » (Icônes, Dossiers & Barre Dock)

public struct CrystalGlassSpec {
    public let tint: Color?
    public let surfaceSheenColors: [Color]
    public let specularRimColors: [Color]
    public let fallbackTintOpacity: Double
    public let fallbackMaterialOpacity: Double

    public static func resolve(
        style: IconAppearanceStyle,
        tintColor: Color? = nil,
        isFolder: Bool = false,
        customFolderColor: Color? = nil,
        isPureLightPreset: Bool = false
    ) -> CrystalGlassSpec {
        if isFolder && isPureLightPreset {
            return CrystalGlassSpec(
                tint: Color.white.opacity(0.24),
                surfaceSheenColors: [
                    Color.white.opacity(0.22),
                    Color.white.opacity(0.06),
                    Color.white.opacity(0.12)
                ],
                specularRimColors: [
                    Color.white.opacity(0.88),
                    Color.white.opacity(0.26),
                    Color.white.opacity(0.18),
                    Color.white.opacity(0.50)
                ],
                fallbackTintOpacity: 0.22,
                fallbackMaterialOpacity: 0.56
            )
        }

        switch style {
        case .transparent, .clearLiquid, .original, .system:
            return CrystalGlassSpec(
                tint: isFolder ? customFolderColor?.opacity(0.20) : nil,
                surfaceSheenColors: [
                    Color.white.opacity(0.08),
                    Color.white.opacity(0.02),
                    Color.white.opacity(0.05)
                ],
                specularRimColors: [
                    Color.white.opacity(0.78),
                    Color.white.opacity(0.18),
                    Color.white.opacity(0.14),
                    Color.white.opacity(0.42)
                ],
                fallbackTintOpacity: customFolderColor != nil && isFolder ? 0.18 : 0.06,
                fallbackMaterialOpacity: 0.34
            )

        case .clearDark:
            return CrystalGlassSpec(
                tint: Color(red: 0.04, green: 0.05, blue: 0.10).opacity(0.55),
                surfaceSheenColors: [
                    Color(red: 0.08, green: 0.09, blue: 0.15).opacity(0.46),
                    Color(red: 0.03, green: 0.04, blue: 0.08).opacity(0.58)
                ],
                specularRimColors: [
                    Color.white.opacity(0.52),
                    Color.white.opacity(0.14),
                    Color.white.opacity(0.08),
                    Color.white.opacity(0.30)
                ],
                fallbackTintOpacity: 0.45,
                fallbackMaterialOpacity: 0.46
            )

        case .frostedGlass:
            return CrystalGlassSpec(
                tint: Color.white.opacity(0.22),
                surfaceSheenColors: [
                    Color.white.opacity(0.24),
                    Color(red: 0.88, green: 0.92, blue: 1.0).opacity(0.12),
                    Color.white.opacity(0.18)
                ],
                specularRimColors: [
                    Color.white.opacity(0.86),
                    Color.white.opacity(0.26),
                    Color.white.opacity(0.16),
                    Color.white.opacity(0.50)
                ],
                fallbackTintOpacity: 0.24,
                fallbackMaterialOpacity: 0.56
            )

        case .dark:
            return CrystalGlassSpec(
                tint: Color(red: 0.05, green: 0.06, blue: 0.10).opacity(isFolder ? 0.62 : 0.68),
                surfaceSheenColors: [
                    Color(red: 0.08, green: 0.09, blue: 0.13).opacity(isFolder ? 0.56 : 0.62),
                    Color(red: 0.03, green: 0.035, blue: 0.06).opacity(isFolder ? 0.68 : 0.76)
                ],
                specularRimColors: [
                    Color.white.opacity(0.48),
                    Color.white.opacity(0.13),
                    Color.white.opacity(0.08),
                    Color.white.opacity(0.28)
                ],
                fallbackTintOpacity: 0.56,
                fallbackMaterialOpacity: 0.52
            )

        case .light:
            return CrystalGlassSpec(
                tint: Color.white.opacity(isFolder ? 0.36 : 0.42),
                surfaceSheenColors: [
                    Color.white.opacity(isFolder ? 0.46 : 0.54),
                    Color(red: 0.93, green: 0.95, blue: 1.0).opacity(isFolder ? 0.32 : 0.38),
                    Color.white.opacity(isFolder ? 0.40 : 0.48)
                ],
                specularRimColors: [
                    Color.white.opacity(0.92),
                    Color.white.opacity(0.30),
                    Color.white.opacity(0.20),
                    Color.white.opacity(0.56)
                ],
                fallbackTintOpacity: 0.40,
                fallbackMaterialOpacity: 0.58
            )

        case .tinted:
            let accent = tintColor ?? customFolderColor ?? Color(red: 0.12, green: 0.56, blue: 1.0)
            return CrystalGlassSpec(
                tint: accent.opacity(isFolder ? 0.34 : 0.38),
                surfaceSheenColors: [
                    accent.opacity(0.20),
                    Color.white.opacity(0.05),
                    accent.opacity(0.14)
                ],
                specularRimColors: [
                    accent.opacity(0.84),
                    Color.white.opacity(0.28),
                    accent.opacity(0.18),
                    accent.opacity(0.48)
                ],
                fallbackTintOpacity: 0.32,
                fallbackMaterialOpacity: 0.46
            )

        case .monochrome:
            return CrystalGlassSpec(
                tint: Color(white: 0.16).opacity(0.36),
                surfaceSheenColors: [
                    Color(white: 0.24).opacity(0.38),
                    Color(white: 0.12).opacity(0.48)
                ],
                specularRimColors: [
                    Color.white.opacity(0.74),
                    Color.white.opacity(0.20),
                    Color.white.opacity(0.12),
                    Color.white.opacity(0.40)
                ],
                fallbackTintOpacity: 0.34,
                fallbackMaterialOpacity: 0.46
            )

        case .classicApple:
            return CrystalGlassSpec(
                tint: isFolder ? customFolderColor?.opacity(0.18) : nil,
                surfaceSheenColors: [
                    Color.white.opacity(0.10),
                    Color.white.opacity(0.02),
                    Color.white.opacity(0.05)
                ],
                specularRimColors: [
                    Color.white.opacity(0.78),
                    Color.white.opacity(0.20),
                    Color.white.opacity(0.12),
                    Color.white.opacity(0.42)
                ],
                fallbackTintOpacity: 0.10,
                fallbackMaterialOpacity: 0.36
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

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(shape: S, spec: CrystalGlassSpec, interactive: Bool = false) {
        self.shape = shape
        self.spec = spec
        self.interactive = interactive
    }

    public var body: some View {
        ZStack {
            if #available(macOS 26.0, *), !reduceTransparency {
                let glass: Glass = {
                    var g: Glass = interactive ? .clear.interactive() : .clear
                    if let tint = spec.tint {
                        g = g.tint(tint)
                    }
                    return g
                }()
                Color.clear
                    .glassEffect(glass, in: shape)
            } else {
                shape
                    .fill(reduceTransparency ? Color(nsColor: .windowBackgroundColor).opacity(0.86) : Color.clear)
                if !reduceTransparency {
                    shape
                        .fill(.ultraThinMaterial)
                        .opacity(spec.fallbackMaterialOpacity)
                }
                if let tint = spec.tint {
                    shape.fill(tint.opacity(spec.fallbackTintOpacity))
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
public struct CrystalAppIconImage: View {
    public let image: NSImage
    public let size: CGFloat
    public let style: IconAppearanceStyle
    public let isPro: Bool
    public let tintColor: Color?
    public var useLiveGlass: Bool = true

    public init(
        image: NSImage,
        size: CGFloat,
        style: IconAppearanceStyle,
        isPro: Bool,
        tintColor: Color? = nil,
        useLiveGlass: Bool = true
    ) {
        self.image = image
        self.size = size
        self.style = style
        self.isPro = isPro
        self.tintColor = tintColor
        self.useLiveGlass = useLiveGlass
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
            let spec = CrystalGlassSpec.resolve(style: style, tintColor: tintColor)
            let rimWidth = max(useLiveGlass ? 0.88 : 0.48, min(1.35, bodySize * 0.0155))

            ZStack {
                if useLiveGlass {
                    CrystalGlassBackdrop(shape: shape, spec: spec)
                        .frame(width: bodySize, height: bodySize)
                } else {
                    // Version légère sans réfraction imbriquée pour les mini-icônes 3×3 des dossiers
                    ZStack {
                        if let tint = spec.tint {
                            shape.fill(tint.opacity(0.62))
                        } else {
                            shape.fill(Color.white.opacity(0.10))
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

                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .shadow(
                        color: .black.opacity(useLiveGlass ? 0.20 : 0.14),
                        radius: max(0.5, size * 0.020),
                        y: max(0.4, size * 0.010)
                    )

                CrystalGlassBackdrop.specularRim(shape: shape, spec: spec, lineWidth: rimWidth)
                    .frame(width: bodySize, height: bodySize)
            }
            .frame(width: size, height: size)
            .shadow(
                color: .black.opacity(useLiveGlass ? 0.24 : 0.15),
                radius: max(1.0, size * (useLiveGlass ? 0.055 : 0.032)),
                y: max(0.5, size * (useLiveGlass ? 0.028 : 0.016))
            )
        }
    }
}

/// Enveloppe légère qui suit automatiquement les préférences globales d'apparence (hors grille 120 Hz).
public struct LiveAppIconView: View {
    public let image: NSImage
    public let size: CGFloat
    public var useLiveGlass: Bool = true

    @AppStorage(PrefKey.iconStyle) private var iconStyleRaw = "original"
    @AppStorage(PrefKey.tintedIcons) private var tintedIcons = false
    @AppStorage(PrefKey.tintedIconColor) private var tintedIconColor = "accent"
    @AppStorage(PrefKey.isProUnlocked) private var isPro = false

    public init(image: NSImage, size: CGFloat, useLiveGlass: Bool = true) {
        self.image = image
        self.size = size
        self.useLiveGlass = useLiveGlass
    }

    private var effectiveStyle: IconAppearanceStyle {
        if tintedIcons && isPro { return .tinted }
        let parsed = IconAppearanceStyle(rawValue: iconStyleRaw) ?? .original
        if parsed.requiresPro && !isPro { return .original }
        return parsed
    }

    private var activeTint: Color? {
        guard tintedIcons && isPro else { return nil }
        return CrystalGlassSpec.activeTintColor(forKey: tintedIconColor)
    }

    public var body: some View {
        CrystalAppIconImage(
            image: image,
            size: size,
            style: effectiveStyle,
            isPro: isPro,
            tintColor: activeTint,
            useLiveGlass: useLiveGlass
        )
    }
}
