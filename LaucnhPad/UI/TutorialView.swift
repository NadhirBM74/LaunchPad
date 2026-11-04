import SwiftUI
import AppKit

// MARK: - Modèle d'une étape du tutoriel

struct TutorialStep: Identifiable {
    let id: Int
    let badge: String
    let title: String
    let subtitle: String
    let icon: String
    let iconColor: Color
    let features: [TutorialFeature]
}

struct TutorialFeature: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let description: String
    let tag: String?
}

// MARK: - Vue Principale du Tutoriel

struct TutorialCardView: View {
    var vm: LaunchpadViewModel? = nil
    var initialStepIndex: Int = 0
    var onDismiss: (() -> Void)? = nil

    @State private var currentStepIndex: Int
    @AppStorage(PrefKey.backgroundStyle) private var backgroundStyle: BackgroundStyle = .liquidGlass

    init(vm: LaunchpadViewModel? = nil, initialStepIndex: Int = 0, onDismiss: (() -> Void)? = nil) {
        self.vm = vm
        self.initialStepIndex = initialStepIndex
        self.onDismiss = onDismiss
        self._currentStepIndex = State(initialValue: initialStepIndex)
    }

    private let steps: [TutorialStep] = [
        TutorialStep(
            id: 0,
            badge: "BIENVENUE",
            title: "Bienvenue sur LaunchPad",
            subtitle: "Votre nouveau centre de contrôle et lanceur d'applications rapide, fluide et personnalisable pour macOS.",
            icon: "sparkles",
            iconColor: Color(red: 0.22, green: 0.64, blue: 1.0),
            features: [
                TutorialFeature(icon: "bolt.fill", title: "Ultra-rapide et natif", description: "Développé en Swift pur pour une réactivité instantanée à 120 FPS.", tag: "Performance"),
                TutorialFeature(icon: "macwindow.badge.plus", title: "Plein écran ou fenêtre", description: "Adaptez l'affichage selon votre espace de travail et vos préférences.", tag: "Affichage"),
                TutorialFeature(icon: "heart.fill", title: "Conçu pour vous", description: "Organisez vos outils favoris, widgets et raccourcis au même endroit.", tag: "Expérience")
            ]
        ),
        TutorialStep(
            id: 1,
            badge: "ACCÈS RAPIDE",
            title: "Ouvrez LaunchPad en un geste",
            subtitle: "Accédez à toutes vos applications en une fraction de seconde grâce à de multiples déclencheurs.",
            icon: "keyboard.fill",
            iconColor: Color(red: 0.38, green: 0.85, blue: 0.55),
            features: [
                TutorialFeature(icon: "command", title: "Raccourci clavier ⌃ Espace", description: "Invoquez le panneau immédiatement d'une seule main (modifiable dans les réglages).", tag: "Clavier"),
                TutorialFeature(icon: "hand.draw.fill", title: "Geste Trackpad naturel", description: "Pincez avec 3 ou 4 doigts sur votre trackpad pour ouvrir LaunchPad comme sur iOS.", tag: "Trackpad"),
                TutorialFeature(icon: "menubar.arrow.up.rectangle", title: "Barre des menus & Coins actifs", description: "Cliquez sur l'icône de la barre des menus ou glissez votre curseur dans un coin d'écran.", tag: "Système")
            ]
        ),
        TutorialStep(
            id: 2,
            badge: "ORGANISATION",
            title: "Organisation & Dossiers fluides",
            subtitle: "Disposez vos icônes exactement comme vous le souhaitez en quelques glisser-déposer.",
            icon: "square.grid.3x3.fill",
            iconColor: Color(red: 1.0, green: 0.60, blue: 0.20),
            features: [
                TutorialFeature(icon: "arrow.up.and.down.and.arrow.left.and.right", title: "Glisser-déposer libre", description: "Déplacez vos applications d'un emplacement à un autre ou vers une autre page.", tag: "Grille"),
                TutorialFeature(icon: "folder.badge.plus", title: "Dossiers automatiques", description: "Superposez deux icônes pour créer un dossier instantanément et les regrouper.", tag: "Dossiers"),
                TutorialFeature(icon: "contextualmenu.and.cursor", title: "Menu contextuel complet", description: "Faites un clic droit sur une icône pour la renommer, la masquer ou la désinstaller.", tag: "Actions")
            ]
        ),
        TutorialStep(
            id: 3,
            badge: "RECHERCHE",
            title: "Recherche instantanée au clavier",
            subtitle: "Trouvez et lancez n'importe quelle application sans même toucher votre souris.",
            icon: "magnifyingglass",
            iconColor: Color(red: 0.85, green: 0.40, blue: 1.0),
            features: [
                TutorialFeature(icon: "character.textbox", title: "Tapez directement", description: "Dès l'ouverture, commencez à saisir du texte : la recherche se focalise automatiquement.", tag: "Direct"),
                TutorialFeature(icon: "return", title: "Lancement à la touche Entrée", description: "Appuyez sur Entrée pour exécuter immédiatement le premier résultat sélectionné.", tag: "Efficace"),
                TutorialFeature(icon: "escape", title: "Touche Échap", description: "Une pression efface votre recherche, une seconde referme immédiatement le panneau.", tag: "Raccourci")
            ]
        ),
        TutorialStep(
            id: 4,
            badge: "PERSONNALISATION & PRO",
            title: "Widgets & Finitions d'exception",
            subtitle: "Sublimez votre bureau avec des widgets interactifs et des thèmes exclusifs.",
            icon: "crown.fill",
            iconColor: Color(red: 1.0, green: 0.80, blue: 0.15),
            features: [
                TutorialFeature(icon: "opticaldisc.fill", title: "Widget Platine Vinyle", description: "Suivez votre musique en direct avec rotation dynamique et commandes Apple Music / Spotify.", tag: "Musique"),
                TutorialFeature(icon: "sparkles", title: "Thème Liquid Glass", description: "Profitez de reflets lumineux, de verre dépoli dynamique et d'icônes teintées.", tag: "Design"),
                TutorialFeature(icon: "clock.badge.checkmark.fill", title: "Notes, Horloge & Système", description: "Gardez un œil sur le processeur, la mémoire vive et prenez des notes rapides.", tag: "Widgets")
            ]
        )
    ]

