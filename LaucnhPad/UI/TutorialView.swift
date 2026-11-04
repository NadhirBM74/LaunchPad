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

// MARK: - Scènes Démonstratives Animées (Animations Fluides & Effets de Flou)

/// Scène interactive animée affichant visuellement le fonctionnement selon l'étape courante
struct TutorialStageView: View {
    let stepIndex: Int
    let accentColor: Color

    var body: some View {
        ZStack {
            // Fond en verre dépoli avec lueur diffuse d'ambiance
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.30), accentColor.opacity(0.20), Color.white.opacity(0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )

            // Lueur d'ambiance centrale avec flou
            Circle()
                .fill(accentColor.opacity(0.20))
                .frame(width: 160, height: 160)
                .blur(radius: 35)

            // Contenu animé spécifique à chaque étape
            Group {
                switch stepIndex {
                case 0:
                    TutorialStageOverview(accentColor: accentColor)
                case 1:
                    TutorialStageTriggers(accentColor: accentColor)
                case 2:
                    TutorialStageOrganize(accentColor: accentColor)
                case 3:
                    TutorialStageSearch(accentColor: accentColor)
                case 4:
                    TutorialStageWidgets(accentColor: accentColor)
                default:
                    TutorialStageOverview(accentColor: accentColor)
                }
            }
            .padding(14)
        }
        .frame(height: 180)
        .clipped()
    }
}

// MARK: - Étape 0 : Vue d'ensemble & Fluidité 120 FPS
private struct TutorialStageOverview: View {
    let accentColor: Color
    @State private var waveOffset: CGFloat = 0
    @State private var isFloating = false

    private let miniIcons: [(name: String, icon: String, color: Color)] = [
        ("Finder", "macwindow", Color.blue),
        ("Safari", "safari.fill", Color.cyan),
        ("Musique", "music.note", Color.red),
        ("Photos", "photo.stack.fill", Color.pink),
        ("Terminal", "terminal.fill", Color.gray),
        ("Réglages", "gearshape.fill", Color.purple)
    ]

    var body: some View {
        VStack(spacing: 12) {
            // Grille miniature flottante d'icônes avec reflets
            HStack(spacing: 18) {
                ForEach(0..<miniIcons.count, id: \.self) { idx in
                    let item = miniIcons[idx]
                    VStack(spacing: 4) {
                        ZStack {
                            // Halo flou sous chaque icône
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(item.color.opacity(0.35))
                                .frame(width: 38, height: 38)
                                .blur(radius: 6)

                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [item.color.opacity(0.85), item.color],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 36, height: 36)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                )

                            Image(systemName: item.icon)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .offset(y: isFloating ? (idx % 2 == 0 ? -3 : 3) : 0)
                        .animation(
                            .easeInOut(duration: 2.2).repeatForever(autoreverses: true).delay(Double(idx) * 0.15),
                            value: isFloating
                        )

                        Text(item.name)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
            }

            // Barre de dock miniature en verre dépoli
            HStack(spacing: 10) {
                Circle().fill(Color.white.opacity(0.3)).frame(width: 5, height: 5)
                Capsule().fill(accentColor.opacity(0.8)).frame(width: 32, height: 4)
                Circle().fill(Color.white.opacity(0.3)).frame(width: 5, height: 5)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.8))
            )

            // Lueur d'indication de réactivité
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(accentColor)
                Text("Affichage instantané • Fluidité 120 FPS")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.80))
            }
        }
        .onAppear {
            isFloating = true
        }
    }
}

// MARK: - Étape 1 : Accès Rapide (Pincement Trackpad & Clavier)
private struct TutorialStageTriggers: View {
    let accentColor: Color

    @State private var pinchProgress: CGFloat = 0.0
    @State private var rippleScale: CGFloat = 0.6
    @State private var rippleOpacity: Double = 0.0
    @State private var isKeyPressed = false

    var body: some View {
        HStack(spacing: 28) {
            // Démonstration 1 : Trackpad avec pincement de doigts
            VStack(spacing: 8) {
                ZStack {
                    // Surface du Trackpad avec bord doux
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                        .frame(width: 120, height: 86)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )

                    // Onde de choc / flou d'ouverture lors du pincement
                    Circle()
                        .stroke(accentColor.opacity(0.8), lineWidth: 2)
                        .frame(width: 60, height: 60)
                        .scaleEffect(rippleScale)
                        .opacity(rippleOpacity)
                        .blur(radius: 2)

                    // 4 doigts qui se pincent
                    let radius: CGFloat = 28 * (1.0 - pinchProgress * 0.72)
                    let angles: [Double] = [45, 135, 225, 315]

                    ForEach(0..<4, id: \.self) { i in
                        let rad = angles[i] * .pi / 180
                        Circle()
                            .fill(Color.white)
                            .frame(width: 11, height: 11)
                            .shadow(color: accentColor.opacity(0.8), radius: 6)
                            .offset(
                                x: cos(rad) * radius,
                                y: sin(rad) * radius
                            )
                    }

                    // Icône LaunchPad apparaissant au centre lors du pincement
                    Image(systemName: "square.grid.3x3.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(accentColor)
                        .scaleEffect(pinchProgress > 0.6 ? 1.0 : 0.0)
                        .opacity(Double(pinchProgress))
                        .blur(radius: (1.0 - pinchProgress) * 6)
                }

                HStack(spacing: 4) {
                    Image(systemName: "hand.draw.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(accentColor)
                    Text("Pincez à 3-4 doigts")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }

            // Séparateur vertical doux
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 1, height: 70)

            // Démonstration 2 : Touches Clavier ⌃ + Espace
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    // Touche Control
                    VStack {
                        Text("control")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                        Text("⌃")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 48, height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isKeyPressed ? accentColor.opacity(0.35) : Color.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(isKeyPressed ? accentColor : Color.white.opacity(0.2), lineWidth: 1.2)
                            )
                    )
                    .shadow(color: isKeyPressed ? accentColor.opacity(0.6) : .black.opacity(0.2), radius: isKeyPressed ? 8 : 2)
                    .offset(y: isKeyPressed ? 2 : 0)

                    // Touche Espace
                    VStack {
                        Text("espace")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                        Image(systemName: "space")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 74, height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isKeyPressed ? accentColor.opacity(0.35) : Color.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(isKeyPressed ? accentColor : Color.white.opacity(0.2), lineWidth: 1.2)
                            )
                    )
                    .shadow(color: isKeyPressed ? accentColor.opacity(0.6) : .black.opacity(0.2), radius: isKeyPressed ? 8 : 2)
                    .offset(y: isKeyPressed ? 2 : 0)
                }
                .frame(height: 86)

