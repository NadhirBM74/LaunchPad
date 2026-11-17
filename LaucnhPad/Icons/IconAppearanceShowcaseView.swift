import SwiftUI
import AppKit

// MARK: - Galerie Interactive d'Apparence des Icônes (Fidèle à la Photo de Référence 1)

struct IconAppearanceShowcaseView: View {
    @AppStorage(PrefKey.iconStyle) private var iconStyleRaw: String = "original"
    @AppStorage(PrefKey.tintedIcons) private var tintedIcons: Bool = false
    @AppStorage(PrefKey.tintedIconColor) private var tintedIconColor: String = "blue"
    @ObservedObject private var licenseManager = LicenseManager.shared
    @State private var feedbackMessage: String? = nil
    var onStyleChanged: (() -> Void)? = nil
    var onRequirePro: ((String, String) -> Void)? = nil

    private var activeStyle: IconAppearanceStyle {
        if tintedIcons {
            return licenseManager.isPro ? .tinted : .original
        }
        let parsed = IconAppearanceStyle(rawValue: iconStyleRaw) ?? .original
        if parsed.requiresPro && !licenseManager.isPro {
            return .original
        }
        return parsed
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

    private let tintOptions: [(String, String, Color)] = [
        ("blue", "Bleu", Color(red: 0.08, green: 0.54, blue: 0.98)),
        ("purple", "Violet", Color(red: 0.65, green: 0.42, blue: 1.0)),
        ("orange", "Orange", Color(red: 1.0, green: 0.56, blue: 0.14)),
        ("mint", "Menthe", Color(red: 0.18, green: 0.85, blue: 0.68)),
        ("rose", "Rose", Color(red: 1.0, green: 0.32, blue: 0.56)),
        ("gold", "Or", Color(red: 0.98, green: 0.78, blue: 0.22)),
        ("graphite", "Graphite", Color(white: 0.78))
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Bandeau d'état clair indiquant le style actif et bouton de rafraîchissement HD
            HStack(spacing: 10) {
                Image(systemName: activeStyle.badgeIcon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Style actif : \(activeStyle.title)")
                            .font(.system(size: 13, weight: .bold))
                        Text("HD 512 px")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(Color.green.opacity(0.15), in: Capsule())
                    }
                    Text(activeStyle.subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    IconCache.shared.removeAll()
                    NotificationCenter.default.post(name: .launchpadIconStyleDidChange, object: nil)
                    onStyleChanged?()
                    showFeedback("Icônes HD 512×512 actualisées !")
                } label: {
                    Label("Actualiser HD", systemImage: "arrow.clockwise")
                        .font(.system(size: 11.5, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Vide le cache et régénère toutes les icônes en haute définition 512×512 Retina")
                .accessibilityLabel("Actualiser les icônes en haute définition")
            }
            .padding(10)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            if licenseManager.isPro {
                // Titulaires d'une licence Pro : réglages système Apple + icônes transparentes / Liquid Glass
                HStack(spacing: 12) {
                    // Carte Gauche : SYSTEM ICON APPEARANCE (Dark | Light | Tinted)
                    systemAppearanceCard

                    // Carte Droite : CLEAR COLORED ICONS (Glass & Colored Icons)
                    clearColoredIconsCard
                }

                // Choix directs avec aperçu visuel d'icônes : Couleur de base macOS & Transparent Cristal
                HStack(spacing: 10) {
                    baseMacOSCard
                    transparentCrystalCard
                }
            } else {
                // Utilisateurs sans licence Pro : uniquement l'apparence d'icônes des paramètres Apple (sans transparence)
                HStack {
                    Spacer(minLength: 0)
                    systemAppearanceCard
                        .frame(maxWidth: 380)
                    Spacer(minLength: 0)
                }

                baseMacOSCard
            }

            // Palette de couleur directe lorsque le mode Teinté est actif
            if activeStyle == .tinted {
                HStack(spacing: 10) {
                    Text("Couleur de teinte :")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    ForEach(tintOptions, id: \.0) { key, label, color in
                        let isChosen = (tintedIconColor == key) || (key == "blue" && tintedIconColor == "accent")
                        Button {
                            withAnimation(AppleDesignSystem.Springs.snappy) {
                                tintedIconColor = key
                                IconCache.shared.removeAll()
                                NotificationCenter.default.post(name: .launchpadIconStyleDidChange, object: nil)
                                onStyleChanged?()
                                showFeedback("Teinte « \(label) » appliquée")
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(color)
                                    .frame(width: 14, height: 14)
                                Text(label)
                                    .font(.system(size: 11, weight: isChosen ? .bold : .medium))
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(isChosen ? color.opacity(0.22) : Color.primary.opacity(0.06), in: Capsule())
                            .overlay(
                                Capsule().strokeBorder(isChosen ? color : Color.clear, lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if let feedbackMessage {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(feedbackMessage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.green)
                }
                .transition(.opacity)
            }
        }
    }

    private var baseMacOSCard: some View {
        let isSelected = (activeStyle == .original || activeStyle == .system)
        return Button {
            selectMode(.original)
        } label: {
            HStack(spacing: 10) {
                HStack(spacing: 5) {
                    CustomAppIconView(kind: .finder, style: .classicApple, size: 32)
                    CustomAppIconView(kind: .safari, style: .classicApple, size: 32)
                    CustomAppIconView(kind: .photos, style: .classicApple, size: 32)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Couleur de base macOS")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("Icônes Apple d'origine en 512×512")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.10), lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var transparentCrystalCard: some View {
        let isSelected = (activeStyle == .transparent)
        return Button {
            selectMode(.transparent)
        } label: {
            HStack(spacing: 10) {
                HStack(spacing: 5) {
                    CustomAppIconView(kind: .keynote, style: .transparent, size: 32)
                    CustomAppIconView(kind: .weather, style: .transparent, size: 32)
                    CustomAppIconView(kind: .photos, style: .transparent, size: 32)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Transparent Cristal")
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundStyle(.primary)
                        if !licenseManager.isPro {
                            ProBadge()
                        }
                    }
                    Text("Verre transparent sur toutes vos apps")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.accentColor)
                } else if !licenseManager.isPro {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.10), lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func showFeedback(_ text: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            feedbackMessage = text
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            withAnimation(.easeInOut(duration: 0.2)) {
                if feedbackMessage == text {
                    feedbackMessage = nil
                }
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
                    .drawingGroup()
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            VStack(spacing: 8) {
                VStack(spacing: 1) {
                    HStack(spacing: 5) {
                        Text("CLEAR COLORED ICONS")
                            .font(.system(size: 8.5, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(.white.opacity(0.88))
                        if !licenseManager.isPro {
                            ProBadge()
                        }
                    }
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
        if mode.requiresPro && !licenseManager.isPro {
            let title = mode.isTransparentGlassStyle
                ? loc("pro_alert.transparent_title")
                : loc("pro_alert.tinted_title")
            let msg = mode.isTransparentGlassStyle
                ? loc("pro_alert.transparent_msg")
                : loc("pro_alert.tinted_msg")
            if let onRequirePro {
                onRequirePro(title, msg)
            } else {
                showFeedback(title)
            }
            return
        }
        withAnimation(AppleDesignSystem.Springs.snappy) {
            if mode == .tinted {
                tintedIcons = true
                iconStyleRaw = IconAppearanceStyle.tinted.rawValue
            } else {
                tintedIcons = false
                iconStyleRaw = mode.rawValue
            }
            IconCache.shared.removeAll()
            NotificationCenter.default.post(name: .launchpadIconStyleDidChange, object: nil)
            onStyleChanged?()
            showFeedback("Style « \(mode.title) » appliqué en 512×512 HD")
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
