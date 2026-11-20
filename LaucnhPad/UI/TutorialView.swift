import SwiftUI
import AppKit

// MARK: - Modèle d'une étape du tutoriel

struct TutorialStep: Identifiable {
    let id: Int
    let badge: String
    let tabTitle: String
    let title: String
    let subtitle: String
    let icon: String
    let iconColor: Color
    let instruction: String
    let highlights: [(icon: String, title: String, detail: String)]
}

// MARK: - Vue Principale du Tutoriel Interactif (Design Aura Nocturne Velvet 4C — 4 Versions)

struct TutorialCardView: View {
    var vm: LaunchpadViewModel? = nil
    var initialStepIndex: Int = 0
    var onDismiss: (() -> Void)? = nil

    @ObservedObject private var locManager = LocalizationManager.shared
    @AppStorage(PrefKey.backgroundStyle) private var backgroundStyle: BackgroundStyle = .liquidGlass
    @AppStorage(PrefKey.liquidGlassIntensity) private var liquidGlassIntensity = 0.85
    @AppStorage(PrefKey.tutorialVisualStyle) private var tutorialStyle: TutorialVisualStyle = .studioAura
    @State private var currentStepIndex: Int

    init(vm: LaunchpadViewModel? = nil, initialStepIndex: Int = 0, onDismiss: (() -> Void)? = nil) {
        self.vm = vm
        self.initialStepIndex = initialStepIndex
        self.onDismiss = onDismiss
        self._currentStepIndex = State(initialValue: initialStepIndex)
    }

    private var steps: [TutorialStep] {
        [
            TutorialStep(
                id: 0,
                badge: loc("tuto.step1.badge"),
                tabTitle: "Ouverture & F4",
                title: loc("tuto.step1.title"),
                subtitle: "Ouvrez LaunchPad en 120 FPS par pincement 3 doigts (sans conflit macOS) ou touche F4 directe.",
                icon: "hand.draw.fill",
                iconColor: Color(red: 0.28, green: 0.72, blue: 1.0),
                instruction: loc("tuto.step1.inst"),
                highlights: [
                    ("hand.pinch.fill", "Pincement 3 doigts", "Fluide et isolé des gestes macOS"),
                    ("keyboard", "Touche F4 directe", "Ouvre LaunchPad au lieu de Spotlight"),
                    ("escape", "Touche Échap", "Ferme menus et grilles instantanément")
                ]
            ),
            TutorialStep(
                id: 1,
                badge: "CRISTAL & RECHERCHE",
                tabTitle: "Liquid Glass",
                title: "Icônes Cristal, Barre de recherche & Dock",
                subtitle: "Réglez le % de Liquid Glass des icônes, filtrez en verre cristal et épinglez vos favoris.",
                icon: "drop.halffull",
                iconColor: Color(red: 0.72, green: 0.45, blue: 1.0),
                instruction: "Tapez pour rechercher ou glissez des apps dans la barre de favoris",
                highlights: [
                    ("drop.halffull", "% Liquid Glass", "Contrôle direct dans les icônes"),
                    ("magnifyingglass", "Barre Cristal", "Assortie aux icônes & 4 variantes"),
                    ("dock.rectangle", "Dock Favoris", "Glissez pour épingler au Dock macOS")
                ]
            ),
            TutorialStep(
                id: 2,
                badge: loc("tuto.step3.badge"),
                tabTitle: "Grille 120 Hz",
                title: loc("tuto.step3.title"),
                subtitle: "Défilement horizontal 120 FPS, mode édition jiggle et organisation multi-pages intelligente.",
                icon: "square.grid.3x3.fill",
                iconColor: Color(red: 0.34, green: 0.88, blue: 0.58),
                instruction: loc("tuto.step3.inst"),
                highlights: [
                    ("hand.tap.fill", "Clic long / Option", "Active l'édition et les badges"),
                    ("arrow.left.arrow.right", "Swipes 120 Hz", "Transitions printanières fluides"),
                    ("arrow.up.arrow.down", "Tri intelligent", "Réorganisez en un clic")
                ]
            ),
            TutorialStep(
                id: 3,
                badge: loc("tuto.step4.badge"),
                tabTitle: "Dossiers & Touch ID",
                title: loc("tuto.step4.title"),
                subtitle: "9 styles de dossiers (Cristal, Soie, Marbre, Onyx), ajout rapide et verrouillage Touch ID.",
                icon: "folder.fill.badge.gearshape",
                iconColor: Color(red: 1.0, green: 0.62, blue: 0.22),
                instruction: loc("tuto.step4.inst"),
                highlights: [
                    ("paintbrush.fill", "9 styles visuels", "Cristal, Soie, Marbre, Argent, Onyx"),
                    ("touchid", "Sécurité Touch ID", "Protégez vos dossiers privés"),
                    ("plus.circle.fill", "Gestion rapide", "Ajoutez ou retirez en 1 tap")
                ]
            ),
            TutorialStep(
                id: 4,
                badge: loc("tuto.step5.badge"),
                tabTitle: "Widgets Live",
                title: loc("tuto.step5.title"),
                subtitle: "Galerie de widgets temps réel : Platine Vinyle, Météo animée, Horloges, Calendrier et Système.",
                icon: "square.stack.3d.up.fill",
                iconColor: Color(red: 0.98, green: 0.45, blue: 0.68),
                instruction: loc("tuto.step5.inst"),
                highlights: [
                    ("opticaldisc.fill", "Vinyle & Musique", "Synchronisé Apple Music & Spotify"),
                    ("cloud.sun.fill", "Météo Live", "Géolocalisation ou ville manuelle"),
                    ("calendar", "Calendrier & Horloge", "EventKit, CPU/RAM & Note rapide")
                ]
            ),
            TutorialStep(
                id: 5,
                badge: loc("tuto.step6.badge"),
                tabTitle: "Pro & Licence",
                title: loc("tuto.step6.title"),
                subtitle: loc("tuto.step6.sub"),
                icon: "crown.fill",
                iconColor: Color(red: 1.0, green: 0.78, blue: 0.18),
                instruction: loc("tuto.step6.inst"),
                highlights: [
                    ("trash.fill", "Désinstalleur Pro", "Supprime caches et fichiers résiduels"),
                    ("externaldrive.badge.checkmark", "Sauvegarde JSON", "Exportez vos réglages et dispositions"),
                    ("crown.fill", "Essai 7j & Pro", "Débloquez tout sans abonnement")
                ]
            )
        ]
    }

    private var frameDimensions: CGSize {
        switch tutorialStyle {
        case .studioAura: return CGSize(width: 820, height: 550)
        case .cinemaPanoramique: return CGSize(width: 780, height: 540)
        case .bentoShowcase: return CGSize(width: 800, height: 560)
        case .spotlightMinimal: return CGSize(width: 680, height: 510)
        }
    }

    var body: some View {
        let _ = locManager.effectiveLanguageCode
        let allSteps = steps
        let currentStep = allSteps[currentStepIndex]
        let dims = frameDimensions

        VelvetAuraModalContainer(cornerRadius: 22) { aura in
            Group {
                switch tutorialStyle {
                case .studioAura:
                    studioAuraLayout(allSteps: allSteps, currentStep: currentStep, aura: aura)
                case .cinemaPanoramique:
                    cinemaPanoramiqueLayout(allSteps: allSteps, currentStep: currentStep, aura: aura)
                case .bentoShowcase:
                    bentoShowcaseLayout(allSteps: allSteps, currentStep: currentStep, aura: aura)
                case .spotlightMinimal:
                    spotlightMinimalLayout(allSteps: allSteps, currentStep: currentStep, aura: aura)
                }
            }
            .frame(width: dims.width, height: dims.height)
        }
        .onExitCommand { dismiss() }
    }