                HStack(spacing: 4) {
                    Image(systemName: "command")
                        .font(.system(size: 10))
                        .foregroundStyle(accentColor)
                    Text("Raccourci ⌃ Espace")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
        .onAppear {
            startAnimationLoop()
        }
    }

    private func startAnimationLoop() {
        Timer.scheduledTimer(withTimeInterval: 2.4, repeats: true) { _ in
            // Pincement des doigts
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                pinchProgress = 1.0
                isKeyPressed = true
            }

            // Onde de flou
            withAnimation(.easeOut(duration: 0.8)) {
                rippleScale = 1.8
                rippleOpacity = 0.8
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(.easeOut(duration: 0.5)) {
                    rippleOpacity = 0.0
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    pinchProgress = 0.0
                    rippleScale = 0.6
                    isKeyPressed = false
                }
            }
        }
    }
}

// MARK: - Étape 2 : Organisation & Création de Dossiers par Glisser-Déposer
private struct TutorialStageOrganize: View {
    let accentColor: Color

    @State private var dragOffset: CGFloat = 0.0
    @State private var isDragging = false
    @State private var isFolderFormed = false
    @State private var folderGlow = 0.0

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                // Zone de création de dossier avec flou dynamique
                HStack(spacing: 44) {
                    // Icône cible (Musique) qui reçoit l'application pour former un dossier
                    ZStack {
                        if isFolderFormed {
                            // Aspect dossier déplié en verre dépoli
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.12))
                                .frame(width: 58, height: 58)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(accentColor, lineWidth: 1.8)
                                )
                                .shadow(color: accentColor.opacity(0.55), radius: 12)
                                .transition(.scale.combined(with: .opacity))
                        }

                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(LinearGradient(colors: [Color.pink, Color.red], startPoint: .top, endPoint: .bottom))
                                .frame(width: isFolderFormed ? 26 : 42, height: isFolderFormed ? 26 : 42)
                                .overlay(
                                    Image(systemName: "music.note")
                                        .font(.system(size: isFolderFormed ? 12 : 18))
                                        .foregroundStyle(.white)
                                )
                                .offset(x: isFolderFormed ? -10 : 0, y: isFolderFormed ? -4 : 0)

                            if !isFolderFormed {
                                Text("Musique")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                        }
                    }

                    // Icône source déplacée (Safari)
                    VStack(spacing: 4) {
                        ZStack {
                            // Traînée floutée de mouvement lors du glissement
                            if isDragging {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(Color.cyan.opacity(0.35))
                                    .frame(width: 44, height: 44)
                                    .blur(radius: 8)
                            }

                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(LinearGradient(colors: [Color.cyan, Color.blue], startPoint: .top, endPoint: .bottom))
                                .frame(width: isFolderFormed ? 26 : 42, height: isFolderFormed ? 26 : 42)
                                .overlay(
                                    Image(systemName: "safari.fill")
                                        .font(.system(size: isFolderFormed ? 12 : 18))
                                        .foregroundStyle(.white)
                                )
                                .shadow(color: isDragging ? .black.opacity(0.4) : .clear, radius: 10, y: 6)
                                .scaleEffect(isDragging ? 1.15 : 1.0)
                        }

                        if !isFolderFormed {
                            Text("Safari")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                    .offset(x: dragOffset, y: isFolderFormed ? -4 : (isDragging ? -8 : 0))
                }

                // Curseur de souris simulé
                Image(systemName: "cursorarrow")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 4, y: 2)
                    .offset(x: dragOffset + 32, y: isDragging ? 12 : 24)
            }
            .frame(height: 84)

            // Légende explicative animée
            HStack(spacing: 6) {
                Image(systemName: isFolderFormed ? "folder.badge.plus" : "arrow.left.and.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(accentColor)
                Text(isFolderFormed ? "Dossier créé automatiquement !" : "Glissez une icône sur une autre pour créer un dossier")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(isFolderFormed ? accentColor : .white.opacity(0.85))
            }
        }
        .onAppear {
            startLoop()
        }
    }

    private func startLoop() {
        Timer.scheduledTimer(withTimeInterval: 3.8, repeats: true) { _ in
            // Étape 1 : Le curseur prend Safari
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                isDragging = true
            }

            // Étape 2 : Déplacement vers Musique
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.easeInOut(duration: 1.0)) {
                    dragOffset = -86
                }
            }

            // Étape 3 : Fusion en dossier
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.45) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    isFolderFormed = true
                    isDragging = false
                }
            }

            // Étape 4 : Reset
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
                withAnimation(.easeInOut(duration: 0.6)) {
                    dragOffset = 0.0
                    isFolderFormed = false
                }
            }
        }
    }
}

// MARK: - Étape 3 : Recherche Instantanée au Clavier
private struct TutorialStageSearch: View {
    let accentColor: Color

    @State private var typedText: String = ""
    @State private var cursorVisible = true
    @State private var targetHighlighted = false

    private let sampleIcons = [
        ("Notes", "note.text", Color.yellow),
        ("Safari", "safari.fill", Color.blue),
        ("Terminal", "terminal.fill", Color.black)
    ]

