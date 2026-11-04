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
}

// MARK: - Vue Principale du Tutoriel Interactif

struct TutorialCardView: View {
    var vm: LaunchpadViewModel? = nil
    var initialStepIndex: Int = 0
    var onDismiss: (() -> Void)? = nil

    @State private var currentStepIndex: Int

    init(vm: LaunchpadViewModel? = nil, initialStepIndex: Int = 0, onDismiss: (() -> Void)? = nil) {
        self.vm = vm
        self.initialStepIndex = initialStepIndex
        self.onDismiss = onDismiss
        self._currentStepIndex = State(initialValue: initialStepIndex)
    }

    private let steps: [TutorialStep] = [
        TutorialStep(
            id: 0,
            badge: "OUVERTURE RAPIDE",
            tabTitle: "1. Ouverture",
            title: "Comment ouvrir et fermer LaunchPad",
            subtitle: "Accédez à toutes vos applications en une fraction de seconde grâce aux gestes naturels de macOS.",
            icon: "hand.draw.fill",
            iconColor: Color(red: 0.22, green: 0.64, blue: 1.0),
            instruction: "Pincez à 3 ou 4 doigts sur le trackpad ou appuyez sur ⌃ Espace"
        ),
        TutorialStep(
            id: 1,
            badge: "RECHERCHE INSTANTANÉE",
            tabTitle: "2. Recherche",
            title: "Comment chercher et lancer une app au clavier",
            subtitle: "Trouvez et lancez n'importe quelle application sans même toucher à votre souris.",
            icon: "magnifyingglass",
            iconColor: Color(red: 0.85, green: 0.40, blue: 1.0),
            instruction: "Tapez directement le nom d'une app, puis appuyez sur Entrée"
        ),
        TutorialStep(
            id: 2,
            badge: "ORGANISATION DES PAGES",
            tabTitle: "3. Déplacer",
            title: "Comment déplacer une app & changer de page",
            subtitle: "Réorganisez vos applications librement sur la grille ou déplacez-les vers une autre page.",
            icon: "arrow.up.and.down.and.arrow.left.and.right",
            iconColor: Color(red: 0.38, green: 0.85, blue: 0.55),
            instruction: "Glissez une icône vers le bord droit ou gauche pour changer de page"
        ),
        TutorialStep(
            id: 3,
            badge: "CRÉATION DE DOSSIERS",
            tabTitle: "4. Dossiers",
            title: "Comment créer un dossier en 1 seconde",
            subtitle: "Regroupez vos applications par catégorie simplement en les superposant.",
            icon: "folder.badge.plus",
            iconColor: Color(red: 1.0, green: 0.60, blue: 0.20),
            instruction: "Superposez deux icônes pour créer automatiquement un dossier"
        ),
        TutorialStep(
            id: 4,
            badge: "WIDGETS & PRO",
            tabTitle: "5. Widgets",
            title: "Comment utiliser les Widgets & le style Liquid Glass",
            subtitle: "Contrôlez votre musique avec la platine vinyle en direct et profitez des reflets de verre dépoli.",
            icon: "opticaldisc.fill",
            iconColor: Color(red: 1.0, green: 0.80, blue: 0.15),
            instruction: "Profitez de la platine vinyle interactive et des widgets dynamiques"
        )
    ]

    var body: some View {
        let currentStep = steps[currentStepIndex]

        VStack(spacing: 0) {
            // Barre supérieure : Badge étape, Titre & Bouton Fermer
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    HStack(spacing: 5) {
                        Image(systemName: currentStep.icon)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(currentStep.iconColor)
                        Text(currentStep.badge)
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(currentStep.iconColor)
                            .tracking(1.0)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3.5)
                    .background(currentStep.iconColor.opacity(0.16))
                    .clipShape(Capsule())

                    Text("Étape \(currentStepIndex + 1) sur \(steps.count)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Text("Passer")
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.10))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)