    private func dismiss() {
        Prefs.defaults.set(true, forKey: PrefKey.hasLaunchedBefore)
        if let vm {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                vm.showTutorial = false
            }
        }
        onDismiss?()
    }

    // MARK: - V1 : Studio Interactif Aura 4C (Sidebar Étapes à gauche + Scène à droite)

    private func studioAuraLayout(allSteps: [TutorialStep], currentStep: TutorialStep, aura: VelvetAuraTheme) -> some View {
        HStack(spacing: 0) {
            // Sidebar Aura 4C
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 9) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(aura.accentGradient)
                            .frame(width: 30, height: 30)
                        Image(systemName: "sparkles")
                            .font(.system(size: 13.5, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Guide LaunchPad")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(aura.primaryText)
                        Text("Tour complet")
                            .font(.system(size: 11))
                            .foregroundStyle(aura.secondaryText)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 16)

                VStack(spacing: 4) {
                    ForEach(allSteps) { step in
                        let selected = step.id == currentStepIndex
                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                                currentStepIndex = step.id
                                vm?.tutorialStepIndex = step.id
                            }
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: step.icon)
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(selected ? step.iconColor : aura.secondaryText)
                                    .frame(width: 18)
                                Text("\(step.id + 1). \(step.tabTitle)")
                                    .font(.system(size: 12.5, weight: selected ? .semibold : .medium))
                                    .foregroundStyle(selected ? aura.navActiveText : aura.primaryText.opacity(0.84))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8.5)
                            .background(VelvetAuraSidebarRowBackground(theme: backgroundStyle, isSelected: selected))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)

                Spacer()

                // Bouton Discord discret en pied de sidebar
                Button {
                    if let url = URL(string: "https://discord.gg/VG9rgMjBMf") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image("DiscordLogo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 15, height: 12)
                        Text(loc("tuto.join_discord"))
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(aura.primaryText)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(aura.pillFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(aura.pillBorder, lineWidth: 0.8))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.bottom, 16)
            }
            .frame(width: 214)
            .background(aura.sidebarBackground)

            Rectangle().fill(aura.divider).frame(width: 1)

            // Contenu principal à droite
            VStack(spacing: 0) {
                tutorialTopHeader(currentStep: currentStep, allSteps: allSteps, aura: aura)
                    .padding(.horizontal, 22)
                    .padding(.top, 18)
                    .padding(.bottom, 12)

                Rectangle().fill(aura.divider).frame(height: 1)

                VStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(currentStep.title)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(aura.primaryText)
                        Text(currentStep.subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(aura.secondaryText)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    stepAnimatedScene(step: currentStep, height: 248, aura: aura)

                    stepHighlightStrip(step: currentStep, aura: aura)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 14)

                Spacer(minLength: 0)

                Rectangle().fill(aura.divider).frame(height: 1)

                tutorialFooter(allSteps: allSteps, currentStep: currentStep, aura: aura)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(aura.footerBackground)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(aura.contentTint)
        }
    }

    // MARK: - V2 : Cinéma Panoramique Plein Cadre

    private func cinemaPanoramiqueLayout(allSteps: [TutorialStep], currentStep: TutorialStep, aura: VelvetAuraTheme) -> some View {
        VStack(spacing: 0) {
            tutorialTopHeader(currentStep: currentStep, allSteps: allSteps, aura: aura)
                .padding(.horizontal, 22)
                .padding(.top, 16)
                .padding(.bottom, 10)

            // Ruban de navigation panoramique
            HStack(spacing: 6) {
                ForEach(allSteps) { step in
                    let active = step.id == currentStepIndex
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                            currentStepIndex = step.id
                            vm?.tutorialStepIndex = step.id
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: step.icon)
                                .font(.system(size: 10.5, weight: .bold))
                            Text(step.tabTitle)
                                .font(.system(size: 11, weight: active ? .bold : .medium))
                                .lineLimit(1)
                        }
                        .foregroundStyle(active ? .white : aura.secondaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5.5)
                        .frame(maxWidth: .infinity)
                        .background(active ? AnyShapeStyle(aura.accentGradient) : AnyShapeStyle(aura.pillFill), in: Capsule())
                        .overlay(Capsule().strokeBorder(active ? Color.white.opacity(0.25) : aura.pillBorder, lineWidth: 0.8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 12)

            Rectangle().fill(aura.divider).frame(height: 1)

            VStack(spacing: 10) {
                Text(currentStep.title)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(aura.primaryText)
                Text(currentStep.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(aura.secondaryText)
                    .multilineTextAlignment(.center)

                stepAnimatedScene(step: currentStep, height: 270, aura: aura)
                instructionPill(currentStep: currentStep, aura: aura)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 12)

            Spacer(minLength: 0)
            Rectangle().fill(aura.divider).frame(height: 1)
            tutorialFooter(allSteps: allSteps, currentStep: currentStep, aura: aura)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(aura.footerBackground)
        }
    }

    // MARK: - V3 : Bento Grid Démonstrateur

    private func bentoShowcaseLayout(allSteps: [TutorialStep], currentStep: TutorialStep, aura: VelvetAuraTheme) -> some View {
        VStack(spacing: 0) {
            tutorialTopHeader(currentStep: currentStep, allSteps: allSteps, aura: aura)
                .padding(.horizontal, 22)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Rectangle().fill(aura.divider).frame(height: 1)

            VStack(spacing: 12) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(currentStep.title)
                            .font(.system(size: 18.5, weight: .bold))
                            .foregroundStyle(aura.primaryText)
                        Text(currentStep.subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(aura.secondaryText)
                    }
                    Spacer()
                }

                stepAnimatedScene(step: currentStep, height: 244, aura: aura)

                HStack(spacing: 10) {
                    ForEach(0..<currentStep.highlights.count, id: \.self) { idx in
                        let h = currentStep.highlights[idx]
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 6) {
                                Image(systemName: h.icon)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(currentStep.iconColor)
                                Text(h.title)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(aura.primaryText)
                                    .lineLimit(1)
                            }
                            Text(h.detail)
                                .font(.system(size: 10.5))
                                .foregroundStyle(aura.secondaryText)
                                .lineLimit(2)
                        }
                        .padding(11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(VelvetAuraCardBackground(theme: backgroundStyle, cornerRadius: 13))
                        .overlay(VelvetAuraCardOverlay(theme: backgroundStyle, cornerRadius: 13))
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)

            Spacer(minLength: 0)
            Rectangle().fill(aura.divider).frame(height: 1)
            tutorialFooter(allSteps: allSteps, currentStep: currentStep, aura: aura)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(aura.footerBackground)
        }
    }

    // MARK: - V4 : Carrousel Spotlight Minimal

    private func spotlightMinimalLayout(allSteps: [TutorialStep], currentStep: TutorialStep, aura: VelvetAuraTheme) -> some View {
        VStack(spacing: 0) {
            tutorialTopHeader(currentStep: currentStep, allSteps: allSteps, aura: aura)
                .padding(.horizontal, 22)
                .padding(.top, 18)

            VStack(spacing: 4) {
                Text(currentStep.title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(aura.primaryText)
                    .multilineTextAlignment(.center)
                Text(currentStep.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(aura.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: 540)
            }
            .padding(.horizontal, 22)
            .padding(.top, 10)
            .padding(.bottom, 12)

            stepAnimatedScene(step: currentStep, height: 245, aura: aura)
                .padding(.horizontal, 22)

            instructionPill(currentStep: currentStep, aura: aura)
                .padding(.top, 10)

            Spacer(minLength: 0)
            Rectangle().fill(aura.divider).frame(height: 1)
            tutorialFooter(allSteps: allSteps, currentStep: currentStep, aura: aura)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(aura.footerBackground)
        }
    }

    // MARK: - Sous-composants factorisés

    private func tutorialTopHeader(currentStep: TutorialStep, allSteps: [TutorialStep], aura: VelvetAuraTheme) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: currentStep.icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(currentStep.iconColor)
                Text(currentStep.badge)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(currentStep.iconColor)
                    .tracking(0.9)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(currentStep.iconColor.opacity(0.16), in: Capsule())

            Text(loc("tuto.step_progress", currentStepIndex + 1, allSteps.count))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(aura.secondaryText)

            Spacer(minLength: 8)

            // Sélecteur des 4 modèles de Tutoriel
            HStack(spacing: 2) {
                ForEach(TutorialVisualStyle.allCases) { variant in
                    let active = tutorialStyle == variant
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            tutorialStyle = variant
                        }
                    } label: {
                        Text(variant.shortTitle)
                            .font(.system(size: 9.5, weight: active ? .bold : .medium))
                            .foregroundStyle(active ? aura.primaryText : aura.secondaryText)
                            .padding(.horizontal, 6.5)
                            .padding(.vertical, 3.5)
                            .background(
                                active ? AnyShapeStyle(aura.navActiveFill) : AnyShapeStyle(Color.clear),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(aura.pillFill, in: Capsule())
            .overlay(Capsule().strokeBorder(aura.pillBorder, lineWidth: 0.8))

            VelvetAuraEscapePill()
        }
    }

    private func stepAnimatedScene(step: TutorialStep, height: CGFloat, aura: VelvetAuraTheme) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(backgroundStyle == .light ? Color.black.opacity(0.84) : Color.black.opacity(0.38))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )

            Circle()
                .fill(
                    RadialGradient(
                        colors: [step.iconColor.opacity(0.24), step.iconColor.opacity(0.06), Color.clear],
                        center: .center,
                        startRadius: 10,
                        endRadius: 165
                    )
                )
                .frame(width: 330, height: 330)
                .allowsHitTesting(false)

            Group {
                switch currentStepIndex {
                case 0: AnimStep0OpenClose(accentColor: step.iconColor)
                case 1: AnimStepLiquidGlassSearch(accentColor: step.iconColor)
                case 2: AnimStep2DragAndPage(accentColor: step.iconColor)
                case 3: AnimStep3CreateFolder(accentColor: step.iconColor)
                case 4: AnimStep4WidgetsVinyl(accentColor: step.iconColor)
                case 5: AnimStep5ProTrial(accentColor: step.iconColor)
                default: EmptyView()
                }
            }
            .padding(14)
        }
        .frame(height: height)
        .environment(\.colorScheme, .dark)
    }

    private func stepHighlightStrip(step: TutorialStep, aura: VelvetAuraTheme) -> some View {
        HStack(spacing: 8) {
            ForEach(0..<step.highlights.count, id: \.self) { idx in
                let h = step.highlights[idx]
                HStack(spacing: 6) {
                    Image(systemName: h.icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(step.iconColor)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(h.title)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(aura.primaryText)
                            .lineLimit(1)
                        Text(h.detail)
                            .font(.system(size: 9.5))
                            .foregroundStyle(aura.secondaryText)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(aura.pillFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(aura.pillBorder, lineWidth: 0.8))
            }
        }
    }

    private func instructionPill(currentStep: TutorialStep, aura: VelvetAuraTheme) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(currentStep.iconColor)
            Text(currentStep.instruction)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(aura.primaryText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(currentStep.iconColor.opacity(0.14), in: Capsule())
        .overlay(Capsule().stroke(currentStep.iconColor.opacity(0.32), lineWidth: 1))
    }

    private func tutorialFooter(allSteps: [TutorialStep], currentStep: TutorialStep, aura: VelvetAuraTheme) -> some View {
        HStack {
            if currentStepIndex > 0 {
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        currentStepIndex -= 1
                        vm?.tutorialStepIndex = currentStepIndex
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .bold))
                        Text(loc("tuto.prev"))
                            .font(.system(size: 12.5, weight: .semibold))
                    }
                    .foregroundStyle(aura.primaryText)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 8)
                    .background(aura.pillFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(aura.pillBorder, lineWidth: 0.9))
                }
                .buttonStyle(.plain)
            } else {
                Spacer().frame(width: 90)
            }

            Spacer()

            HStack(spacing: 6) {
                ForEach(0..<allSteps.count, id: \.self) { idx in
                    Capsule()
                        .fill(idx == currentStepIndex ? currentStep.iconColor : aura.secondaryText.opacity(0.28))
                        .frame(width: idx == currentStepIndex ? 20 : 6, height: 6)
                        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: currentStepIndex)
                }
            }

            Spacer()

            if currentStepIndex < allSteps.count - 1 {
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        currentStepIndex += 1
                        vm?.tutorialStepIndex = currentStepIndex
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(loc("tuto.next"))
                            .font(.system(size: 13, weight: .bold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(aura.accentGradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: aura.accent.opacity(0.35), radius: 8, y: 3)
                }
                .buttonStyle(.plain)
            } else {
                let isTrial = LicenseManager.shared.isTrialActive
                let isLifetime = LicenseManager.shared.isProLifetime
                HStack(spacing: 6) {
                    if isLifetime || isTrial {
                        AnimatedVerifiedSealBadge(isTrial: isTrial && !isLifetime, size: 15)
                    } else {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(aura.accent)
                    }
                    Text("ESC pour terminer")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(aura.secondaryText)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(aura.pillFill, in: Capsule())
                .overlay(Capsule().strokeBorder(aura.pillBorder, lineWidth: 0.8))
            }
        }
    }
}