    var body: some View {
        VStack(spacing: 12) {
            // Barre de recherche miniature en verre dépoli
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accentColor)

                HStack(spacing: 0) {
                    Text(typedText.isEmpty ? "Rechercher une application..." : typedText)
                        .font(.system(size: 13, weight: typedText.isEmpty ? .regular : .semibold))
                        .foregroundStyle(typedText.isEmpty ? .white.opacity(0.35) : .white)

                    if !typedText.isEmpty && cursorVisible {
                        Rectangle()
                            .fill(accentColor)
                            .frame(width: 2, height: 14)
                            .padding(.leading, 1)
                    }
                }

                Spacer()

                if !typedText.isEmpty {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(typedText.isEmpty ? Color.white.opacity(0.12) : accentColor.opacity(0.8), lineWidth: 1)
                    )
            )
            .frame(maxWidth: 320)

            // Résultats : les non-correspondants se floutent, Safari s'illumine
            HStack(spacing: 24) {
                ForEach(sampleIcons, id: \.0) { item in
                    let isMatch = item.0.lowercased().contains(typedText.lowercased()) || typedText.isEmpty
                    let isExact = item.0.lowercased() == typedText.lowercased()

                    VStack(spacing: 4) {
                        ZStack {
                            if isExact {
                                // Halo de sélection
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(accentColor.opacity(0.45))
                                    .frame(width: 44, height: 44)
                                    .blur(radius: 8)
                            }

                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(item.2)
                                .frame(width: 38, height: 38)
                                .overlay(
                                    Image(systemName: item.1)
                                        .font(.system(size: 18))
                                        .foregroundStyle(.white)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(isExact ? Color.white : Color.clear, lineWidth: 1.5)
                                )
                                .scaleEffect(isExact ? 1.15 : 1.0)
                        }

                        Text(item.0)
                            .font(.system(size: 10, weight: isExact ? .bold : .medium))
                            .foregroundStyle(isExact ? .white : .white.opacity(0.7))
                    }
                    .opacity(isMatch ? 1.0 : 0.22)
                    .blur(radius: isMatch ? 0 : 4) // Floutage intuitif des apps exclues
                    .animation(.spring(response: 0.35, dampingFraction: 0.75), value: typedText)
                }
            }

            // Bouton de validation Entrée
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Text("↵")
                        .font(.system(size: 12, weight: .bold))
                    Text("Entrée")
                        .font(.system(size: 10.5, weight: .semibold))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(accentColor.opacity(0.3))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(accentColor, lineWidth: 1))
                .foregroundStyle(.white)

                Text("Ouvre instantanément le premier résultat")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .onAppear {
            startTypingLoop()
        }
    }

    private func startTypingLoop() {
        Timer.scheduledTimer(withTimeInterval: 3.5, repeats: true) { _ in
            let word = "Safari"
            typedText = ""
            for (index, char) in word.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.18 + 0.3) {
                    typedText.append(char)
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
                withAnimation(.easeOut(duration: 0.3)) {
                    typedText = ""
                }
            }
        }
    }
}

// MARK: - Étape 4 : Widgets & Thème Liquid Glass
private struct TutorialStageWidgets: View {
    let accentColor: Color

    @State private var vinylAngle: Double = 0
    @State private var sheenOffset: CGFloat = -180
    @State private var noteOffset: CGFloat = 0

    var body: some View {
        HStack(spacing: 24) {
            // Widget Vinyle rotatif avec ondes musicales
            HStack(spacing: 12) {
                ZStack {
                    // Disque vinyle avec sillons concentriques
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(white: 0.10), Color(white: 0.18), Color(white: 0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 74, height: 74)
                        .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                        .overlay(Circle().stroke(Color.white.opacity(0.06), lineWidth: 1).frame(width: 58, height: 58))
                        .overlay(Circle().stroke(Color.white.opacity(0.06), lineWidth: 1).frame(width: 44, height: 44))
                        .rotationEffect(.degrees(vinylAngle))

                    // Macaron central avec illustration
                    Circle()
                        .fill(LinearGradient(colors: [accentColor, .orange], startPoint: .top, endPoint: .bottom))
                        .frame(width: 26, height: 26)
                        .overlay(Image(systemName: "music.note").font(.system(size: 11)).foregroundStyle(.white))
                        .rotationEffect(.degrees(vinylAngle))

                    // Bras de lecture de la platine
                    Rectangle()
                        .fill(Color(white: 0.8))
                        .frame(width: 3, height: 36)
                        .rotationEffect(.degrees(24), anchor: .top)
                        .offset(x: 28, y: -16)

                    // Notes de musique flottantes avec flou
                    Image(systemName: "music.quarternote.3")
                        .font(.system(size: 14))
                        .foregroundStyle(accentColor)
                        .offset(x: 10, y: noteOffset)
                        .opacity(Double(1.0 - abs(noteOffset) / 30))
                        .blur(radius: abs(noteOffset) / 15)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Platine Vinyle")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Synchronisé Apple Music & Spotify")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(2)
                }
                .frame(maxWidth: 110, alignment: .leading)
            }

            // Séparateur vertical
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 1, height: 70)

            // Carte de style Liquid Glass avec reflet lumineux traversant
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 130, height: 76)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.4), Color.white.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )

                // Reflet lumineux qui balaie la carte
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.clear, Color.white.opacity(0.35), Color.clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 40, height: 90)
                    .rotationEffect(.degrees(25))
                    .offset(x: sheenOffset)
                    .blur(radius: 6)
                    .mask(RoundedRectangle(cornerRadius: 14, style: .continuous).frame(width: 130, height: 76))

                VStack(spacing: 3) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16))
                        .foregroundStyle(accentColor)
                    Text("Liquid Glass")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Verre dépoli & reflets")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 8.0).repeatForever(autoreverses: false)) {
                vinylAngle = 360
            }

            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: false)) {
                sheenOffset = 180
            }

            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                noteOffset = -24
            }
        }
    }
}