            // Titre et Sous-titre
            VStack(spacing: 4) {
                Text(currentStep.title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text(currentStep.subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: 520)
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 12)

            // SCÈNE ANIMÉE CENTRALE (Démonstration Visuelle Réaliste)
            ZStack {
                // Cadre de l'écran simulateur
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.35))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )

                // Halo d'ambiance avec flou
                Circle()
                    .fill(currentStep.iconColor.opacity(0.18))
                    .frame(width: 220, height: 220)
                    .blur(radius: 40)
                    .allowsHitTesting(false)

                // Animation dédiée selon l'étape
                Group {
                    switch currentStepIndex {
                    case 0:
                        AnimStep0OpenClose(accentColor: currentStep.iconColor)
                    case 1:
                        AnimStep1SearchLaunch(accentColor: currentStep.iconColor)
                    case 2:
                        AnimStep2DragAndPage(accentColor: currentStep.iconColor)
                    case 3:
                        AnimStep3CreateFolder(accentColor: currentStep.iconColor)
                    case 4:
                        AnimStep4WidgetsVinyl(accentColor: currentStep.iconColor)
                    default:
                        EmptyView()
                    }
                }
                .padding(14)
            }
            .frame(height: 235)
            .padding(.horizontal, 22)

            // Bannière d'instruction claire
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(currentStep.iconColor)
                Text(currentStep.instruction)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(currentStep.iconColor.opacity(0.14))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(currentStep.iconColor.opacity(0.3), lineWidth: 1))
            .padding(.top, 10)

            Divider()
                .background(Color.white.opacity(0.12))
                .padding(.horizontal, 22)
                .padding(.top, 14)

            // Pied de carte : Navigation Suivant / Précédent & Indicateur de progression
            HStack {
                if currentStepIndex > 0 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            currentStepIndex -= 1
                            vm?.tutorialStepIndex = currentStepIndex
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11, weight: .bold))
                            Text("Précédent")
                                .font(.system(size: 12.5, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer().frame(width: 80)
                }

                Spacer()

                // Indicateur de points d'étapes (Apple style discret)
                HStack(spacing: 6) {
                    ForEach(0..<steps.count, id: \.self) { idx in
                        Capsule()
                            .fill(idx == currentStepIndex ? currentStep.iconColor : Color.white.opacity(0.25))
                            .frame(width: idx == currentStepIndex ? 18 : 6, height: 6)
                            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: currentStepIndex)
                    }
                }

                Spacer()

                if currentStepIndex < steps.count - 1 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            currentStepIndex += 1
                            vm?.tutorialStepIndex = currentStepIndex
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text("Étape suivante")
                                .font(.system(size: 13, weight: .bold))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 9)
                        .background(
                            LinearGradient(
                                colors: [currentStep.iconColor, currentStep.iconColor.opacity(0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .shadow(color: currentStep.iconColor.opacity(0.4), radius: 8, y: 3)
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
                        .padding(.horizontal, 20)
                        .padding(.vertical, 9)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .shadow(color: .white.opacity(0.35), radius: 10, y: 3)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
        }
        .frame(width: 650, height: 490)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.35), Color.white.opacity(0.08), Color.white.opacity(0.20)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.2
                        )
                )
                .shadow(color: .black.opacity(0.6), radius: 36, y: 16)
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

// MARK: - ANIMATION 1 : Ouvrir & Fermer LaunchPad (Trackpad + ⌃ Espace)

private struct AnimStep0OpenClose: View {
    let accentColor: Color

    @State private var pinchProgress: CGFloat = 0.0
    @State private var isKeyPressed = false
    @State private var launchpadOpacity: Double = 0.0
    @State private var launchpadScale: CGFloat = 0.85
    @State private var statusMessage = "1. Pincez ou pressez ⌃ Espace"
    @State private var timer: Timer? = nil

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
                        Text("ctrl")
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
                        Text("Espace")
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

                Text(statusMessage)
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