// MARK: - ANIMATION 1 : Ouvrir & Fermer LaunchPad (Trackpad + ⌃ Espace)

private struct AnimStep0OpenClose: View {
    let accentColor: Color

    @ObservedObject private var locManager = LocalizationManager.shared
    @State private var pinchProgress: CGFloat = 0.0
    @State private var isKeyPressed = false
    @State private var launchpadOpacity: Double = 0.0
    @State private var launchpadScale: CGFloat = 0.85
    @State private var statusKey = "tuto.open.status1"
    @State private var loopTask: Task<Void, Never>? = nil

    var body: some View {
        HStack(spacing: 26) {
            // CONTRÔLES TACTILES & CLAVIER (À GAUCHE)
            VStack(spacing: 12) {
                // Trackpad réaliste en verre dépoli
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.10), Color.white.opacity(0.04)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 145, height: 95)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(pinchProgress > 0.5 ? accentColor.opacity(0.8) : Color.white.opacity(0.18), lineWidth: 1.2)
                        )
                        .shadow(color: pinchProgress > 0.5 ? accentColor.opacity(0.25) : Color.black.opacity(0.3), radius: 8)

                    // Onde de choc tactile quand on pince
                    if pinchProgress > 0.7 {
                        Circle()
                            .stroke(accentColor.opacity(0.4), lineWidth: 2)
                            .frame(width: 50, height: 50)
                            .scaleEffect(pinchProgress * 1.3)
                            .opacity(Double(1.0 - pinchProgress * 0.5))
                    }