// MARK: - Carte Principale du Tutoriel

struct TutorialCardView: View {
    var vm: LaunchpadViewModel? = nil
    var initialStepIndex: Int = 0
    var onDismiss: (() -> Void)? = nil

    @State private var currentStepIndex: Int
    @State private var transitionBlur: CGFloat = 0.0
    @State private var transitionOpacity: Double = 1.0
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
        .frame(maxWidth: 630)
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
            .padding(.top, 20)

            // Corps principal de l'étape
            VStack(spacing: 12) {
                // Titre et description
                VStack(spacing: 4) {
                    Text(currentStep.title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text(currentStep.subtitle)
                        .font(.system(size: 12.5, weight: .regular))
                        .foregroundStyle(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .frame(maxWidth: 500)
                }
                .padding(.top, 4)

                // Scène visuelle animée avec flou intuitif
                TutorialStageView(stepIndex: currentStepIndex, accentColor: currentStep.iconColor)
                    .blur(radius: transitionBlur)
                    .opacity(transitionOpacity)
                    .padding(.horizontal, 20)
                    .padding(.top, 2)

                // Liste des fonctionnalités clés
                VStack(spacing: 8) {
                    ForEach(currentStep.features) { feature in
                        HStack(alignment: .center, spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.white.opacity(0.08))
                                    .frame(width: 28, height: 28)
                                Image(systemName: feature.icon)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(currentStep.iconColor)
                            }

                            VStack(alignment: .leading, spacing: 1) {
                                HStack {
                                    Text(feature.title)
                                        .font(.system(size: 12.5, weight: .semibold))
                                        .foregroundStyle(.white)
                                    if let tag = feature.tag {
                                        Text(tag)
                                            .font(.system(size: 9, weight: .bold))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(Color.white.opacity(0.12))
                                            .clipShape(Capsule())
                                            .foregroundStyle(.white.opacity(0.8))
                                    }
                                }
                                Text(feature.description)
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundStyle(.white.opacity(0.68))
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(0.035))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                                )
                        )
                    }
                }
                .padding(.horizontal, 20)
                .blur(radius: transitionBlur)
                .opacity(transitionOpacity)
            }
            .padding(.vertical, 10)

            Divider()
                .background(Color.white.opacity(0.10))
                .padding(.horizontal, 20)
                .padding(.top, 4)

            // Pied de carte : pagination et boutons
            HStack(alignment: .center) {
                // Indicateur de page (Dots)
                HStack(spacing: 6) {
                    ForEach(0..<steps.count, id: \.self) { idx in
                        Capsule()
                            .fill(idx == currentStepIndex ? currentStep.iconColor : Color.white.opacity(0.25))
                            .frame(width: idx == currentStepIndex ? 22 : 6, height: 6)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentStepIndex)
                            .onTapGesture {
                                changeStep(to: idx)
                            }
                    }
                }

                Spacer()

                HStack(spacing: 10) {
                    if currentStepIndex > 0 {
                        Button {
                            changeStep(to: currentStepIndex - 1)
                        } label: {
                            Text("Précédent")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(.white.opacity(0.85))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(Color.white.opacity(0.10))
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                    if currentStepIndex < steps.count - 1 {
                        Button {
                            changeStep(to: currentStepIndex + 1)
                        } label: {
                            HStack(spacing: 5) {
                                Text("Suivant")
                                    .font(.system(size: 12.5, weight: .semibold))
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
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
                                    .font(.system(size: 12.5, weight: .bold))
                            }
                            .foregroundStyle(.black)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .shadow(color: .white.opacity(0.3), radius: 10, y: 3)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.32), Color.white.opacity(0.06), Color.white.opacity(0.14)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.2
                        )
                )
                .shadow(color: .black.opacity(0.55), radius: 36, y: 16)
        }
    }

    private func changeStep(to newIndex: Int) {
        guard newIndex != currentStepIndex, newIndex >= 0, newIndex < steps.count else { return }

        // Transition cinématographique avec flou doux
        withAnimation(.easeOut(duration: 0.15)) {
            transitionBlur = 10
            transitionOpacity = 0.3
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            currentStepIndex = newIndex
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                transitionBlur = 0.0
                transitionOpacity = 1.0
            }
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

// MARK: - Visite Guidée Animée en Direct dans le Launchpad (Plein Écran & Spotlight)

struct LaunchpadLiveTutorialView: View {
    @ObservedObject var vm: LaunchpadViewModel
    var onDismiss: (() -> Void)? = nil

    @State private var currentStepIndex: Int = 0
    @State private var showDetailedCard: Bool = false
    @State private var transitionBlur: CGFloat = 0.0
    @State private var transitionOpacity: Double = 1.0

    private let steps: [TutorialStep] = [
        TutorialStep(
            id: 0,
            badge: "BIENVENUE",
            title: "Bienvenue dans LaunchPad",
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
            subtitle: "Pincez sur votre trackpad ou pressez ⌃ Espace pour ouvrir LaunchPad immédiatement.",
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
            title: "Organisation & Dossiers en direct",
            subtitle: "Glissez une application sur une autre pour créer un dossier instantanément.",
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
            subtitle: "Tapez directement le nom d'une application au clavier et appuyez sur Entrée.",
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
            subtitle: "Sublimez votre écran avec des widgets interactifs, vinyle et le thème Liquid Glass.",
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
        GeometryReader { geo in
            let currentStep = steps[currentStepIndex]

            ZStack {
                if showDetailedCard {
                    // Mode Fiche Détaillée
                    ZStack {
                        Color.black.opacity(0.45)
                            .ignoresSafeArea()
                            .onTapGesture {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    showDetailedCard = false
                                }
                            }

                        VStack(spacing: 12) {
                            HStack {
                                Button {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        showDetailedCard = false
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "arrow.left")
                                        Text("Reprendre la visite en direct dans LaunchPad")
                                            .fontWeight(.semibold)
                                    }
                                    .font(.system(size: 12.5))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Capsule())
                                    .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                                    .foregroundStyle(.white)
                                }
                                .buttonStyle(.plain)

                                Spacer()
                            }
                            .frame(maxWidth: 630)

                            TutorialCardView(vm: vm, initialStepIndex: currentStepIndex, onDismiss: onDismiss)
                        }
                    }
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
                } else {
                    // Mode Direct dans le Launchpad (Plein Écran avec animations fluides)
                    liveLaunchpadOverlay(geo: geo, currentStep: currentStep)
                        .transition(.opacity)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showDetailedCard)
        }
        .onExitCommand {
            dismiss()
        }
    }

    // MARK: - Démonstrations Directes dans le Launchpad
    @ViewBuilder
    private func liveLaunchpadOverlay(geo: GeometryProxy, currentStep: TutorialStep) -> some View {
        ZStack {
            // Voile semi-transparent doux qui laisse respirer le Launchpad
            Color.black.opacity(currentStepIndex == 3 ? 0.32 : 0.22)
                .ignoresSafeArea()

            // Orbes lumineuses d'ambiance avec flou
            Circle()
                .fill(currentStep.iconColor.opacity(0.22))
                .frame(width: 480, height: 480)
                .blur(radius: 120)
                .offset(x: -geo.size.width * 0.25, y: -geo.size.height * 0.15)
                .allowsHitTesting(false)

            Circle()
                .fill(currentStep.iconColor.opacity(0.18))
                .frame(width: 420, height: 420)
                .blur(radius: 110)
                .offset(x: geo.size.width * 0.25, y: geo.size.height * 0.15)
                .allowsHitTesting(false)

            // Scène d'animation en direct selon l'étape
            Group {
                switch currentStepIndex {
                case 0:
                    LiveStep0Overview(accentColor: currentStep.iconColor, screenSize: geo.size)
                case 1:
                    LiveStep1Triggers(accentColor: currentStep.iconColor, screenSize: geo.size)
                case 2:
                    LiveStep2Organize(accentColor: currentStep.iconColor, screenSize: geo.size)
                case 3:
                    LiveStep3Search(accentColor: currentStep.iconColor, screenSize: geo.size)
                case 4:
                    LiveStep4Widgets(accentColor: currentStep.iconColor, screenSize: geo.size)
                default:
                    EmptyView()
                }
            }
            .blur(radius: transitionBlur)
            .opacity(transitionOpacity)

            // Barre de Contrôle Flottante façon Dynamic Island en bas de l'écran
            VStack {
                Spacer()

                HStack(spacing: 16) {
                    // Bouton Précédent
                    if currentStepIndex > 0 {
                        Button {
                            changeStep(to: currentStepIndex - 1)
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 38, height: 38)
                                .background(Color.white.opacity(0.12))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }

                    // Encart central d'information & progression
                    VStack(spacing: 5) {
                        HStack(spacing: 8) {
                            HStack(spacing: 5) {
                                Circle().fill(currentStep.iconColor).frame(width: 7, height: 7)
                                Text("\(currentStepIndex + 1)/\(steps.count) • \(currentStep.badge)")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(currentStep.iconColor)
                                    .tracking(1.0)
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .background(currentStep.iconColor.opacity(0.18))
                            .clipShape(Capsule())

                            Text(currentStep.title)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                        }

                        Text(currentStep.subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.78))
                            .multilineTextAlignment(.center)
                            .lineLimit(1)

                        // Puces de pagination interactives
                        HStack(spacing: 6) {
                            ForEach(0..<steps.count, id: \.self) { idx in
                                Capsule()
                                    .fill(idx == currentStepIndex ? currentStep.iconColor : Color.white.opacity(0.3))
                                    .frame(width: idx == currentStepIndex ? 22 : 6, height: 5)
                                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentStepIndex)
                                    .onTapGesture {
                                        changeStep(to: idx)
                                    }
                            }
                        }
                        .padding(.top, 2)
                    }
                    .frame(minWidth: 320)

                    // Bouton Suivant / Terminer
                    if currentStepIndex < steps.count - 1 {
                        Button {
                            changeStep(to: currentStepIndex + 1)
                        } label: {
                            HStack(spacing: 6) {
                                Text("Suivant")
                                    .font(.system(size: 13, weight: .bold))
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(
                                LinearGradient(
                                    colors: [currentStep.iconColor, currentStep.iconColor.opacity(0.85)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                                Text("Terminer")
                                    .font(.system(size: 13, weight: .bold))
                            }
                            .foregroundStyle(.black)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .shadow(color: .white.opacity(0.3), radius: 8, y: 3)
                        }
                        .buttonStyle(.plain)
                    }

                    // Bouton bascule vers Fiche complète
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            showDetailedCard = true
                        }
                    } label: {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.8))
                            .frame(width: 34, height: 34)
                            .background(Color.white.opacity(0.10))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Afficher la fiche détaillée complète")

                    // Bouton Fermer
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 34, height: 34)
                            .background(Color.white.opacity(0.10))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Fermer le tutoriel")
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.40), Color.white.opacity(0.08), Color.white.opacity(0.20)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.2
                                )
                        )
                        .shadow(color: .black.opacity(0.55), radius: 30, y: 12)
                )
                .padding(.bottom, 34)
            }
        }
    }

    private func changeStep(to newIndex: Int) {
        guard newIndex != currentStepIndex, newIndex >= 0, newIndex < steps.count else { return }

        withAnimation(.easeOut(duration: 0.16)) {
            transitionBlur = 12
            transitionOpacity = 0.2
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            currentStepIndex = newIndex
            withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) {
                transitionBlur = 0.0
                transitionOpacity = 1.0
            }
        }
    }

    private func dismiss() {
        Prefs.defaults.set(true, forKey: PrefKey.hasLaunchedBefore)
        if let onDismiss {
            onDismiss()
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                vm.showTutorial = false
            }
        }
    }
}

