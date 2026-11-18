import SwiftUI
import AppKit

// MARK: - Galerie Interactive d'Apparence des Icônes (Fidèle à la Photo de Référence 1)

struct IconAppearanceShowcaseView: View {
    @AppStorage(PrefKey.iconStyle) private var iconStyleRaw: String = "original"
    @AppStorage(PrefKey.tintedIcons) private var tintedIcons: Bool = false
    @AppStorage(PrefKey.tintedIconColor) private var tintedIconColor: String = "blue"
    @ObservedObject private var licenseManager = LicenseManager.shared
    @ObservedObject private var locManager = LocalizationManager.shared
    @State private var feedbackMessage: String? = nil
    @State private var feedbackTask: Task<Void, Never>? = nil
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

    private static let tintOptions: [(key: String, labelKey: String, color: Color)] = [
        ("blue", "tint.blue", Color(red: 0.08, green: 0.54, blue: 0.98)),
        ("purple", "tint.purple", Color(red: 0.65, green: 0.42, blue: 1.0)),
        ("orange", "tint.orange", Color(red: 1.0, green: 0.56, blue: 0.14)),
        ("mint", "tint.mint", Color(red: 0.18, green: 0.85, blue: 0.68)),
        ("rose", "tint.rose", Color(red: 1.0, green: 0.32, blue: 0.56)),
        ("gold", "tint.gold", Color(red: 0.98, green: 0.78, blue: 0.22)),
        ("graphite", "tint.graphite", Color(white: 0.78))
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
                        Text(loc("icon_showcase.active_style", activeStyle.title))
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
                    IconCache.shared.removeStyleImages()
                    NotificationCenter.default.post(name: .launchpadIconStyleDidChange, object: "force")
                    onStyleChanged?()
                    showFeedback(loc("icon_showcase.refresh_done"))
                } label: {
                    Label(loc("icon_showcase.refresh_btn"), systemImage: "arrow.clockwise")
                        .font(.system(size: 11.5, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
                .help(loc("icon_showcase.refresh_help"))
                .accessibilityLabel(loc("icon_showcase.refresh_a11y"))
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
                    Text(loc("icon_showcase.tint_label"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    ForEach(Self.tintOptions, id: \.key) { option in
                        let isChosen = (tintedIconColor == option.key) || (option.key == "blue" && tintedIconColor == "accent")
                        let label = loc(option.labelKey)
                        Button {
                            guard !isChosen else { return }
                            withAnimation(AppleDesignSystem.Springs.snappy) {
                                tintedIconColor = option.key
                                IconCache.shared.invalidateStyleCache()
                                NotificationCenter.default.post(name: .launchpadIconStyleDidChange, object: nil)
                                onStyleChanged?()
                                showFeedback(loc("icon_showcase.tint_applied", label))
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(option.color)
                                    .frame(width: 14, height: 14)
                                Text(label)
                                    .font(.system(size: 11, weight: isChosen ? .bold : .medium))
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(isChosen ? option.color.opacity(0.22) : Color.primary.opacity(0.06), in: Capsule())
                            .overlay(
                                Capsule().strokeBorder(isChosen ? option.color : Color.clear, lineWidth: 1.5)
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
        .onDisappear {
            feedbackTask?.cancel()
            feedbackTask = nil
        }
    }

    private var baseMacOSCard: some View {
        let isSelected = (activeStyle == .original || activeStyle == .system)
        return Button {
            selectMode(.original)
        } label: {
            HStack(spacing: 10) {
                HStack(spacing: 5) {
                    CustomAppIconView(kind: .finder, style: .classicApple, size: 32).equatable()
                    CustomAppIconView(kind: .safari, style: .classicApple, size: 32).equatable()
                    CustomAppIconView(kind: .photos, style: .classicApple, size: 32).equatable()
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(loc("icon_showcase.apple_colors_title"))
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(.primary)
                    Text(loc("icon_showcase.apple_colors_sub"))
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
                    CustomAppIconView(kind: .keynote, style: .transparent, size: 32).equatable()
                    CustomAppIconView(kind: .weather, style: .transparent, size: 32).equatable()
                    CustomAppIconView(kind: .photos, style: .transparent, size: 32).equatable()
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(loc("icon_showcase.crystal_title"))
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundStyle(.primary)
                        if !licenseManager.isPro {
                            ProBadge()
                        }
                    }
                    Text(loc("icon_showcase.crystal_sub"))
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
        feedbackTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) {
            feedbackMessage = text
        }
        feedbackTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
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
                Text(loc("icon_showcase.sys_banner_over"))
                    .font(.system(size: 8.5, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(Color(white: 0.25))
                Text(loc("icon_showcase.sys_banner_modes"))
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Color(white: 0.10))
            }
            .padding(.top, 12)

            VStack(spacing: 8) {
                // Rangée 1 : Dark
                IconShowcaseRowButton(
                    kinds: [.freeform, .photos, .home],
                    style: .dark,
                    tintColor: resolvedTint,
                    iconSize: 48,
                    isSelected: activeStyle == .dark,
                    isDarkBackground: false
                ) {
                    selectMode(.dark)
                }
                .equatable()

                // Rangée 2 : Light
                IconShowcaseRowButton(
                    kinds: [.freeform, .photos, .home],
                    style: .light,
                    tintColor: resolvedTint,
                    iconSize: 48,
                    isSelected: activeStyle == .light,
                    isDarkBackground: false
                ) {
                    selectMode(.light)
                }
                .equatable()

                // Rangée 3 : Tinted
                IconShowcaseRowButton(
                    kinds: [.freeform, .photos, .home],
                    style: .tinted,
                    tintColor: resolvedTint,
                    iconSize: 48,
                    isSelected: activeStyle == .tinted,
                    isDarkBackground: false
                ) {
                    selectMode(.tinted)
                }
                .equatable()
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
            ClearCardArtBackdrop().equatable()

            VStack(spacing: 8) {
                VStack(spacing: 1) {
                    HStack(spacing: 5) {
                        Text(loc("icon_showcase.clear_banner_over"))
                            .font(.system(size: 8.5, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(.white.opacity(0.88))
                        if !licenseManager.isPro {
                            ProBadge()
                        }
                    }
                    Text(loc("icon_showcase.clear_banner_sub"))
                        .font(.system(size: 12.5, weight: .heavy))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineSpacing(0)
                }
                .padding(.top, 10)

                VStack(spacing: 8) {
                    // Rangée 1 : Clear Dark Glass
                    IconShowcaseRowButton(
                        kinds: [.keynote, .photos, .weather, .maps],
                        style: .clearDark,
                        tintColor: resolvedTint,
                        iconSize: 44,
                        isSelected: activeStyle == .clearDark,
                        isDarkBackground: true
                    ) {
                        selectMode(.clearDark)
                    }
                    .equatable()

                    // Rangée 2 : Frosted Light Glass
                    IconShowcaseRowButton(
                        kinds: [.keynote, .photos, .weather, .maps],
                        style: .frostedGlass,
                        tintColor: resolvedTint,
                        iconSize: 44,
                        isSelected: activeStyle == .frostedGlass,
                        isDarkBackground: true
                    ) {
                        selectMode(.frostedGlass)
                    }
                    .equatable()

                    // Rangée 3 : Clear Liquid Glass
                    IconShowcaseRowButton(
                        kinds: [.keynote, .photos, .weather, .maps],
                        style: .clearLiquid,
                        tintColor: resolvedTint,
                        iconSize: 44,
                        isSelected: activeStyle == .clearLiquid,
                        isDarkBackground: true
                    ) {
                        selectMode(.clearLiquid)
                    }
                    .equatable()
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
        guard mode != activeStyle else { return }
        withAnimation(AppleDesignSystem.Springs.snappy) {
            if mode == .tinted {
                tintedIcons = true
                iconStyleRaw = IconAppearanceStyle.tinted.rawValue
            } else {
                tintedIcons = false
                iconStyleRaw = mode.rawValue
            }
            IconCache.shared.invalidateStyleCache()
            NotificationCenter.default.post(name: .launchpadIconStyleDidChange, object: nil)
            onStyleChanged?()
            showFeedback(loc("icon_showcase.style_applied", mode.title))
        }
    }
}

private struct IconShowcaseRowButton: View, Equatable {
    let kinds: [CustomAppIconKind]
    let style: IconAppearanceStyle
    let tintColor: Color
    let iconSize: CGFloat
    let isSelected: Bool
    let isDarkBackground: Bool
    let action: () -> Void

    static func == (lhs: IconShowcaseRowButton, rhs: IconShowcaseRowButton) -> Bool {
        lhs.kinds == rhs.kinds
            && lhs.style == rhs.style
            && lhs.iconSize == rhs.iconSize
            && lhs.isSelected == rhs.isSelected
            && lhs.isDarkBackground == rhs.isDarkBackground
            && (lhs.style != .tinted || lhs.tintColor == rhs.tintColor)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ForEach(kinds) { kind in
                    CustomAppIconView(
                        kind: kind,
                        style: style,
                        tintColor: tintColor,
                        size: iconSize
                    )
                    .equatable()
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
}

private struct ClearCardArtBackdrop: View, Equatable {
    static func == (lhs: ClearCardArtBackdrop, rhs: ClearCardArtBackdrop) -> Bool { true }

    var body: some View {
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
        .drawingGroup()
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
