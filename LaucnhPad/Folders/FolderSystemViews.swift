import SwiftUI
import AppKit

// MARK: - Styles de Dossiers d'Applications (Inspirés des Photos de Référence 2 & 4)

public enum FolderVisualStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    // Styles Grille Squircle (Photo de Référence 2 : Social, Extra, Work)
    case frostedGlass = "frostedGlass"   // "Social" : Verre givré brillant avec reflet diagonal + grille d'icônes
    case clearGlass = "clearGlass"       // "Extra" : Verre translucide sombre/clair + grille d'icônes
    case pureWhite = "pureWhite"         // "Work" : Squircle blanc pur lumineux + grille d'icônes

    // Styles Dossiers Design à Onglet (Photo de Référence 4 : Backup, Design, New projects, Work files, LaunchMe)
    case silkSand = "silkSand"           // "Backup" : Onglet sable + texture soie dorée 3D
    case fluidMarble = "fluidMarble"     // "Design" : Onglet rouge vif + marbre abstrait rouge/orange/blanc/noir
    case brushedSilver = "brushedSilver" // "New projects" : Onglet blanc + aluminium brossé argenté
    case matteOnyx = "matteOnyx"         // "Work files" : Onglet noir + noir mat profond et tranche blanche
    case obsidianWaves = "obsidianWaves" // "LaunchMe" : Onglet carbone + ondes 3D obsidienne noire
    case customTabbed = "customTabbed"   // Dossier à onglet avec couleur et icône personnalisées

    public var id: String { rawValue }

    public var title: String {
        loc("folder.style.\(rawValue)")
    }

    public var isTabbedFolder: Bool {
        switch self {
        case .frostedGlass, .clearGlass, .pureWhite:
            return false
        case .silkSand, .fluidMarble, .brushedSilver, .matteOnyx, .obsidianWaves, .customTabbed:
            return true
        }
    }
}

// MARK: - Forme Géométrique du Dossier à Onglet (Photo de Référence 4)

struct TabbedFolderBackShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let r = min(w, h) * 0.14
        let tabTopY = h * 0.08
        let bodyTopY = h * 0.165
        let tabRightX = w * 0.44
        let tabSlopeW = w * 0.07

        // Coin inférieur gauche -> bas -> coin inférieur droit -> haut droit
        path.move(to: CGPoint(x: 0, y: tabTopY + r))
        path.addQuadCurve(to: CGPoint(x: r, y: tabTopY), control: CGPoint(x: 0, y: tabTopY))
        path.addLine(to: CGPoint(x: tabRightX - tabSlopeW, y: tabTopY))
        path.addCurve(
            to: CGPoint(x: tabRightX + tabSlopeW, y: bodyTopY),
            control1: CGPoint(x: tabRightX - tabSlopeW * 0.2, y: tabTopY),
            control2: CGPoint(x: tabRightX + tabSlopeW * 0.2, y: bodyTopY)
        )
        path.addLine(to: CGPoint(x: w - r, y: bodyTopY))
        path.addQuadCurve(to: CGPoint(x: w, y: bodyTopY + r), control: CGPoint(x: w, y: bodyTopY))
        path.addLine(to: CGPoint(x: w, y: h - r))
        path.addQuadCurve(to: CGPoint(x: w - r, y: h), control: CGPoint(x: w, y: h))
        path.addLine(to: CGPoint(x: r, y: h))
        path.addQuadCurve(to: CGPoint(x: 0, y: h - r), control: CGPoint(x: 0, y: h))
        path.closeSubpath()
        return path
    }
}

// MARK: - Vue d'Icône de Dossier sur la Grille (Supporte tous les styles Référence 2 & 4)

struct PremiumFolderIconView: View {
    let icons: [NSImage]
    let size: CGFloat
    var style: FolderVisualStyle = .frostedGlass
    var customColorHex: String? = nil
    var customSymbol: String? = nil

    @AppStorage(PrefKey.iconStyle) private var iconStyleRaw = "original"
    @AppStorage(PrefKey.tintedIcons) private var tintedIcons = false
    @AppStorage(PrefKey.tintedIconColor) private var tintedIconColor = "accent"
    @ObservedObject private var licenseManager = LicenseManager.shared
    @Environment(\.colorScheme) private var colorScheme