    var body: some View {
        ZStack {
            cardContent
        }
        .frame(maxWidth: 620)
        .padding(.horizontal, 24)
        .onExitCommand {
            dismiss()
        }
    }

    private var cardContent: some View {
        let currentStep = steps[currentStepIndex]

        return VStack(spacing: 0) {
            // Entête
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(currentStep.iconColor)
                    Text(currentStep.badge)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(currentStep.iconColor)
                        .tracking(1.2)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(currentStep.iconColor.opacity(0.15))
                .clipShape(Capsule())

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Text("Passer")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)

            // Corps principal de l'étape
            VStack(spacing: 16) {
                // Icône principale avec halo lumineux
                ZStack {
                    Circle()
                        .fill(currentStep.iconColor.opacity(0.20))
                        .frame(width: 68, height: 68)
                        .blur(radius: 10)

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [currentStep.iconColor.opacity(0.35), currentStep.iconColor.opacity(0.12)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 58, height: 58)
                        .overlay(Circle().stroke(currentStep.iconColor.opacity(0.4), lineWidth: 1.5))

                    Image(systemName: currentStep.icon)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .padding(.top, 4)

                // Titre et description
                VStack(spacing: 6) {
                    Text(currentStep.title)
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text(currentStep.subtitle)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .frame(maxWidth: 480)
                }

                // Liste des fonctionnalités clés
                VStack(spacing: 10) {
                    ForEach(currentStep.features) { feature in
                        HStack(alignment: .top, spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.white.opacity(0.08))
                                    .frame(width: 32, height: 32)
                                Image(systemName: feature.icon)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(currentStep.iconColor)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(feature.title)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.white)
                                    if let tag = feature.tag {
                                        Text(tag)
                                            .font(.system(size: 9, weight: .bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 1.5)
                                            .background(Color.white.opacity(0.12))
                                            .clipShape(Capsule())
                                            .foregroundStyle(.white.opacity(0.8))
                                    }
                                }
                                Text(feature.description)
                                    .font(.system(size: 11.5, weight: .regular))
                                    .foregroundStyle(.white.opacity(0.68))
                                    .lineLimit(2)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.04))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.white.opacity(0.07), lineWidth: 1)
                                )
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
            }
            .padding(.vertical, 14)

            Divider()
                .background(Color.white.opacity(0.10))
                .padding(.horizontal, 20)
                .padding(.top, 6)

            // Pied de carte : pagination et boutons
            HStack(alignment: .center) {
                // Indicateur de page (Dots)
                HStack(spacing: 6) {
                    ForEach(0..<steps.count, id: \.self) { idx in
                        Capsule()
                            .fill(idx == currentStepIndex ? currentStep.iconColor : Color.white.opacity(0.25))
                            .frame(width: idx == currentStepIndex ? 20 : 6, height: 6)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentStepIndex)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                    currentStepIndex = idx
                                }
                            }
                    }
                }

                Spacer()

                HStack(spacing: 10) {
                    if currentStepIndex > 0 {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                currentStepIndex -= 1
                            }
                        } label: {
                            Text("Précédent")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.85))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.10))
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                    if currentStepIndex < steps.count - 1 {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                currentStepIndex += 1
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Text("Suivant")
                                    .font(.system(size: 13, weight: .semibold))
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                LinearGradient(
                                    colors: [currentStep.iconColor, currentStep.iconColor.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .shadow(color: currentStep.iconColor.opacity(0.35), radius: 8, y: 3)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            dismiss()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 13, weight: .bold))
                                Text("Commencer à utiliser LaunchPad")
                                    .font(.system(size: 13, weight: .bold))
                            }
                            .foregroundStyle(.black)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .shadow(color: .white.opacity(0.3), radius: 10, y: 3)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
        }
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.35), Color.white.opacity(0.08), Color.white.opacity(0.18)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.2
                        )
                )
                .shadow(color: .black.opacity(0.55), radius: 36, y: 16)
        }
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
}

// MARK: - Modal intégré au Launchpad

struct TutorialModalView: View {
    @ObservedObject var vm: LaunchpadViewModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        vm.showTutorial = false
                    }
                }

            TutorialCardView(vm: vm)
                .transition(.scale(scale: 0.92).combined(with: .opacity))
        }
        .zIndex(100)
    }
}