                    // Vague abstraite lumineuse dans le fond d'écran
                    Circle()
                        .fill(Color.orange.opacity(0.35))
                        .frame(width: 180, height: 180)
                        .blur(radius: 40)
                        .offset(x: 60, y: 30)

                    // 2. Barre des menus macOS supérieure (Apple, Finder, Heure)
                    VStack {
                        HStack(spacing: 6) {
                            Text("")
                                .font(.system(size: 9, weight: .bold))
                            Text("Finder")
                                .font(.system(size: 8, weight: .bold))
                            Text("Fichier")
                                .font(.system(size: 7.5, weight: .regular))
                            Text("Édition")
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
                                Text("Rechercher...")
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
                                miniLaunchIcon(name: "Musique", icon: "music.note", color: .red)
                                miniLaunchIcon(name: "Terminal", icon: "terminal.fill", color: .gray)
                                miniLaunchIcon(name: "Xcode", icon: "hammer.fill", color: .blue)
                                miniLaunchIcon(name: "Mail", icon: "envelope.fill", color: .indigo)
                                miniLaunchIcon(name: "Notes", icon: "note.text", color: .yellow)
                                miniLaunchIcon(name: "Réglages", icon: "gearshape.fill", color: .gray)
                            }

                            Spacer()
                        }

                        // Badge de confirmation vert "LaunchPad Ouvert"
                        HStack(spacing: 4) {
                            Circle().fill(Color.green).frame(width: 6, height: 6)
                            Text("LaunchPad Ouvert")
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
            runAnimationCycle()
            timer = Timer.scheduledTimer(withTimeInterval: 6.2, repeats: true) { _ in
                runAnimationCycle()
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
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

    private func runAnimationCycle() {
        // 0. ÉTAT INITIAL AU REPOS (Bureau macOS)
        withAnimation(.easeOut(duration: 0.3)) {
            launchpadOpacity = 0.0
            launchpadScale = 0.85
            pinchProgress = 0.0
            isKeyPressed = false
            statusMessage = "1. Pincez ou pressez ⌃ Espace"
        }

        // 1. GESTE D'OUVERTURE : Doigts pincent + touches s'enfoncent -> LaunchPad zoome et s'affiche SIMULTANÉMENT !
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                pinchProgress = 1.0
                isKeyPressed = true
                launchpadOpacity = 1.0
                launchpadScale = 1.0
                statusMessage = "✦ Le geste ouvre LaunchPad !"
            }
        }

        // 2. Relâchement des doigts : LaunchPad reste grand ouvert et stable
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) {
            withAnimation(.easeOut(duration: 0.3)) {
                pinchProgress = 0.0
                isKeyPressed = false
                statusMessage = "✦ LaunchPad est ouvert et prêt"
            }
        }

        // 3. ANNONCE DE LA FERMETURE (l'utilisateur lit ce qui va se passer)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.4) {
            statusMessage = "2. Pincez à nouveau pour fermer..."
        }

        // 4. GESTE DE FERMETURE EN DIRECT : Doigts pincent + touches s'enfoncent -> LaunchPad se referme SIMULTANÉMENT !
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.1) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                pinchProgress = 1.0
                isKeyPressed = true
                launchpadOpacity = 0.0
                launchpadScale = 0.85
                statusMessage = "✦ Le geste referme LaunchPad !"
            }
        }

        // 5. Relâchement des doigts sur le bureau : état final au repos
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.8) {
            withAnimation(.easeOut(duration: 0.3)) {
                pinchProgress = 0.0
                isKeyPressed = false
                statusMessage = "✦ Retour au bureau macOS"
            }
        }
    }
}

// MARK: - ANIMATION 2 : Recherche et Lancement au Clavier

private struct AnimStep1SearchLaunch: View {
    let accentColor: Color

    @State private var typed = ""
    @State private var isLaunched = false