                    // 4 doigts tactiles avec trajectoire de pincement
                    let radius: CGFloat = 34 * (1.0 - pinchProgress * 0.72)
                    let angles: [Double] = [45, 135, 225, 315]

                    ForEach(0..<4, id: \.self) { i in
                        let rad = angles[i] * .pi / 180
                        Circle()
                            .fill(Color.white)
                            .frame(width: 12, height: 12)
                            .shadow(color: accentColor.opacity(0.9), radius: 6)
                            .offset(
                                x: cos(rad) * radius,
                                y: sin(rad) * radius
                            )
                    }

                    // Flèches centripètes
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(accentColor.opacity(Double(1.0 - pinchProgress)))
                }

                // Touches clavier 3D (⌃ Control + Espace)
                HStack(spacing: 6) {
                    // Touche ⌃ Control
                    HStack(spacing: 2) {
                        Text("⌃")
                            .font(.system(size: 11, weight: .bold))
                        Text(loc("tuto.open.key_ctrl"))
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isKeyPressed ? accentColor : Color.white.opacity(0.14))
                            .shadow(color: isKeyPressed ? accentColor.opacity(0.6) : .black.opacity(0.3), radius: isKeyPressed ? 6 : 2, y: isKeyPressed ? 0 : 2)
                    )
                    .scaleEffect(isKeyPressed ? 0.94 : 1.0)
                    .offset(y: isKeyPressed ? 1.5 : 0)

                    Text("+")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))

                    // Touche Espace
                    HStack(spacing: 4) {
                        Text("␣")
                            .font(.system(size: 11, weight: .bold))
                        Text(loc("tuto.open.key_space"))
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isKeyPressed ? accentColor : Color.white.opacity(0.14))
                            .shadow(color: isKeyPressed ? accentColor.opacity(0.6) : .black.opacity(0.3), radius: isKeyPressed ? 6 : 2, y: isKeyPressed ? 0 : 2)
                    )
                    .scaleEffect(isKeyPressed ? 0.94 : 1.0)
                    .offset(y: isKeyPressed ? 1.5 : 0)
                }
                .foregroundStyle(.white)

                Text(loc(statusKey))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(width: 155)
                    .multilineTextAlignment(.center)
            }

            // ÉCRAN MACBOOK RÉALISTE AVEC DESKTOP ET LAUNCHPAD (À DROITE)
            ZStack {
                // Cadre extérieur de l'écran MacBook (Aluminium Gris Sidéral)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(white: 0.10))
                    .frame(width: 330, height: 188)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.22), lineWidth: 1.2)
                    )
                    .shadow(color: .black.opacity(0.6), radius: 14, y: 6)

                // Dalle de l'écran avec fond d'écran macOS vibrant
                ZStack {
                    // 1. Fond d'écran dynamique macOS (style Sonoma / Sequoia)
                    LinearGradient(
                        colors: [
                            Color(red: 0.16, green: 0.10, blue: 0.36),
                            Color(red: 0.32, green: 0.16, blue: 0.48),
                            Color(red: 0.82, green: 0.38, blue: 0.32),
                            Color(red: 0.14, green: 0.28, blue: 0.52)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    // Vague abstraite lumineuse (RadialGradient léger au lieu de blur GPU)
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.orange.opacity(0.42), Color.orange.opacity(0.12), Color.clear],
                                center: .center,
                                startRadius: 8,
                                endRadius: 130
                            )
                        )
                        .frame(width: 260, height: 260)
                        .offset(x: 60, y: 30)

                    // 2. Barre des menus macOS supérieure (Apple, Finder, Heure)
                    VStack {
                        HStack(spacing: 6) {
                            Text("")
                                .font(.system(size: 9, weight: .bold))
                            Text("Finder")
                                .font(.system(size: 8, weight: .bold))
                            Text(loc("tuto.open.menu_file"))
                                .font(.system(size: 7.5, weight: .regular))
                            Text(loc("tuto.open.menu_edit"))
                                .font(.system(size: 7.5, weight: .regular))

                            Spacer()

                            Image(systemName: "wifi")
                                .font(.system(size: 7))
                            Image(systemName: "battery.100")
                                .font(.system(size: 7))
                            Text("9:41")
                                .font(.system(size: 8, weight: .semibold))
                        }
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.25))

                        Spacer()

                        // 3. Dock macOS en bas de l'écran (glisse vers le bas et s'estompe quand LaunchPad s'ouvre)
                        HStack(spacing: 6) {
                            miniDockIcon(icon: "finder", color: .blue)
                            miniDockIcon(icon: "safari.fill", color: .cyan)
                            miniDockIcon(icon: "envelope.fill", color: .indigo)
                            miniDockIcon(icon: "music.note", color: .pink)
                            miniDockIcon(icon: "photo.stack.fill", color: .orange)
                            miniDockIcon(icon: "square.grid.2x2.fill", color: accentColor, isLaunchpad: true)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.25), lineWidth: 0.8)
                        )
                        .padding(.bottom, 6)
                        .opacity(1.0 - launchpadOpacity)
                        .offset(y: CGFloat(launchpadOpacity * 20.0))
                    }

                    // 4. OVERLAY LAUNCHPAD (animé en synchronicité exacte via launchpadOpacity & scale)
                    ZStack {
                        // Fond flouté dépoli profond
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .overlay(Color.black.opacity(0.35))

                        VStack(spacing: 10) {
                            // Mini barre de recherche
                            HStack(spacing: 4) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.white.opacity(0.6))
                                Text(loc("tuto.open.search_hint"))
                                    .font(.system(size: 8))
                                    .foregroundStyle(.white.opacity(0.5))
                                Spacer()
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .frame(width: 140)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Capsule())
                            .padding(.top, 14)

                            // Grille des applications LaunchPad avec icônes réalistes
                            LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 14), count: 4), spacing: 8) {
                                miniLaunchIcon(name: "Safari", icon: "safari.fill", color: .cyan)
                                miniLaunchIcon(name: "Photos", icon: "photo.stack.fill", color: .pink)
                                miniLaunchIcon(name: loc("app_sample.music"), icon: "music.note", color: .red)
                                miniLaunchIcon(name: "Terminal", icon: "terminal.fill", color: .gray)
                                miniLaunchIcon(name: "Xcode", icon: "hammer.fill", color: .blue)
                                miniLaunchIcon(name: "Mail", icon: "envelope.fill", color: .indigo)
                                miniLaunchIcon(name: loc("app_sample.notes"), icon: "note.text", color: .yellow)
                                miniLaunchIcon(name: loc("app_sample.settings"), icon: "gearshape.fill", color: .gray)
                            }

                            Spacer()
                        }

                        // Badge de confirmation vert "LaunchPad Ouvert"
                        HStack(spacing: 4) {
                            Circle().fill(Color.green).frame(width: 6, height: 6)
                            Text(loc("tuto.open.badge"))
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3.5)
                        .background(Color.black.opacity(0.7))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.green.opacity(0.5), lineWidth: 1))
                        .offset(y: 62)
                    }
                    .opacity(launchpadOpacity)
                    .scaleEffect(launchpadScale)
                    .blur(radius: CGFloat((1.0 - launchpadOpacity) * 6.0))

                    // Caméra FaceTime HD (Notch) au sommet
                    VStack {
                        Capsule()
                            .fill(Color.black)
                            .frame(width: 32, height: 4)
                            .overlay(
                                Circle()
                                    .fill(Color(white: 0.2))
                                    .frame(width: 2.5, height: 2.5)
                            )
                        Spacer()
                    }
                    .padding(.top, 2)
                }
                .frame(width: 318, height: 176)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .onAppear {
            loopTask?.cancel()
            loopTask = Task { @MainActor in
                while !Task.isCancelled {
                    await runAnimationCycle()
                    try? await Task.sleep(for: .seconds(1.4))
                }
            }
        }
        .onDisappear {
            loopTask?.cancel()
            loopTask = nil
        }
    }

    private func miniDockIcon(icon: String, color: Color, isLaunchpad: Bool = false) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(color)
            .frame(width: 14, height: 14)
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: 8))
                    .foregroundStyle(.white)
            )
            .shadow(color: isLaunchpad ? color.opacity(0.8) : .clear, radius: 4)
    }

    private func miniLaunchIcon(name: String, icon: String, color: Color) -> some View {
        VStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(color)
                .frame(width: 24, height: 24)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                )
                .shadow(color: .black.opacity(0.3), radius: 3, y: 1)

            Text(name)
                .font(.system(size: 6.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
        }
    }

    @MainActor
    private func runAnimationCycle() async {
        // 0. ÉTAT INITIAL AU REPOS (Bureau macOS)
        withAnimation(.easeOut(duration: 0.3)) {
            launchpadOpacity = 0.0
            launchpadScale = 0.85
            pinchProgress = 0.0
            isKeyPressed = false
            statusKey = "tuto.open.status1"
        }

        // 1. GESTE D'OUVERTURE : Doigts pincent + touches s'enfoncent -> LaunchPad zoome et s'affiche SIMULTANÉMENT !
        try? await Task.sleep(for: .seconds(1.0))
        guard !Task.isCancelled else { return }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            pinchProgress = 1.0
            isKeyPressed = true
            launchpadOpacity = 1.0
            launchpadScale = 1.0
            statusKey = "tuto.open.status2"
        }

        // 2. Relâchement des doigts : LaunchPad reste grand ouvert et stable
        try? await Task.sleep(for: .seconds(0.7))
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.3)) {
            pinchProgress = 0.0
            isKeyPressed = false
            statusKey = "tuto.open.status3"
        }

        // 3. ANNONCE DE LA FERMETURE (l'utilisateur lit ce qui va se passer)
        try? await Task.sleep(for: .seconds(1.7))
        guard !Task.isCancelled else { return }
        statusKey = "tuto.open.status4"

        // 4. GESTE DE FERMETURE EN DIRECT : Doigts pincent + touches s'enfoncent -> LaunchPad se referme SIMULTANÉMENT !
        try? await Task.sleep(for: .seconds(0.7))
        guard !Task.isCancelled else { return }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            pinchProgress = 1.0
            isKeyPressed = true
            launchpadOpacity = 0.0
            launchpadScale = 0.85
            statusKey = "tuto.open.status5"
        }

        // 5. Relâchement des doigts sur le bureau : état final au repos
        try? await Task.sleep(for: .seconds(0.7))
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.3)) {
            pinchProgress = 0.0
            isKeyPressed = false
            statusKey = "tuto.open.status6"
        }
    }
}