// MARK: - Étape 0 En Direct : Onde lumineuse fluide & Accueil
private struct LiveStep0Overview: View {
    let accentColor: Color
    let screenSize: CGSize

    @State private var wavePosition: CGFloat = -400
    @State private var haloPulse = false

    var body: some View {
        ZStack {
            // Onde lumineuse balayant doucement le Launchpad
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.clear, accentColor.opacity(0.25), Color.white.opacity(0.20), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 250, height: screenSize.height * 1.5)
                .rotationEffect(.degrees(30))
                .offset(x: wavePosition)
                .blur(radius: 35)

            // Carte d'accueil centrale moderne en verre dépoli
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(haloPulse ? 0.45 : 0.20))
                        .frame(width: 80, height: 80)
                        .blur(radius: haloPulse ? 20 : 10)

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [accentColor, accentColor.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 64, height: 64)
                        .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 1.5))
                        .shadow(color: accentColor.opacity(0.6), radius: 14)

                    Image(systemName: "sparkles")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(spacing: 6) {
                    Text("Bienvenue sur LaunchPad")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.4), radius: 6)

                    Text("Votre bureau macOS réinventé avec une fluidité native exceptionnelle à 120 FPS.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 480)
                }

                HStack(spacing: 12) {
                    Label("Ultra-rapide", systemImage: "bolt.fill")
                    Text("•").foregroundStyle(.white.opacity(0.4))
                    Label("Personnalisable", systemImage: "slider.horizontal.3")
                    Text("•").foregroundStyle(.white.opacity(0.4))
                    Label("Widgets en direct", systemImage: "square.stack.3d.up.fill")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accentColor)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.35), Color.white.opacity(0.08)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.2
                            )
                    )
                    .shadow(color: .black.opacity(0.45), radius: 26, y: 10)
            )
            .offset(y: -40)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 4.0).repeatForever(autoreverses: false)) {
                wavePosition = screenSize.width + 400
            }
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                haloPulse = true
            }
        }
    }
}