    var body: some View {
        VStack(spacing: 14) {
            // Barre de recherche avec texte qui se tape automatiquement
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(accentColor)

                Text(typed.isEmpty ? "Recherche au clavier..." : typed)
                    .font(.system(size: 13, weight: typed.isEmpty ? .regular : .bold))
                    .foregroundStyle(typed.isEmpty ? .white.opacity(0.35) : .white)

                if !typed.isEmpty {
                    Rectangle().fill(accentColor).frame(width: 2, height: 14)
                }

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(width: 280)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(typed.isEmpty ? Color.white.opacity(0.12) : accentColor, lineWidth: 1.2)
                    )
            )

            // 4 Applications : les non-correspondantes se floutent, Safari s'ouvre
            HStack(spacing: 24) {
                appTile(name: "Notes", icon: "note.text", color: .yellow, isMatch: typed.isEmpty)
                appTile(name: "Safari", icon: "safari.fill", color: .blue, isMatch: true, isTarget: typed == "Safari")
                appTile(name: "Musique", icon: "music.note", color: .pink, isMatch: typed.isEmpty)
                appTile(name: "Terminal", icon: "terminal.fill", color: .gray, isMatch: typed.isEmpty)
            }

            // Touche Entrée qui se presse et lance l'app
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Text("↵").font(.system(size: 13, weight: .bold))
                    Text("Entrée").font(.system(size: 11, weight: .bold))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(isLaunched ? Color.green : accentColor)
                .clipShape(Capsule())
                .foregroundStyle(.white)
                .scaleEffect(isLaunched ? 1.08 : 1.0)

                Text(isLaunched ? "Application lancée instantanément !" : "Appuyez sur Entrée pour exécuter")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(isLaunched ? Color.green : .white.opacity(0.85))
            }
        }
        .onAppear {
            startLoop()
        }
    }

    private func appTile(name: String, icon: String, color: Color, isMatch: Bool, isTarget: Bool = false) -> some View {
        VStack(spacing: 4) {
            ZStack {
                if isTarget {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(accentColor.opacity(0.5))
                        .frame(width: 58, height: 58)
                        .blur(radius: 10)
                }

                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(color)
                    .frame(width: 48, height: 48)
                    .overlay(Image(systemName: icon).font(.system(size: 22)).foregroundStyle(.white))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isTarget ? Color.white : Color.clear, lineWidth: 2)
                    )
                    .scaleEffect(isTarget ? (isLaunched ? 1.25 : 1.15) : 1.0)
            }

            Text(name)
                .font(.system(size: 10.5, weight: isTarget ? .bold : .medium))
                .foregroundStyle(isTarget ? .white : .white.opacity(0.7))
        }
        .opacity(isMatch ? 1.0 : 0.22)
        .blur(radius: isMatch ? 0 : 5)
    }

    private func startLoop() {
        Timer.scheduledTimer(withTimeInterval: 3.4, repeats: true) { _ in
            typed = ""
            isLaunched = false

            for (idx, char) in "Safari".enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(idx) * 0.16 + 0.2) {
                    typed.append(char)
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    isLaunched = true
                }
            }
        }
    }
}

// MARK: - ANIMATION 3 : Déplacer une App & Changer de Page

private struct AnimStep2DragAndPage: View {
    let accentColor: Color

    @State private var phase: Int = 0 // 0: repos, 1: levé, 2: bord droit, 3: flip page, 4: dépose, 5: succès
    @State private var activePage: Int = 0
    @State private var timer: Timer? = nil

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
            return "Cliquez et maintenez une application..."
        case 1:
            return "L'icône se soulève..."
        case 2:
            return "Glissez vers le bord droit de l'écran..."
        case 3:
            return "La Page 2 s'affiche automatiquement !"
        case 4, 5:
            return "Déposez l'application dans son nouvel emplacement !"
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
                                Text("Page 1")
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
                                Text("Déposer")
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
            runCycle()
            timer = Timer.scheduledTimer(withTimeInterval: 4.8, repeats: true) { _ in
                runCycle()
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
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

    private func runCycle() {
        // Étape 0 : Début au repos sur Page 1
        phase = 0
        activePage = 0

        // Étape 1 : Le curseur attrape et soulève Safari
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            phase = 1
        }

        // Étape 2 : Déplacement vers le bord droit de l'écran
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            phase = 2
        }