// MARK: - ANIMATION 2 : Recherche et Lancement au Clavier

// MARK: - ANIMATION 2 : Liquid Glass %, Recherche Cristal & Dock Favoris

private struct AnimStepLiquidGlassSearch: View {
    let accentColor: Color
    @State private var glassLevel: Double = 0.85
    @State private var searchHighlight = false
    @State private var loopTask: Task<Void, Never>? = nil

    private var glassSpec: CrystalGlassSpec {
        CrystalGlassSpec.resolve(style: .clearLiquid, glassIntensity: glassLevel)
    }

    var body: some View {
        VStack(spacing: 14) {
            // Barre de recherche Liquid Glass identique aux icônes
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(red: 0.80, green: 0.68, blue: 1.0))
                Text(searchHighlight ? "Safari" : "Rechercher une application…")
                    .font(.system(size: 13, weight: searchHighlight ? .bold : .regular))
                    .foregroundStyle(searchHighlight ? .white : .white.opacity(0.58))
                Spacer()
                Text("⌘F")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.12), in: Capsule())
            }
            .padding(.horizontal, 14)
            .frame(width: 280, height: 34)
            .background(CrystalGlassBackdrop(shape: Capsule(), spec: glassSpec, preferRotatedMaterial: true))
            .overlay(CrystalGlassBackdrop.specularRim(shape: Capsule(), spec: glassSpec, lineWidth: 1.1))

            // Vraies icônes vectorielles CustomAppIconView réagissant au pourcentage Liquid Glass
            HStack(spacing: 18) {
                VStack(spacing: 4) {
                    CustomAppIconView(kind: .safari, style: .clearLiquid, size: 54, isPro: true, glassIntensity: glassLevel)
                    Text("Safari")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .scaleEffect(searchHighlight ? 1.12 : 1.0)

                VStack(spacing: 4) {
                    CustomAppIconView(kind: .photos, style: .clearLiquid, size: 54, isPro: true, glassIntensity: glassLevel)
                    Text("Photos")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.8))
                }

                VStack(spacing: 4) {
                    CustomAppIconView(kind: .weather, style: .clearLiquid, size: 54, isPro: true, glassIntensity: glassLevel)
                    Text("Météo")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.8))
                }

                VStack(spacing: 4) {
                    CustomAppIconView(kind: .keynote, style: .tinted, tintColor: accentColor, size: 54, isPro: true, glassIntensity: glassLevel)
                    Text("Teinté")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }

            // Indicateur visuel du % Liquid Glass & Dock Favoris
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "drop.halffull")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(accentColor)
                    Text("Liquid Glass : \(Int(round(glassLevel * 100))) %")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.10), in: Capsule())

                HStack(spacing: 5) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.yellow)
                    Text("Dock Favoris épinglé")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.10), in: Capsule())
            }
        }
        .onAppear {
            loopTask?.cancel()
            loopTask = Task { @MainActor in
                while !Task.isCancelled {
                    withAnimation(.easeInOut(duration: 0.7)) { glassLevel = 0.25; searchHighlight = false }
                    try? await Task.sleep(for: .milliseconds(900))
                    guard !Task.isCancelled else { break }
                    withAnimation(.easeInOut(duration: 0.7)) { glassLevel = 0.95; searchHighlight = true }
                    try? await Task.sleep(for: .milliseconds(1300))
                }
            }
        }
        .onDisappear {
            loopTask?.cancel()
            loopTask = nil
        }
    }
}

// MARK: - ANIMATION 3 : Déplacer une App & Changer de Page

private struct AnimStep2DragAndPage: View {
    let accentColor: Color
    @ObservedObject private var locManager = LocalizationManager.shared

    @State private var phase: Int = 0 // 0: repos, 1: levé, 2: bord droit, 3: flip page, 4: dépose, 5: succès
    @State private var activePage: Int = 0
    @State private var loopTask: Task<Void, Never>? = nil

    // Coordonnées de Safari
    private var safariX: CGFloat {
        switch phase {
        case 0: return 0
        case 1: return 0
        case 2: return 125
        case 3: return 125
        case 4, 5: return 75
        default: return 0
        }
    }

    private var safariY: CGFloat {
        switch phase {
        case 0: return 0
        case 1, 2, 3: return -8
        case 4, 5: return 0
        default: return 0
        }
    }

    private var isSafariLifted: Bool {
        phase >= 1 && phase <= 3
    }