// MARK: - Étape 1 En Direct : Gestes Trackpad & Clavier
private struct LiveStep1Triggers: View {
    let accentColor: Color
    let screenSize: CGSize

    @State private var pinchProgress: CGFloat = 0.0
    @State private var rippleScale: CGFloat = 0.8
    @State private var rippleOpacity: Double = 0.0
    @State private var isKeyPressed = false

    var body: some View {
        ZStack {
            // Onde de choc circulaire se propageant sur le Launchpad
            Circle()
                .stroke(accentColor.opacity(0.7), lineWidth: 3)
                .frame(width: 140, height: 140)
                .scaleEffect(rippleScale)
                .opacity(rippleOpacity)
                .blur(radius: 3)
                .offset(y: -40)

            HStack(spacing: 36) {
                // Démonstration Trackpad en grand format
                VStack(spacing: 12) {
                    ZStack {
                        // Surface du Trackpad
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .frame(width: 190, height: 130)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(
                                        LinearGradient(
                                            colors: [Color.white.opacity(0.4), Color.white.opacity(0.1)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1.2
                                    )
                            )
                            .shadow(color: .black.opacity(0.35), radius: 16, y: 6)

                        // 4 doigts qui se pincent vers le centre
                        let radius: CGFloat = 44 * (1.0 - pinchProgress * 0.75)
                        let angles: [Double] = [45, 135, 225, 315]

                        ForEach(0..<4, id: \.self) { i in
                            let rad = angles[i] * .pi / 180
                            Circle()
                                .fill(Color.white)
                                .frame(width: 15, height: 15)
                                .shadow(color: accentColor, radius: 8)
                                .offset(
                                    x: cos(rad) * radius,
                                    y: sin(rad) * radius
                                )
                        }

                        // Logo LaunchPad apparaissant au centre lors du pincement
                        Image(systemName: "square.grid.3x3.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(accentColor)
                            .scaleEffect(pinchProgress > 0.5 ? 1.0 : 0.0)
                            .opacity(Double(pinchProgress))
                            .blur(radius: (1.0 - pinchProgress) * 6)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "hand.draw.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(accentColor)
                        Text("Pincement Trackpad à 3 ou 4 doigts")
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                }

                // Démonstration Touches Clavier
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        // Touche Control
                        VStack(spacing: 2) {
                            Text("control")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.white.opacity(0.65))
                            Text("⌃")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 68, height: 74)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(isKeyPressed ? accentColor.opacity(0.4) : Color.white.opacity(0.10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(isKeyPressed ? accentColor : Color.white.opacity(0.25), lineWidth: 1.5)
                                )
                        )
                        .shadow(color: isKeyPressed ? accentColor.opacity(0.6) : .black.opacity(0.25), radius: isKeyPressed ? 12 : 4)
                        .offset(y: isKeyPressed ? 4 : 0)

                        // Touche Espace
                        VStack(spacing: 2) {
                            Text("espace")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.white.opacity(0.65))
                            Image(systemName: "space")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 104, height: 74)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(isKeyPressed ? accentColor.opacity(0.4) : Color.white.opacity(0.10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(isKeyPressed ? accentColor : Color.white.opacity(0.25), lineWidth: 1.5)
                                )
                        )
                        .shadow(color: isKeyPressed ? accentColor.opacity(0.6) : .black.opacity(0.25), radius: isKeyPressed ? 12 : 4)
                        .offset(y: isKeyPressed ? 4 : 0)
                    }
                    .frame(height: 130)

                    HStack(spacing: 6) {
                        Image(systemName: "keyboard.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(accentColor)
                        Text("Raccourci Clavier ⌃ Espace")
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                }
            }
            .offset(y: -40)

            // Badges discrets aux 4 coins pour les coins actifs
            VStack {
                HStack {
                    hotCornerBadge(label: "Coin Actif", corner: "↖")
                    Spacer()
                    hotCornerBadge(label: "Coin Actif", corner: "↗")
                }
                Spacer()
                HStack {
                    hotCornerBadge(label: "Coin Actif", corner: "↙")
                    Spacer()
                    hotCornerBadge(label: "Coin Actif", corner: "↘")
                }
                .padding(.bottom, 120)
            }
            .padding(24)
        }
        .onAppear {
            startLoop()
        }
    }

    private func hotCornerBadge(label: String, corner: String) -> some View {
        HStack(spacing: 4) {
            Text(corner).font(.system(size: 13, weight: .bold)).foregroundStyle(accentColor)
            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
    }

    private func startLoop() {
        Timer.scheduledTimer(withTimeInterval: 2.6, repeats: true) { _ in
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                pinchProgress = 1.0
                isKeyPressed = true
            }

            withAnimation(.easeOut(duration: 1.0)) {
                rippleScale = 2.6
                rippleOpacity = 0.85
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation(.easeOut(duration: 0.5)) {
                    rippleOpacity = 0.0
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    pinchProgress = 0.0
                    rippleScale = 0.8
                    isKeyPressed = false
                }
            }
        }
    }
}

// MARK: - Étape 2 En Direct : Glisser-Déposer & Création de dossiers
private struct LiveStep2Organize: View {
    let accentColor: Color
    let screenSize: CGSize

