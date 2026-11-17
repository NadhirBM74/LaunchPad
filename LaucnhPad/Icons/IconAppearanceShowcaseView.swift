import SwiftUI
import AppKit

// MARK: - Galerie Interactive d'Apparence des Icônes (Fidèle à la Photo de Référence 1)

struct IconAppearanceShowcaseView: View {
    @AppStorage(PrefKey.iconStyle) private var iconStyleRaw: String = "dark"
    @AppStorage(PrefKey.tintedIcons) private var tintedIcons: Bool = false
    @AppStorage(PrefKey.tintedIconColor) private var tintedIconColor: String = "blue"
    var onStyleChanged: (() -> Void)? = nil

    private var activeStyle: IconAppearanceStyle {
        if tintedIcons { return .tinted }
        return IconAppearanceStyle(rawValue: iconStyleRaw) ?? .dark
    }

    private var resolvedTint: Color {
        switch tintedIconColor {
        case "graphite": return Color(white: 0.78)
        case "purple": return Color(red: 0.65, green: 0.42, blue: 1.0)
        case "orange": return Color(red: 1.0, green: 0.56, blue: 0.14)
        case "mint": return Color(red: 0.18, green: 0.85, blue: 0.68)
        case "rose": return Color(red: 1.0, green: 0.32, blue: 0.56)
        case "gold": return Color(red: 0.98, green: 0.78, blue: 0.22)
        case "blue", "accent": return Color(red: 0.08, green: 0.54, blue: 0.98)
        default: return Color(red: 0.08, green: 0.54, blue: 0.98)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Deux grandes cartes côte à côte exactement comme sur la Photo de Référence 1
            HStack(spacing: 12) {
                // Carte Gauche : SYSTEM ICON APPEARANCE (Dark | Light | Tinted)
                systemAppearanceCard

                // Carte Droite : CLEAR COLORED ICONS (Glass & Colored Icons)
                clearColoredIconsCard
            }

            // Sélecteur rapide de mode d'icônes
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach([
                        IconAppearanceStyle.dark,
                        .light,
                        .tinted,
                        .clearDark,
                        .frostedGlass,
                        .clearLiquid,
                        .classicApple,
                        .system,
                        .original
                    ]) { mode in
                        let isSelected = (activeStyle == mode)
                        Button {
                            withAnimation(AppleDesignSystem.Springs.snappy) {
                                if mode == .tinted {
                                    tintedIcons = true
                                    iconStyleRaw = IconAppearanceStyle.tinted.rawValue
                                } else {
                                    tintedIcons = false
                                    iconStyleRaw = mode.rawValue
                                }
                                onStyleChanged?()
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(isSelected ? Color.white : Color.primary.opacity(0.25))
                                    .frame(width: 6, height: 6)
                                Text(mode.title)
                                    .font(.system(size: 11.5, weight: isSelected ? .bold : .medium))
                            }
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(
                                isSelected
                                    ? LinearGradient(colors: [Color(red: 0.35, green: 0.32, blue: 0.96), Color(red: 0.56, green: 0.34, blue: 0.96)], startPoint: .leading, endPoint: .trailing)
                                    : LinearGradient(colors: [Color.primary.opacity(0.07), Color.primary.opacity(0.07)], startPoint: .leading, endPoint: .trailing),
                                in: Capsule()
                            )
                            .foregroundStyle(isSelected ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Carte Gauche : SYSTEM ICON APPEARANCE (Dark | Light | Tinted)

    private var systemAppearanceCard: some View {
        VStack(spacing: 10) {
            VStack(spacing: 2) {
                Text("SYSTEM ICON APPEARANCE")
                    .font(.system(size: 8.5, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(Color(white: 0.25))
                Text("Dark | Light | Tinted")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Color(white: 0.10))
            }
            .padding(.top, 12)

            VStack(spacing: 8) {
                // Rangée 1 : Dark
                iconShowcaseRow(
                    kinds: [.freeform, .photos, .home],
                    style: .dark,
                    isSelected: activeStyle == .dark
                ) {
                    selectMode(.dark)
                }

                // Rangée 2 : Light
                iconShowcaseRow(
                    kinds: [.freeform, .photos, .home],
                    style: .light,
                    isSelected: activeStyle == .light
                ) {
                    selectMode(.light)
                }

                // Rangée 3 : Tinted
                iconShowcaseRow(
                    kinds: [.freeform, .photos, .home],
                    style: .tinted,
                    isSelected: activeStyle == .tinted
                ) {
                    selectMode(.tinted)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(red: 0.96, green: 0.96, blue: 0.97))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.10), radius: 8, y: 3)
    }

    // MARK: - Carte Droite : CLEAR COLORED ICONS (Fond Ondes Violet/Bleu + 3 Rangées Glass)

    private var clearColoredIconsCard: some View {
        ZStack {
            // Fond artistique ondulé bleu/violet fidèle à la Photo 1 (droite)
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.44, green: 0.36, blue: 0.98),
                        Color(red: 0.24, green: 0.14, blue: 0.94),
                        Color(red: 0.30, green: 0.20, blue: 0.96)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Ondes fluides lumineuses blanches/lavande
                WaveRibbonShape()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.85),
                                Color(red: 0.72, green: 0.68, blue: 1.0).opacity(0.35),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .blur(radius: 4)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            VStack(spacing: 8) {
                VStack(spacing: 1) {
                    Text("CLEAR COLORED ICONS")
                        .font(.system(size: 8.5, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.88))
                    Text("A unified style with Glass\nand colored icons.")
                        .font(.system(size: 12.5, weight: .heavy))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineSpacing(0)
                }
                .padding(.top, 10)

                VStack(spacing: 8) {
                    // Rangée 1 : Clear Dark Glass
                    iconShowcaseRow(
                        kinds: [.keynote, .photos, .weather, .maps],
                        style: .clearDark,
                        iconSize: 44,
                        isSelected: activeStyle == .clearDark,
                        isDarkBackground: true
                    ) {
                        selectMode(.clearDark)
                    }

                    // Rangée 2 : Frosted Light Glass
                    iconShowcaseRow(
                        kinds: [.keynote, .photos, .weather, .maps],
                        style: .frostedGlass,
                        iconSize: 44,
                        isSelected: activeStyle == .frostedGlass,
                        isDarkBackground: true
                    ) {
                        selectMode(.frostedGlass)
                    }

                    // Rangée 3 : Clear Liquid Glass
                    iconShowcaseRow(
                        kinds: [.keynote, .photos, .weather, .maps],
                        style: .clearLiquid,
                        iconSize: 44,
                        isSelected: activeStyle == .clearLiquid,
                        isDarkBackground: true
                    ) {
                        selectMode(.clearLiquid)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: Color(red: 0.24, green: 0.14, blue: 0.94).opacity(0.25), radius: 10, y: 4)
    }

    private func iconShowcaseRow(
        kinds: [CustomAppIconKind],
        style: IconAppearanceStyle,
        iconSize: CGFloat = 48,
        isSelected: Bool,
        isDarkBackground: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ForEach(kinds) { kind in
                    CustomAppIconView(
                        kind: kind,
                        style: style,
                        tintColor: resolvedTint,
                        size: iconSize
                    )
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? (isDarkBackground ? Color.white.opacity(0.18) : Color.blue.opacity(0.10)) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isSelected ? (isDarkBackground ? Color.white : Color.blue) : Color.clear,
                        lineWidth: 1.5
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func selectMode(_ mode: IconAppearanceStyle) {
        withAnimation(AppleDesignSystem.Springs.snappy) {
            if mode == .tinted {
                tintedIcons = true
                iconStyleRaw = IconAppearanceStyle.tinted.rawValue
            } else {
                tintedIcons = false
                iconStyleRaw = mode.rawValue
            }
            onStyleChanged?()
        }
    }
}

private struct WaveRibbonShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        path.move(to: CGPoint(x: 0, y: h * 0.78))
        path.addCurve(
            to: CGPoint(x: w * 0.52, y: h * 0.45),
            control1: CGPoint(x: w * 0.18, y: h * 0.42),
            control2: CGPoint(x: w * 0.35, y: h * 0.62)
        )
        path.addCurve(
            to: CGPoint(x: w, y: h * 0.22),
            control1: CGPoint(x: w * 0.72, y: h * 0.25),
            control2: CGPoint(x: w * 0.85, y: h * 0.35)
        )
        path.addLine(to: CGPoint(x: w, y: h * 0.85))
        path.addCurve(
            to: CGPoint(x: w * 0.38, y: h * 0.68),
            control1: CGPoint(x: w * 0.78, y: h * 0.55),
            control2: CGPoint(x: w * 0.55, y: h * 0.88)
        )
        path.addCurve(
            to: CGPoint(x: 0, y: h),
            control1: CGPoint(x: w * 0.18, y: h * 0.48),
            control2: CGPoint(x: w * 0.08, y: h * 0.90)
        )
        path.closeSubpath()
        return path
    }
}