    // Coordonnées du curseur
    private var cursorX: CGFloat {
        switch phase {
        case 0: return 20
        case 1: return 18
        case 2, 3: return 143
        case 4: return 93
        case 5: return 110
        default: return 20
        }
    }

    private var cursorY: CGFloat {
        switch phase {
        case 0: return 32
        case 1, 2, 3: return 10
        case 4: return 10
        case 5: return 36
        default: return 32
        }
    }

    // Décalage des pages
    private var page1Offset: CGFloat {
        phase >= 3 ? -320 : 0
    }

    private var page2Offset: CGFloat {
        phase >= 3 ? 0 : 320
    }

    private var statusText: String {
        switch phase {
        case 0:
            return loc("tuto.move.status1")
        case 1:
            return loc("tuto.move.status2")
        case 2:
            return loc("tuto.move.status3")
        case 3:
            return loc("tuto.move.status4")
        case 4, 5:
            return loc("tuto.move.status5")
        default:
            return ""
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                // Cadre de l'écran LaunchPad
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .frame(width: 350, height: 115)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )

                // Halo lumineux sur le bord droit lorsque l'icône atteint le bord
                if phase == 2 || phase == 3 {
                    HStack {
                        Spacer()
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                LinearGradient(
                                    colors: [accentColor.opacity(0.5), accentColor.opacity(0.0)],
                                    startPoint: .trailing,
                                    endPoint: .leading
                                )
                            )
                            .frame(width: 34, height: 115)
                    }
                    .frame(width: 350)
                    .transition(.opacity)
                }

                // CONTENU DES PAGES
                ZStack {
                    // PAGE 1 : Finder (-75), Emplacement Safari vide (0), Photos (+75)
                    ZStack {
                        appTile(name: "Finder", icon: "macwindow", color: .blue)
                            .offset(x: -75)

                        // Emplacement d'origine en pointillés quand Safari est soulevée
                        if isSafariLifted {
                            VStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.2), style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                                    .frame(width: 48, height: 48)
                                Text(loc("tuto.move.page_n", 1))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white.opacity(0.25))
                            }
                            .offset(x: 0)
                        }

                        appTile(name: "Photos", icon: "photo.stack.fill", color: .pink)
                            .offset(x: 75)
                    }
                    .offset(x: page1Offset)
                    .opacity(phase >= 3 ? 0.0 : 1.0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: page1Offset)

                    // PAGE 2 : Terminal (-75), Xcode (0)
                    ZStack {
                        appTile(name: "Terminal", icon: "terminal.fill", color: .gray)
                            .offset(x: -75)

                        appTile(name: "Xcode", icon: "hammer.fill", color: Color(red: 0.2, green: 0.6, blue: 1.0))
                            .offset(x: 0)

                        // Emplacement cible récepteur en pointillés (avant que Safari se pose)
                        if phase == 3 {
                            VStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(accentColor.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                                    .frame(width: 48, height: 48)
                                    .overlay(
                                        Image(systemName: "plus")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundStyle(accentColor.opacity(0.7))
                                    )
                                Text(loc("tuto.move.drop"))
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(accentColor)
                            }
                            .offset(x: 75)
                            .transition(.opacity)
                        }
                    }
                    .offset(x: page2Offset)
                    .opacity(phase >= 3 ? 1.0 : 0.0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: page2Offset)

                    // ICÔNE UNIQUE DE SAFARI (Qui se déplace fluidement sans duplication)
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.cyan)
                            .frame(width: isSafariLifted ? 52 : 48, height: isSafariLifted ? 52 : 48)
                            .overlay(
                                Image(systemName: "safari.fill")
                                    .font(.system(size: isSafariLifted ? 24 : 22))
                                    .foregroundStyle(.white)
                            )
                            .shadow(color: isSafariLifted ? .black.opacity(0.6) : .clear, radius: isSafariLifted ? 14 : 0, y: isSafariLifted ? 8 : 0)
                            .scaleEffect(isSafariLifted ? 1.12 : 1.0)

                        Text("Safari")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(.white)
                            .opacity(isSafariLifted ? 0.0 : 1.0)
                    }
                    .offset(x: safariX, y: safariY)
                    .animation(.spring(response: 0.45, dampingFraction: 0.78), value: safariX)
                    .animation(.spring(response: 0.35, dampingFraction: 0.78), value: safariY)

                    // CURSEUR SOURIS MACOS
                    Image(systemName: "cursorarrow")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.8), radius: 4, y: 2)
                        .offset(x: cursorX, y: cursorY)
                        .animation(.spring(response: 0.45, dampingFraction: 0.78), value: cursorX)
                        .animation(.spring(response: 0.45, dampingFraction: 0.78), value: cursorY)
                }
            }
            .frame(width: 350, height: 115)
            .clipped()

            // Indicateur de page (Dots)
            HStack(spacing: 8) {
                Capsule()
                    .fill(activePage == 0 ? accentColor : Color.white.opacity(0.25))
                    .frame(width: activePage == 0 ? 20 : 6, height: 6)
                    .animation(.spring(response: 0.35, dampingFraction: 0.75), value: activePage)

                Capsule()
                    .fill(activePage == 1 ? accentColor : Color.white.opacity(0.25))
                    .frame(width: activePage == 1 ? 20 : 6, height: 6)
                    .animation(.spring(response: 0.35, dampingFraction: 0.75), value: activePage)
            }

            // Explication dynamique de l'action
            HStack(spacing: 6) {
                Image(systemName: phase >= 4 ? "checkmark.circle.fill" : "arrow.right.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(phase >= 4 ? Color.green : accentColor)
                Text(statusText)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(phase >= 4 ? Color.green : .white.opacity(0.88))
            }
        }
        .onAppear {
            loopTask?.cancel()
            loopTask = Task { @MainActor in
                while !Task.isCancelled {
                    await runCycle()
                    try? await Task.sleep(for: .seconds(1.6))
                }
            }
        }
        .onDisappear {
            loopTask?.cancel()
            loopTask = nil
        }
    }

    private func appTile(name: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color)
                .frame(width: 48, height: 48)
                .overlay(Image(systemName: icon).font(.system(size: 22)).foregroundStyle(.white))

            Text(name)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
        }
    }

    @MainActor
    private func runCycle() async {
        // Étape 0 : Début au repos sur Page 1
        phase = 0
        activePage = 0

        // Étape 1 : Le curseur attrape et soulève Safari
        try? await Task.sleep(for: .seconds(0.5))
        guard !Task.isCancelled else { return }
        phase = 1

        // Étape 2 : Déplacement vers le bord droit de l'écran
        try? await Task.sleep(for: .seconds(0.7))
        guard !Task.isCancelled else { return }
        phase = 2

        // Étape 3 : Déclenchement de la Page 2
        try? await Task.sleep(for: .seconds(0.8))
        guard !Task.isCancelled else { return }
        phase = 3
        activePage = 1

        // Étape 4 : Dépose de Safari sur la Page 2
        try? await Task.sleep(for: .seconds(0.7))
        guard !Task.isCancelled else { return }
        phase = 4

        // Étape 5 : Curseur s'éloigne, état final validé
        try? await Task.sleep(for: .seconds(0.5))
        guard !Task.isCancelled else { return }
        phase = 5
    }
}

// MARK: - ANIMATION 4 : Création de Dossiers (Superposition au Centre)

private struct AnimStep3CreateFolder: View {
    let accentColor: Color
    @ObservedObject private var locManager = LocalizationManager.shared