    @State private var dragOffset: CGFloat = 0.0
    @State private var isDragging = false
    @State private var isFolderFormed = false

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                // Démonstration visuelle au format réel
                HStack(spacing: 64) {
                    // Application cible (Musique) qui reçoit pour former un dossier
                    ZStack {
                        if isFolderFormed {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(Color.white.opacity(0.16))
                                .frame(width: 88, height: 88)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                                        .stroke(accentColor, lineWidth: 2)
                                )
                                .shadow(color: accentColor.opacity(0.6), radius: 18)
                                .transition(.scale.combined(with: .opacity))
                        }

                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(LinearGradient(colors: [Color.pink, Color.red], startPoint: .top, endPoint: .bottom))
                                .frame(width: isFolderFormed ? 38 : 68, height: isFolderFormed ? 38 : 68)
                                .overlay(
                                    Image(systemName: "music.note")
                                        .font(.system(size: isFolderFormed ? 18 : 30))
                                        .foregroundStyle(.white)
                                )
                                .offset(x: isFolderFormed ? -16 : 0, y: isFolderFormed ? -8 : 0)

                            if !isFolderFormed {
                                Text("Musique")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.white)
                            }
                        }
                    }

                    // Application déplacée (Safari)
                    VStack(spacing: 6) {
                        ZStack {
                            if isDragging {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color.cyan.opacity(0.4))
                                    .frame(width: 76, height: 76)
                                    .blur(radius: 12)
                            }

                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(LinearGradient(colors: [Color.cyan, Color.blue], startPoint: .top, endPoint: .bottom))
                                .frame(width: isFolderFormed ? 38 : 68, height: isFolderFormed ? 38 : 68)
                                .overlay(
                                    Image(systemName: "safari.fill")
                                        .font(.system(size: isFolderFormed ? 18 : 30))
                                        .foregroundStyle(.white)
                                )
                                .shadow(color: isDragging ? .black.opacity(0.5) : .clear, radius: 16, y: 10)
                                .scaleEffect(isDragging ? 1.2 : 1.0)
                        }

                        if !isFolderFormed {
                            Text("Safari")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white)
                        }
                    }
                    .offset(x: dragOffset, y: isFolderFormed ? -8 : (isDragging ? -14 : 0))
                }

                // Curseur de souris animé
                Image(systemName: "cursorarrow")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.7), radius: 6, y: 3)
                    .offset(x: dragOffset + 48, y: isDragging ? 16 : 36)
            }
            .frame(height: 120)

            // Info-bulle flottante avec flèche
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: isFolderFormed ? "folder.badge.plus" : "hand.tap.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(accentColor)
                    Text(isFolderFormed ? "Dossier créé automatiquement !" : "Glissez une icône sur une autre pour créer un dossier")
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(isFolderFormed ? accentColor : .white)
                }
                Text("Vous pouvez réorganiser toutes vos applications librement par simple glisser-déposer.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        }
        .offset(y: -40)
        .onAppear {
            startLoop()
        }
    }

    private func startLoop() {
        Timer.scheduledTimer(withTimeInterval: 3.8, repeats: true) { _ in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                isDragging = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.easeInOut(duration: 1.1)) {
                    dragOffset = -132
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.55) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    isFolderFormed = true
                    isDragging = false
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                withAnimation(.easeInOut(duration: 0.6)) {
                    dragOffset = 0.0
                    isFolderFormed = false
                }
            }
        }
    }
}

// MARK: - Étape 3 En Direct : Spotlight sur la Barre de Recherche & Filtre Dynamique
private struct LiveStep3Search: View {
    let accentColor: Color
    let screenSize: CGSize

    @State private var typedText: String = ""
    @State private var cursorVisible = true

    private let sampleApps = [
        ("Notes", "note.text", Color.yellow),
        ("Safari", "safari.fill", Color.blue),
        ("Xcode", "hammer.fill", Color.cyan),
        ("Photos", "photo.stack.fill", Color.pink)
    ]