    private var effectiveIconStyle: IconAppearanceStyle {
        let parsed = IconAppearanceStyle(rawValue: iconStyleRaw) ?? .original
        if tintedIcons && parsed == .original {
            return licenseManager.isPro ? .tinted : .original
        }
        if parsed.requiresPro && !licenseManager.isPro {
            return .original
        }
        if parsed == .system {
            return colorScheme == .dark ? .dark : .light
        }
        return parsed
    }

    private var activeThemeTint: Color {
        switch tintedIconColor {
        case "graphite": return Color(white: 0.76)
        case "purple": return Color(red: 0.65, green: 0.42, blue: 1.0)
        case "orange": return Color(red: 1.0, green: 0.56, blue: 0.14)
        case "mint": return Color(red: 0.18, green: 0.85, blue: 0.68)
        case "rose", "pink": return Color(red: 1.0, green: 0.32, blue: 0.56)
        case "gold", "yellow": return Color(red: 0.98, green: 0.78, blue: 0.22)
        case "red": return Color(red: 0.96, green: 0.28, blue: 0.30)
        case "green": return Color(red: 0.22, green: 0.82, blue: 0.46)
        case "teal": return Color(red: 0.18, green: 0.74, blue: 0.86)
        case "indigo": return Color(red: 0.36, green: 0.38, blue: 0.96)
        case "blue", "accent": return Color(red: 0.08, green: 0.54, blue: 0.98)
        default: return Color(red: 0.08, green: 0.54, blue: 0.98)
        }
    }

    private var glassMaterialScheme: ColorScheme {
        switch effectiveIconStyle {
        case .dark, .clearDark:
            return .dark
        default:
            return .light
        }
    }

    private var customColor: Color {
        if let hex = customColorHex, !hex.isEmpty, let ns = NSColor(hexString: hex) {
            return Color(nsColor: ns)
        }
        return effectiveIconStyle == .tinted ? activeThemeTint : Color(red: 0.12, green: 0.56, blue: 1.0)
    }

    var body: some View {
        let visibleSize = size * 0.84
        ZStack {
            if style.isTabbedFolder {
                tabbedFolderView(s: visibleSize)
            } else {
                squircleGridFolderView(s: visibleSize)
            }
        }
        .frame(width: size, height: size)
    }

    // MARK: - 1. Dossiers Grille Squircle translucides cohérents avec le thème d'icônes