    @State private var dragX: CGFloat = 55.0
    @State private var musicX: CGFloat = -55.0
    @State private var isLifted = false
    @State private var isFolderOpen = false
    @State private var loopTask: Task<Void, Never>? = nil

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                if isFolderOpen {
                    // DOSSIER CRÉÉ PARFAITEMENT AU MILIEU (x = 0)
                    VStack(spacing: 4) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.white.opacity(0.16))
                                .frame(width: 76, height: 76)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(accentColor, lineWidth: 2)
                                )
                                .shadow(color: accentColor.opacity(0.6), radius: 16)

                            // Les 2 icônes à l'intérieur du dossier
                            HStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.pink)
                                    .frame(width: 26, height: 26)
                                    .overlay(Image(systemName: "music.note").font(.system(size: 12, weight: .bold)).foregroundStyle(.white))

                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.orange)
                                    .frame(width: 26, height: 26)
                                    .overlay(Image(systemName: "photo.stack.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(.white))
                            }
                        }

                        Text(loc("tuto.folder.sample_name"))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(accentColor)
                    }
                    .transition(.scale(scale: 0.85).combined(with: .opacity))

                } else {
                    // Les 2 applications séparées avant la création
                    // Musique (se déplace de -55 vers 0 pour fusionner au milieu)
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.pink)
                            .frame(width: 48, height: 48)
                            .overlay(Image(systemName: "music.note").font(.system(size: 22)).foregroundStyle(.white))

                        Text(loc("app_sample.music"))
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .offset(x: musicX)

                    // Emplacement d'origine de Photos (reste visible en pointillés quand Photos est soulevée)
                    if isLifted {
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                                .frame(width: 48, height: 48)

                            Text("Photos")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                        .offset(x: 55)
                    }

                    // Photos (se déplace de +55 vers 0 pour fusionner au milieu)
                    if !isFolderOpen {
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.orange)
                                .frame(width: isLifted ? 52 : 48, height: isLifted ? 52 : 48)
                                .overlay(Image(systemName: "photo.stack.fill").font(.system(size: isLifted ? 24 : 22)).foregroundStyle(.white))
                                .shadow(color: isLifted ? .black.opacity(0.55) : .clear, radius: 14, y: 8)
                                .scaleEffect(isLifted ? 1.15 : 1.0)

                            if !isLifted {
                                Text("Photos")
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                        }
                        .offset(x: dragX, y: isLifted ? -6 : 0)
                    }
                }

                // Curseur macOS
                Image(systemName: "cursorarrow")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.7), radius: 4, y: 2)
                    .offset(x: isFolderOpen ? 34 : dragX + 22, y: isFolderOpen ? 26 : (isLifted ? 12 : 26))
            }
            .frame(height: 105)

            HStack(spacing: 6) {
                Image(systemName: isFolderOpen ? "folder.badge.plus" : "square.stack.3d.down.right.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(accentColor)
                Text(isFolderOpen ? loc("tuto.folder.created") : loc("tuto.folder.drag_hint"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isFolderOpen ? accentColor : .white.opacity(0.85))
            }
        }
        .onAppear {
            startLoop()
        }
        .onDisappear {
            loopTask?.cancel()
            loopTask = nil
        }
    }

    private func startLoop() {
        loopTask?.cancel()
        loopTask = Task { @MainActor in
            while !Task.isCancelled {
                dragX = 55
                musicX = -55
                isFolderOpen = false
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isLifted = true
                }

                // Déplacement des deux icônes vers le centre (0)
                try? await Task.sleep(for: .seconds(0.35))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.9)) {
                    dragX = 0
                    musicX = 0
                }

                // Fusion au centre
                try? await Task.sleep(for: .seconds(1.0))
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.72)) {
                    isFolderOpen = true
                    isLifted = false
                }

                // Réinitialisation
                try? await Task.sleep(for: .seconds(1.55))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.5)) {
                    dragX = 55
                    musicX = -55
                    isFolderOpen = false
                }

                try? await Task.sleep(for: .seconds(0.9))
            }
        }
    }
}

// MARK: - ANIMATION 5 : Widgets & Platine Vinyle

private struct AnimStep4WidgetsVinyl: View {
    let accentColor: Color
    @ObservedObject private var locManager = LocalizationManager.shared

    @State private var rotation: Double = 0
    @State private var noteOffset: CGFloat = 0
    @State private var sheenOffset: CGFloat = -160

    var body: some View {
        HStack(spacing: 32) {
            // Widget Vinyle Réaliste
            HStack(spacing: 14) {
                ZStack {
                    // Disque vinyle avec sillons
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(white: 0.08), Color(white: 0.16), Color(white: 0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 82, height: 82)
                        .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                        .overlay(Circle().stroke(Color.white.opacity(0.06), lineWidth: 1).frame(width: 64, height: 64))
                        .overlay(Circle().stroke(Color.white.opacity(0.06), lineWidth: 1).frame(width: 48, height: 48))
                        .rotationEffect(.degrees(rotation))

                    // Macaron central
                    Circle()
                        .fill(LinearGradient(colors: [accentColor, .orange], startPoint: .top, endPoint: .bottom))
                        .frame(width: 30, height: 30)
                        .overlay(Image(systemName: "music.note").font(.system(size: 12, weight: .bold)).foregroundStyle(.white))
                        .rotationEffect(.degrees(rotation))

                    // Bras de lecture
                    Rectangle()
                        .fill(Color(white: 0.8))
                        .frame(width: 3, height: 40)
                        .rotationEffect(.degrees(24), anchor: .top)
                        .offset(x: 32, y: -18)

                    // Notes de musique flottantes
                    Image(systemName: "music.quarternote.3")
                        .font(.system(size: 15))
                        .foregroundStyle(accentColor)
                        .offset(x: 12, y: noteOffset)
                        .opacity(Double(1.0 - abs(noteOffset) / 36))
                        .blur(radius: abs(noteOffset) / 16)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(loc("tuto.widgets.vinyl_title"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                    Text(loc("tuto.widgets.vinyl_sub"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: 130)
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )

            // Carte Thème Liquid Glass
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 150, height: 95)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.4), Color.white.opacity(0.06)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.2
                            )
                    )

                // Reflet traversant doux (gradient lissé sans passe blur)
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color.white.opacity(0.14),
                                Color.white.opacity(0.32),
                                Color.white.opacity(0.14),
                                Color.clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 52, height: 110)
                    .rotationEffect(.degrees(25))
                    .offset(x: sheenOffset)
                    .mask(RoundedRectangle(cornerRadius: 16, style: .continuous).frame(width: 150, height: 95))

                VStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 18))
                        .foregroundStyle(accentColor)
                    Text(loc("tuto.widgets.glass_title"))
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(.white)
                    Text(loc("tuto.widgets.glass_sub"))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .onAppear {
            guard !Prefs.reduceMotion else { return }
            withAnimation(.linear(duration: 8.0).repeatForever(autoreverses: false)) {
                rotation = 360
            }
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: false)) {
                sheenOffset = 160
            }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                noteOffset = -28
            }
        }
    }
}

// MARK: - ANIMATION 6 : Essai Gratuit 7 Jours & Paiement Pro

private struct AnimStep5ProTrial: View {
    let accentColor: Color