        // Étape 3 : Déclenchement de la Page 2
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            phase = 3
            activePage = 1
        }

        // Étape 4 : Dépose de Safari sur la Page 2
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.7) {
            phase = 4
        }

        // Étape 5 : Curseur s'éloigne, état final validé
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
            phase = 5
        }
    }
}

// MARK: - ANIMATION 4 : Création de Dossiers (Superposition au Centre)

private struct AnimStep3CreateFolder: View {
    let accentColor: Color

    @State private var dragX: CGFloat = 55.0
    @State private var musicX: CGFloat = -55.0
    @State private var isLifted = false
    @State private var isFolderOpen = false

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

                        Text("Médias")
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

                        Text("Musique")
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
                Text(isFolderOpen ? "Dossier 'Médias' créé instantanément au centre !" : "Glissez une application directement sur une autre")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isFolderOpen ? accentColor : .white.opacity(0.85))
            }
        }
        .onAppear {
            startLoop()
        }
    }

    private func startLoop() {
        Timer.scheduledTimer(withTimeInterval: 3.8, repeats: true) { _ in
            dragX = 55
            musicX = -55
            isFolderOpen = false
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isLifted = true
            }

            // Déplacement des deux icônes vers le centre (0)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                withAnimation(.easeInOut(duration: 0.9)) {
                    dragX = 0
                    musicX = 0
                }
            }

            // Fusion au centre
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.35) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.72)) {
                    isFolderOpen = true
                    isLifted = false
                }
            }

            // Réinitialisation
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.9) {
                withAnimation(.easeInOut(duration: 0.5)) {
                    dragX = 55
                    musicX = -55
                    isFolderOpen = false
                }
            }
        }
    }
}

// MARK: - ANIMATION 5 : Widgets & Platine Vinyle

private struct AnimStep4WidgetsVinyl: View {
    let accentColor: Color

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
                    Text("Platine Vinyle")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Rotation en direct Apple Music & Spotify")
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

                // Reflet traversant
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.clear, Color.white.opacity(0.35), Color.clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 40, height: 110)
                    .rotationEffect(.degrees(25))
                    .offset(x: sheenOffset)
                    .blur(radius: 6)
                    .mask(RoundedRectangle(cornerRadius: 16, style: .continuous).frame(width: 150, height: 95))

                VStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 18))
                        .foregroundStyle(accentColor)
                    Text("Liquid Glass")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Reflets & verre dépoli")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .onAppear {
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

// MARK: - Modal intégré au Launchpad

struct TutorialModalView: View {
    @ObservedObject var vm: LaunchpadViewModel

    var body: some View {
        ZStack {
            // Fond d'ambiance avec flou
            Color.black.opacity(0.40)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        vm.showTutorial = false
                    }
                }

            // Orbes lumineuses d'ambiance avec flou (ne capturent pas les clics !)
            Circle()
                .fill(Color(red: 0.22, green: 0.64, blue: 1.0).opacity(0.22))
                .frame(width: 460, height: 460)
                .blur(radius: 110)
                .offset(x: -160, y: -100)
                .allowsHitTesting(false)

            Circle()
                .fill(Color(red: 0.85, green: 0.40, blue: 1.0).opacity(0.18))
                .frame(width: 400, height: 400)
                .blur(radius: 120)
                .offset(x: 180, y: 120)
                .allowsHitTesting(false)

            // Carte de tutoriel interactive
            TutorialCardView(vm: vm, initialStepIndex: vm.tutorialStepIndex) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    vm.showTutorial = false
                }
            }
            .transition(.scale(scale: 0.94).combined(with: .opacity))
        }
        .zIndex(100)
    }
}