    var body: some View {
        ZStack {
            // Projecteur lumineux (Spotlight) centré directement sur la vraie barre de recherche en haut
            VStack {
                ZStack {
                    // Halo de lumière diffuse sur la barre de recherche du Launchpad
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(accentColor.opacity(0.35))
                        .frame(width: 360, height: 50)
                        .blur(radius: 16)

                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(accentColor, lineWidth: 2)
                        .frame(width: 340, height: 44)
                        .shadow(color: accentColor.opacity(0.8), radius: 12)

                    // Bulle d'annotation dynamique pointant vers la barre de recherche
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(accentColor)
                        HStack(spacing: 0) {
                            Text(typedText.isEmpty ? "Recherche au clavier..." : typedText)
                                .font(.system(size: 14, weight: typedText.isEmpty ? .regular : .bold))
                                .foregroundStyle(typedText.isEmpty ? .white.opacity(0.4) : .white)
                            if cursorVisible {
                                Rectangle().fill(accentColor).frame(width: 2, height: 16).padding(.leading, 2)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .frame(width: 330)
                }
                .padding(.top, 44)

                Spacer()
            }

            // Démonstration sur les applications : le filtre en action
            VStack(spacing: 16) {
                Text("Tapez simplement au clavier à n'importe quel moment")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)

                HStack(spacing: 32) {
                    ForEach(sampleApps, id: \.0) { item in
                        let isExact = item.0.lowercased() == typedText.lowercased()
                        let isMatch = item.0.lowercased().contains(typedText.lowercased()) || typedText.isEmpty

                        VStack(spacing: 6) {
                            ZStack {
                                if isExact {
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(accentColor.opacity(0.55))
                                        .frame(width: 78, height: 78)
                                        .blur(radius: 12)
                                }

                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(item.2)
                                    .frame(width: 64, height: 64)
                                    .overlay(
                                        Image(systemName: item.1)
                                            .font(.system(size: 28))
                                            .foregroundStyle(.white)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(isExact ? Color.white : Color.clear, lineWidth: 2)
                                    )
                                    .scaleEffect(isExact ? 1.18 : 1.0)
                            }

                            Text(item.0)
                                .font(.system(size: 12, weight: isExact ? .bold : .medium))
                                .foregroundStyle(isExact ? .white : .white.opacity(0.7))
                        }
                        .opacity(isMatch ? 1.0 : 0.20)
                        .blur(radius: isMatch ? 0 : 5)
                        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: typedText)
                    }
                }

                // Touche Entrée clignotante
                HStack(spacing: 8) {
                    HStack(spacing: 5) {
                        Text("↵")
                            .font(.system(size: 14, weight: .bold))
                        Text("Entrée")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(accentColor)
                    .clipShape(Capsule())
                    .foregroundStyle(.white)
                    .shadow(color: accentColor.opacity(0.5), radius: 8)

                    Text("Appuyez sur Entrée pour ouvrir immédiatement !")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(.top, 6)
            }
            .offset(y: 20)
        }
        .onAppear {
            startTypingLoop()
        }
    }

    private func startTypingLoop() {
        Timer.scheduledTimer(withTimeInterval: 3.6, repeats: true) { _ in
            let word = "Safari"
            typedText = ""
            for (index, char) in word.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.18 + 0.3) {
                    typedText.append(char)
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation(.easeOut(duration: 0.3)) {
                    typedText = ""
                }
            }
        }
    }
}

// MARK: - Étape 4 En Direct : Widgets & Effets Liquid Glass
private struct LiveStep4Widgets: View {
    let accentColor: Color
    let screenSize: CGSize

    @State private var vinylAngle: Double = 0
    @State private var sheenOffset: CGFloat = -260
    @State private var noteOffset: CGFloat = 0

    var body: some View {
        HStack(spacing: 36) {
            // Widget Platine Vinyle en grand format
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(white: 0.10), Color(white: 0.18), Color(white: 0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)
                        .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
                        .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1).frame(width: 80, height: 80))
                        .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1).frame(width: 60, height: 60))
                        .rotationEffect(.degrees(vinylAngle))

                    Circle()
                        .fill(LinearGradient(colors: [accentColor, .orange], startPoint: .top, endPoint: .bottom))
                        .frame(width: 36, height: 36)
                        .overlay(Image(systemName: "music.note").font(.system(size: 15)).foregroundStyle(.white))
                        .rotationEffect(.degrees(vinylAngle))

                    Rectangle()
                        .fill(Color(white: 0.85))
                        .frame(width: 3.5, height: 48)
                        .rotationEffect(.degrees(24), anchor: .top)
                        .offset(x: 38, y: -22)

                    Image(systemName: "music.quarternote.3")
                        .font(.system(size: 18))
                        .foregroundStyle(accentColor)
                        .offset(x: 16, y: noteOffset)
                        .opacity(Double(1.0 - abs(noteOffset) / 40))
                        .blur(radius: abs(noteOffset) / 18)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Widget Platine Vinyle")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Contrôlez votre musique en direct avec rotation dynamique.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(maxWidth: 160)
                }
            }
            .padding(18)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )

            // Carte de style Liquid Glass
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.07))
                    .frame(width: 220, height: 115)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.5), Color.white.opacity(0.08)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.2
                            )
                    )

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.clear, Color.white.opacity(0.4), Color.clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 55, height: 130)
                    .rotationEffect(.degrees(25))
                    .offset(x: sheenOffset)
                    .blur(radius: 8)
                    .mask(RoundedRectangle(cornerRadius: 20, style: .continuous).frame(width: 220, height: 115))

                VStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 22))
                        .foregroundStyle(accentColor)
                    Text("Thème Liquid Glass")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Reflets lumineux & verre dépoli")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
        }
        .offset(y: -40)
        .onAppear {
            withAnimation(.linear(duration: 8.0).repeatForever(autoreverses: false)) {
                vinylAngle = 360
            }
            withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: false)) {
                sheenOffset = 260
            }
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                noteOffset = -32
            }
        }
    }
}

// MARK: - Modal immersif intégré au Launchpad avec effet de flou en arrière-plan

struct TutorialModalView: View {
    @ObservedObject var vm: LaunchpadViewModel

    var body: some View {
        LaunchpadLiveTutorialView(vm: vm) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                vm.showTutorial = false
            }
        }
        .zIndex(100)
    }
}