    @ObservedObject private var licenseManager = LicenseManager.shared
    @ObservedObject private var locManager = LocalizationManager.shared
    @State private var showingKeyInput = false
    @State private var enteredKey = ""
    @State private var feedbackText: String? = nil
    @State private var feedbackIsError = false

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                // CARTE 1 : ESSAI GRATUIT 7 JOURS
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: licenseManager.isTrialActive ? "hourglass" : "gift.fill")
                                .font(.system(size: 10.5, weight: .bold))
                            Text(licenseManager.isTrialActive ? loc("tuto.pro.trial_in_progress") : loc("tuto.pro.trial_offer"))
                                .font(.system(size: 9.5, weight: .bold))
                                .tracking(0.5)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.18))
                        .foregroundStyle(Color.orange)
                        .clipShape(Capsule())

                        Spacer()

                        if licenseManager.isTrialActive {
                            HStack(spacing: 4) {
                                AnimatedVerifiedSealBadge(isTrial: true, size: 14)
                                Text(loc("tuto.pro.active"))
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Color(red: 1.00, green: 0.80, blue: 0.12))
                            }
                        }
                    }

                    if licenseManager.isTrialActive {
                        // Compte à rebours dynamique en grand (isolé sur countdown)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(loc("tuto.pro.live_countdown"))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.75))

                            TrialCountdownBoxesView(countdown: licenseManager.countdown)

                            HStack {
                                Text(loc("tuto.pro.auto_revert"))
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(.white.opacity(0.65))

                                Spacer()

                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        licenseManager.cancelTrial()
                                    }
                                } label: {
                                    Text(loc("tuto.pro.cancel_trial"))
                                        .font(.system(size: 9.5, weight: .semibold))
                                        .foregroundStyle(Color.red.opacity(0.85))
                                        .underline()
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } else if licenseManager.isProLifetime {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(loc("tuto.pro.unlocked_title"))
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)

                            Text(loc("tuto.pro.unlocked_desc"))
                                .font(.system(size: 10.5))
                                .foregroundStyle(.white.opacity(0.75))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 6)
                    } else {
                        // Présentation de l'essai 7 jours
                        VStack(alignment: .leading, spacing: 4) {
                            Text(loc("tuto.pro.trial_card_title"))
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)

                            Text(loc("tuto.pro.trial_card_desc"))
                                .font(.system(size: 10.5))
                                .foregroundStyle(.white.opacity(0.75))
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()

                        Button {
                            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                licenseManager.startSevenDayTrial()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 11, weight: .bold))
                                Text(loc("tuto.pro.activate_trial"))
                                    .font(.system(size: 11.5, weight: .bold))
                            }
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(
                                LinearGradient(
                                    colors: [Color(red: 1.0, green: 0.82, blue: 0.2), Color.orange],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .shadow(color: Color.orange.opacity(0.4), radius: 6, y: 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(licenseManager.isTrialActive ? Color.orange.opacity(0.6) : Color.white.opacity(0.12), lineWidth: 1.2)
                )

                // CARTE 2 : PAYER LA VERSION PRO (ACCÈS PERMANENT)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 10.5, weight: .bold))
                            Text(licenseManager.isProLifetime ? loc("tuto.pro.lifetime_badge") : loc("tuto.pro.unlimited_badge"))
                                .font(.system(size: 9.5, weight: .bold))
                                .tracking(0.5)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.purple.opacity(0.2))
                        .foregroundStyle(Color(red: 0.85, green: 0.65, blue: 1.0))
                        .clipShape(Capsule())

                        Spacer()

                        if licenseManager.isProLifetime {
                            AnimatedVerifiedSealBadge(isTrial: false, size: 18)
                        }
                    }

                    if licenseManager.isProLifetime {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(loc("tuto.pro.perm_active_title"))
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)

                            if !licenseManager.licenseKey.isEmpty {
                                Text(loc("tuto.pro.key_fmt", licenseManager.licenseKey))
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.7))
                            }

                            Text(loc("tuto.pro.perm_active_desc"))
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.65))
                        }
                        .padding(.vertical, 6)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(loc("tuto.pro.pay_title"))
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)

                            Text(loc("tuto.pro.pay_desc"))
                                .font(.system(size: 10.5))
                                .foregroundStyle(.white.opacity(0.75))
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if showingKeyInput {
                            HStack(spacing: 5) {
                                TextField(loc("tuto.pro.key_placeholder"), text: $enteredKey)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 11, design: .monospaced))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(Color.black.opacity(0.4))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.2)))

                                Button(loc("dialog.ok")) {
                                    validateKey()
                                }
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }

                        if let feedback = feedbackText {
                            Text(feedback)
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(feedbackIsError ? Color.red : Color.green)
                        }

                        Spacer()

                        HStack(spacing: 6) {
                            Button {
                                licenseManager.openGetProPage()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "cart.fill")
                                        .font(.system(size: 10))
                                    Text(loc("tuto.pro.buy_btn"))
                                        .font(.system(size: 11, weight: .bold))
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .background(
                                    LinearGradient(
                                        colors: [Color.purple, Color.blue],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)

                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showingKeyInput.toggle()
                                }
                            } label: {
                                Image(systemName: "key.fill")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.white.opacity(0.85))
                                    .padding(7)
                                    .background(Color.white.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .help(loc("tuto.pro.key_help"))
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(licenseManager.isProLifetime ? Color.purple.opacity(0.6) : Color.white.opacity(0.12), lineWidth: 1.2)
                )
            }
        }
    }

    private func validateKey() {
        let res = licenseManager.validate(code: enteredKey)
        if res.success {
            feedbackText = loc("tuto.pro.activated_feedback")
            feedbackIsError = false
            showingKeyInput = false
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
        } else {
            feedbackText = res.message
            feedbackIsError = true
        }
    }
}

private struct TrialCountdownBoxesView: View {
    @ObservedObject var countdown: TrialCountdownState
    @ObservedObject private var locManager = LocalizationManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                countdownBox(val: String(format: "%02d", countdown.trialDaysRemaining), unit: loc("tuto.unit.days"))
                Text(":").font(.system(size: 14, weight: .bold)).foregroundStyle(.white.opacity(0.5))
                countdownBox(val: String(format: "%02d", countdown.trialHoursRemaining), unit: loc("tuto.unit.hours"))
                Text(":").font(.system(size: 14, weight: .bold)).foregroundStyle(.white.opacity(0.5))
                countdownBox(val: String(format: "%02d", countdown.trialMinutesRemaining), unit: loc("tuto.unit.min"))
                Text(":").font(.system(size: 14, weight: .bold)).foregroundStyle(.white.opacity(0.5))
                countdownBox(val: String(format: "%02d", countdown.trialSecondsRemaining), unit: loc("tuto.unit.sec"))
            }

            // Jauge de progression
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(LinearGradient(colors: [Color.orange, Color.yellow], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(6, geo.size.width * CGFloat(1.0 - countdown.trialProgress)), height: 4)
                }
            }
            .frame(height: 4)
            .padding(.top, 2)
        }
        .onAppear { LicenseManager.shared.beginCountdownObservation() }
        .onDisappear { LicenseManager.shared.endCountdownObservation() }
    }

    private func countdownBox(val: String, unit: String) -> some View {
        VStack(spacing: 1.5) {
            Text(val)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.15), lineWidth: 0.8))
            Text(unit)
                .font(.system(size: 7.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}

// MARK: - Modal intégré au Launchpad

struct TutorialModalView: View {
    let vm: LaunchpadViewModel

    var body: some View {
        ZStack {
            // Voile sombre statique sans fermeture sur clic (ESC uniquement)
            Color.black.opacity(0.50)
                .ignoresSafeArea()
                .contentShape(Rectangle())

            // Carte de tutoriel interactive Aura 4C
            TutorialCardView(vm: vm, initialStepIndex: vm.tutorialStepIndex) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    vm.showTutorial = false
                }
            }
        }
        .zIndex(100)
    }
}