    @ViewBuilder
    private func themeCoherentGlassBackground(shape: RoundedRectangle, isPureLightPreset: Bool = false) -> some View {
        let iconTheme = effectiveIconStyle
        let baseOpacity: Double = {
            switch iconTheme {
            case .transparent, .clearLiquid, .clearDark:
                return 0.56
            case .frostedGlass:
                return 0.74
            default:
                return isPureLightPreset ? 0.76 : 0.78
            }
        }()

        ZStack {
            shape
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, glassMaterialScheme)
                .opacity(baseOpacity)

            switch iconTheme {
            case .dark:
                shape.fill(
                    LinearGradient(
                        colors: [Color(white: 0.14).opacity(0.46), Color(white: 0.05).opacity(0.58)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            case .clearDark:
                shape.fill(
                    LinearGradient(
                        colors: [Color(white: 0.12).opacity(0.28), Color(white: 0.04).opacity(0.38)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            case .tinted:
                shape.fill(
                    LinearGradient(
                        colors: [activeThemeTint.opacity(0.32), activeThemeTint.opacity(0.16)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            case .monochrome:
                shape.fill(
                    LinearGradient(
                        colors: [Color(white: 0.72).opacity(0.24), Color(white: 0.36).opacity(0.20)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            case .transparent, .clearLiquid, .frostedGlass:
                shape.fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.20), Color.white.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            case .light, .original, .classicApple, .system:
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isPureLightPreset ? 0.36 : 0.24),
                            Color.white.opacity(isPureLightPreset ? 0.20 : 0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }

            // Lueur spéculaire douce en diagonale pour l'effet verre translucide
            LinearGradient(
                stops: [
                    .init(color: Color.white.opacity(iconTheme == .dark || iconTheme == .clearDark ? 0.16 : 0.28), location: 0.0),
                    .init(color: Color.clear, location: 0.45),
                    .init(color: Color.white.opacity(iconTheme == .dark || iconTheme == .clearDark ? 0.08 : 0.16), location: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(shape)

            if let hex = customColorHex, !hex.isEmpty {
                shape.fill(customColor.opacity(0.22))
            }
        }
    }

    @ViewBuilder
    private func squircleGridFolderView(s: CGFloat) -> some View {
        let cornerR = s * 0.255
        let shape = RoundedRectangle(cornerRadius: cornerR, style: .continuous)
        let gap = s * 0.052
        let mini = (s * 0.72 - gap * 2) / 3
        let iconTheme = effectiveIconStyle

        ZStack {
            switch style {
            case .frostedGlass, .clearGlass:
                themeCoherentGlassBackground(shape: shape, isPureLightPreset: false)
            case .pureWhite:
                themeCoherentGlassBackground(shape: shape, isPureLightPreset: true)
            default:
                themeCoherentGlassBackground(shape: shape, isPureLightPreset: false)
            }

            // Mini-grille d'icônes (ou icône personnalisée si définie manuellement)
            if let symbol = customSymbol, !symbol.isEmpty {
                VStack(spacing: s * 0.04) {
                    Image(systemName: symbol)
                        .font(.system(size: s * 0.34, weight: .semibold))
                        .foregroundStyle(iconTheme == .tinted ? activeThemeTint : .white.opacity(0.92))
                        .shadow(color: .black.opacity(0.22), radius: 3, y: 1.5)

                    if !icons.isEmpty {
                        HStack(spacing: s * 0.03) {
                            ForEach(0..<min(3, icons.count), id: \.self) { idx in
                                Image(nsImage: icons[idx])
                                    .resizable()
                                    .interpolation(.high)
                                    .frame(width: mini * 0.82, height: mini * 0.82)
                            }
                        }
                    }
                }
            } else {
                VStack(spacing: gap) {
                    ForEach(0..<3, id: \.self) { row in
                        HStack(spacing: gap) {
                            ForEach(0..<3, id: \.self) { column in
                                let index = row * 3 + column
                                if index < icons.count {
                                    Image(nsImage: icons[index])
                                        .resizable()
                                        .interpolation(.high)
                                        .frame(width: mini, height: mini)
                                        .shadow(color: .black.opacity(0.20), radius: 1.2, y: 0.8)
                                } else {
                                    Color.clear.frame(width: mini, height: mini)
                                }
                            }
                        }
                    }
                }
            }

            // Bordure verre subtile cohérente avec le thème actif
            shape.strokeBorder(
                LinearGradient(
                    colors: [
                        (iconTheme == .tinted ? activeThemeTint.opacity(0.72) : Color.white.opacity(iconTheme == .dark || iconTheme == .clearDark ? 0.30 : 0.56)),
                        Color.white.opacity(iconTheme == .dark || iconTheme == .clearDark ? 0.10 : 0.16),
                        (iconTheme == .tinted ? activeThemeTint.opacity(0.45) : Color.white.opacity(iconTheme == .dark || iconTheme == .clearDark ? 0.18 : 0.32))
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: max(0.85, s * 0.013)
            )
        }
        .frame(width: s, height: s)
        .shadow(color: .black.opacity(iconTheme == .transparent || iconTheme == .clearLiquid ? 0.18 : 0.24), radius: s * 0.055, x: 0, y: s * 0.03)
    }

    // MARK: - 2. Dossiers à Onglet Designer (Photo de Référence 4 : Backup, Design, New projects, Work files, LaunchMe)

    @ViewBuilder
    private func tabbedFolderView(s: CGFloat) -> some View {
        let pocketTopY = s * 0.23
        let pocketH = s - pocketTopY
        let pocketCornerR = s * 0.13

        ZStack(alignment: .bottom) {
            // 1. Arrière du dossier avec onglet supérieur gauche
            TabbedFolderBackShape()
                .fill(tabColor)
                .frame(width: s, height: s)
                .shadow(color: .black.opacity(0.32), radius: s * 0.05, y: s * 0.025)

            // 2. Tranche de feuille blanche nette dépassant juste au-dessus de la pochette avant (Photo 4)
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.96))
                .frame(width: s * 0.90, height: s * 0.06)
                .offset(y: -(pocketH - s * 0.025))
                .shadow(color: .black.opacity(0.15), radius: 1, y: -0.5)

            // 3. Pochette avant texturée selon le thème choisi
            ZStack {
                pocketFrontTexture(width: s, height: pocketH)

                // Reflet supérieur fin sur le bord de la pochette
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [Color.white.opacity(style == .matteOnyx ? 0.08 : 0.28), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: pocketH * 0.14)
                    Spacer(minLength: 0)
                }

                // Symbole personnalisé optionnel
                if let symbol = customSymbol, !symbol.isEmpty {
                    Image(systemName: symbol)
                        .font(.system(size: s * 0.30, weight: .semibold))
                        .foregroundStyle(style == .brushedSilver || style == .silkSand ? Color.black.opacity(0.65) : Color.white.opacity(0.88))
                        .shadow(color: .black.opacity(0.25), radius: 3, y: 1.5)
                }
            }
            .frame(width: s, height: pocketH)
            .clipShape(RoundedRectangle(cornerRadius: pocketCornerR, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: pocketCornerR, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(style == .matteOnyx ? 0.10 : 0.25),
                                Color.black.opacity(0.35)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.8
                    )
            )
            .shadow(color: .black.opacity(0.28), radius: s * 0.03, y: -s * 0.01)
        }
        .frame(width: s, height: s)
    }

    private var tabColor: LinearGradient {
        switch style {
        case .silkSand:
            // "Backup" : Beige sable chaud
            return LinearGradient(
                colors: [Color(red: 0.91, green: 0.72, blue: 0.54), Color(red: 0.82, green: 0.62, blue: 0.44)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .fluidMarble:
            // "Design" : Rouge carmin vibrant
            return LinearGradient(
                colors: [Color(red: 1.00, green: 0.12, blue: 0.24), Color(red: 0.86, green: 0.06, blue: 0.18)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .brushedSilver:
            // "New projects" : Blanc / Argent clair
            return LinearGradient(
                colors: [Color(white: 0.96), Color(white: 0.84)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .matteOnyx, .obsidianWaves:
            // "Work files" & "LaunchMe" : Noir profond
            return LinearGradient(
                colors: [Color(white: 0.10), Color(white: 0.04)],
                startPoint: .top,
                endPoint: .bottom
            )
        default:
            return LinearGradient(
                colors: [customColor, customColor.opacity(0.75)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    @ViewBuilder
    private func pocketFrontTexture(width w: CGFloat, height h: CGFloat) -> some View {
        switch style {
        case .silkSand:
            // "Backup" (Photo 4 Col 1) : Dunes de soie beige/or 3D
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.88, green: 0.72, blue: 0.56),
                        Color(red: 0.82, green: 0.65, blue: 0.48),
                        Color(red: 0.94, green: 0.82, blue: 0.68)
                    ],
                    startPoint: .bottomLeading,
                    endPoint: .topTrailing
                )
                // Ondes soyeuses 3D
                SilkWaveOverlayShape()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.98, green: 0.90, blue: 0.78).opacity(0.85),
                                Color(red: 0.64, green: 0.46, blue: 0.30).opacity(0.55)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

        case .fluidMarble:
            // "Design" (Photo 4 Col 2) : Marbre fluide abstrait orange/rouge/noir/blanc
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.95, green: 0.35, blue: 0.05),
                        Color(red: 0.72, green: 0.08, blue: 0.06),
                        Color(red: 0.12, green: 0.04, blue: 0.04)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                // Tourbillons fluides crème et ambre
                FluidMarbleSwirlShape()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.92),
                                Color(red: 1.0, green: 0.68, blue: 0.18).opacity(0.88),
                                Color(red: 0.85, green: 0.15, blue: 0.08).opacity(0.75)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                SilkWaveOverlayShape()
                    .fill(Color.black.opacity(0.32))
                    .rotationEffect(.degrees(180))
            }

        case .brushedSilver:
            // "New projects" (Photo 4 Col 3) : Dégradé métallique argenté satiné
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0.86, green: 0.87, blue: 0.90), location: 0.0),
                    .init(color: Color(red: 0.68, green: 0.70, blue: 0.74), location: 0.45),
                    .init(color: Color(red: 0.56, green: 0.58, blue: 0.63), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

        case .matteOnyx:
            // "Work files" (Photo 4 Col 4) : Noir mat absolu
            Color(red: 0.03, green: 0.03, blue: 0.04)

        case .obsidianWaves:
            // "LaunchMe" (Photo 4 Col 5) : Ondes 3D obsidienne noire
            ZStack {
                Color(red: 0.03, green: 0.03, blue: 0.04)
                SilkWaveOverlayShape()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.20),
                                Color(white: 0.12).opacity(0.65),
                                Color.black
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

        default:
            LinearGradient(
                colors: [
                    customColor.opacity(0.92),
                    customColor.opacity(0.65)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

private struct SilkWaveOverlayShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: 0, y: h * 0.22))
        path.addCurve(
            to: CGPoint(x: w * 0.62, y: h * 0.58),
            control1: CGPoint(x: w * 0.28, y: h * 0.02),
            control2: CGPoint(x: w * 0.42, y: h * 0.75)
        )
        path.addCurve(
            to: CGPoint(x: w, y: h * 0.35),
            control1: CGPoint(x: w * 0.78, y: h * 0.44),
            control2: CGPoint(x: w * 0.88, y: h * 0.18)
        )
        path.addLine(to: CGPoint(x: w, y: h))
        path.addCurve(
            to: CGPoint(x: w * 0.35, y: h * 0.48),
            control1: CGPoint(x: w * 0.72, y: h * 0.92),
            control2: CGPoint(x: w * 0.55, y: h * 0.32)
        )
        path.addCurve(
            to: CGPoint(x: 0, y: h * 0.65),
            control1: CGPoint(x: w * 0.18, y: h * 0.62),
            control2: CGPoint(x: w * 0.08, y: h * 0.45)
        )
        path.closeSubpath()
        return path
    }
}

private struct FluidMarbleSwirlShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: w * 0.12, y: 0))
        path.addCurve(
            to: CGPoint(x: w * 0.55, y: h * 0.85),
            control1: CGPoint(x: w * 0.48, y: h * 0.15),
            control2: CGPoint(x: w * 0.15, y: h * 0.65)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.92, y: h * 0.15),
            control1: CGPoint(x: w * 0.82, y: h * 0.98),
            control2: CGPoint(x: w * 0.65, y: h * 0.25)
        )
        path.addLine(to: CGPoint(x: w * 0.68, y: 0))
        path.addCurve(
            to: CGPoint(x: w * 0.32, y: h * 0.52),
            control1: CGPoint(x: w * 0.52, y: h * 0.38),
            control2: CGPoint(x: w * 0.45, y: h * 0.68)
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - Panneau de Personnalisation & Gestion d'un Dossier (Style, Couleur, Icône, Applications)

struct FolderCustomizationBarView: View {
    let folder: FolderData
    @ObservedObject var store: LaunchpadStore
    @ObservedObject private var locManager = LocalizationManager.shared
    @Binding var isShowingCustomizer: Bool
    @Binding var isShowingAppPicker: Bool

    private var colorPresets: [(hex: String, name: String)] {
        [
            ("#E5B892", loc("folder.color.sand")),
            ("#FF2442", loc("folder.color.carmine_short")),
            ("#D8DCE2", loc("folder.color.silver")),
            ("#141416", loc("folder.color.onyx_short")),
            ("#0A84FF", loc("tint.blue")),
            ("#30D158", loc("custom_icon.color.green")),
            ("#BF5AF2", loc("folder.color.violet")),
            ("#FF9F0A", loc("folder.color.amber")),
            ("#64D2FF", loc("folder.color.cyan"))
        ]
    }

    private let symbolPresets: [String] = [
        "",
        "folder.fill",
        "paintbrush.fill",
        "briefcase.fill",
        "hammer.fill",
        "externaldrive.fill",
        "rocket.fill",
        "gamecontroller.fill",
        "music.note",
        "photo.fill",
        "terminal.fill",
        "sparkles"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 1. Styles de dossiers (Référence 2 & 4)
            VStack(alignment: .leading, spacing: 6) {
                Text(loc("folder.customize.style"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(FolderVisualStyle.allCases) { styleOption in
                            let isSelected = (folder.style == styleOption)
                            Button {
                                withAnimation(AppleDesignSystem.Springs.snappy) {
                                    store.updateFolderCustomization(
                                        folder.id,
                                        style: styleOption,
                                        colorHex: folder.colorHex,
                                        iconSymbol: folder.iconSymbol
                                    )
                                }
                            } label: {
                                VStack(spacing: 4) {
                                    PremiumFolderIconView(
                                        icons: folder.apps.prefix(9).map { IconCache.shared.icon(for: $0) },
                                        size: 46,
                                        style: styleOption,
                                        customColorHex: folder.colorHex,
                                        customSymbol: folder.iconSymbol
                                    )
                                    .padding(3)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(isSelected ? Color.white.opacity(0.18) : Color.clear)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(isSelected ? Color.white : Color.clear, lineWidth: 1.5)
                                    )

                                    Text(styleOption.title.components(separatedBy: " (").first ?? styleOption.title)
                                        .font(.system(size: 9.5, weight: isSelected ? .bold : .medium))
                                        .foregroundStyle(isSelected ? .white : .white.opacity(0.68))
                                        .lineLimit(1)
                                }
                                .frame(width: 74)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            // 2. Couleur et Symbole
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(loc("folder.customize.color"))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.70))
                    HStack(spacing: 6) {
                        ForEach(colorPresets, id: \.hex) { preset in
                            let selected = (folder.colorHex?.uppercased() == preset.hex.uppercased())
                            Button {
                                store.updateFolderCustomization(
                                    folder.id,
                                    style: folder.style,
                                    colorHex: preset.hex,
                                    iconSymbol: folder.iconSymbol
                                )
                            } label: {
                                Circle()
                                    .fill(Color(nsColor: NSColor(hexString: preset.hex) ?? .systemBlue))
                                    .frame(width: 18, height: 18)
                                    .overlay(Circle().stroke(selected ? Color.white : Color.white.opacity(0.25), lineWidth: selected ? 2 : 0.8))
                                    .scaleEffect(selected ? 1.15 : 1.0)
                            }
                            .buttonStyle(.plain)
                            .help(preset.name)
                        }
                    }
                }

                Divider().frame(height: 28).background(Color.white.opacity(0.15))

                VStack(alignment: .leading, spacing: 5) {
                    Text(loc("folder.customize.icon"))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.70))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 5) {
                            ForEach(symbolPresets, id: \.self) { sym in
                                let currentSym = folder.iconSymbol ?? ""
                                let selected = (currentSym == sym)
                                Button {
                                    store.updateFolderCustomization(
                                        folder.id,
                                        style: folder.style,
                                        colorHex: folder.colorHex,
                                        iconSymbol: sym.isEmpty ? nil : sym
                                    )
                                } label: {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(selected ? Color.white.opacity(0.26) : Color.white.opacity(0.08))
                                            .frame(width: 24, height: 24)
                                        if sym.isEmpty {
                                            Image(systemName: "square.grid.3x3.fill")
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundStyle(.white.opacity(0.85))
                                        } else {
                                            Image(systemName: sym)
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .strokeBorder(selected ? Color.white : Color.clear, lineWidth: 1.2)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.45))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                )
        )
    }
}

// MARK: - Sélecteur d'Applications pour Ajouter/Retirer des Apps d'un Dossier

struct FolderAppPickerSheet: View {
    let folder: FolderData
    @ObservedObject var store: LaunchpadStore
    @ObservedObject private var locManager = LocalizationManager.shared
    @Binding var isPresented: Bool
    @State private var filterText: String = ""
    @State private var sortedApps: [AppInfo] = []

    private var filteredApps: [AppInfo] {
        let q = filterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return sortedApps }
        return sortedApps.filter { store.displayName($0.id).lowercased().contains(q) }
    }

    private func rebuildSortedApps() {
        sortedApps = store.catalog.values
            .filter { !store.hidden.contains($0.id) }
            .sorted { store.displayName($0.id).localizedStandardCompare(store.displayName($1.id)) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(loc("folder.manage_title", folder.name), systemImage: "folder.badge.gearshape")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    withAnimation(AppleDesignSystem.Springs.snappy) {
                        isPresented = false
                    }
                } label: {
                    Text(loc("common.done"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color.white, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            // Champ de recherche rapide
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                TextField(loc("grid.search_placeholder"), text: $filterText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            ScrollView(.vertical, showsIndicators: true) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 8)], spacing: 8) {
                    ForEach(filteredApps) { app in
                        let inFolder = folder.apps.contains(app.id)
                        Button {
                            withAnimation(AppleDesignSystem.Springs.snappy) {
                                store.toggleAppInFolder(app.id, folderID: folder.id)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(nsImage: IconCache.shared.icon(for: app.id))
                                    .resizable()
                                    .frame(width: 26, height: 26)
                                Text(store.displayName(app.id))
                                    .font(.system(size: 12, weight: inFolder ? .semibold : .regular))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                Image(systemName: inFolder ? "checkmark.circle.fill" : "plus.circle")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(inFolder ? Color.green : Color.white.opacity(0.45))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(inFolder ? Color.white.opacity(0.16) : Color.white.opacity(0.05))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(inFolder ? Color.green.opacity(0.55) : Color.white.opacity(0.08), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 220)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(red: 0.08, green: 0.09, blue: 0.12).opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.20), lineWidth: 1)
                )
        )
        .onAppear { rebuildSortedApps() }
        .onChange(of: store.revision) { _, _ in rebuildSortedApps() }
    }
}
