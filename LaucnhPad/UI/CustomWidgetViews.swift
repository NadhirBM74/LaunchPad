import SwiftUI
import Combine
import AppKit

// MARK: - 1. Conteneur Visuel Liquid Glass (Harmonisé avec LaunchOS)

struct WidgetContainerView<Content: View>: View {
    let size: WidgetSize
    var targetSize: CGSize? = nil
    var isPureTranslucent: Bool = false
    @ViewBuilder let content: () -> Content

    @ObservedObject private var widgetManager = WidgetManager.shared
    @AppStorage(PrefKey.backgroundStyle) private var backgroundStyle = AppTheme.liquidGlass
    @AppStorage(PrefKey.liquidGlassIntensity) private var liquidGlassIntensity = 0.85

    var body: some View {
        let w = targetSize?.width ?? size.width
        let h = targetSize?.height ?? size.height
        let cornerRadius = widgetManager.cornerRadius

        content()
            .frame(width: w, height: h)
            .background(isPureTranslucent ? AnyView(translucentGlassBackground(cornerRadius: cornerRadius)) : AnyView(glassBackground(cornerRadius: cornerRadius)))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(isPureTranslucent ? AnyView(EmptyView()) : AnyView(luminousBorder(cornerRadius: cornerRadius)))
            .shadow(color: .black.opacity(isPureTranslucent ? 0.24 : 0.38), radius: isPureTranslucent ? 12 : 14, x: 0, y: isPureTranslucent ? 6 : 7)
    }

    @ViewBuilder
    private func translucentGlassBackground(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .liquidGlass(
                in: shape,
                interactive: false,
                tint: nil,
                prominence: .regular,
                intensity: liquidGlassIntensity
            )
            .overlay {
                if widgetManager.glowColor != .none {
                    shape.fill(widgetManager.glowColor.primaryColor.opacity(0.06))
                }
            }
    }

    @ViewBuilder
    private func glassBackground(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if backgroundStyle == .liquidGlass {
            shape
                .liquidGlass(
                    in: shape,
                    interactive: false,
                    tint: nil
                )
                .overlay {
                    if widgetManager.glowColor != .none {
                        shape.fill(widgetManager.glowColor.primaryColor.opacity(0.06))
                    }
                }
                .overlay {
                    if widgetManager.glassOpacity > 0.05 {
                        shape.fill(Color.black.opacity(widgetManager.glassOpacity * 0.45))
                    }
                }
        } else {
            shape
                .fill(.ultraThinMaterial)
                .overlay(
                    shape.fill(Color.black.opacity(widgetManager.glassOpacity * 0.74))
                )
                .overlay {
                    if widgetManager.glowColor != .none {
                        shape.fill(widgetManager.glowColor.primaryColor.opacity(0.06))
                    }
                }
                .overlay(
                    shape.fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.20),
                                Color.white.opacity(0.04),
                                Color(red: 0.08, green: 0.09, blue: 0.14).opacity(0.24)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                )
        }
    }

    @ViewBuilder
    private func luminousBorder(cornerRadius: CGFloat) -> some View {
        let glow = widgetManager.glowColor.primaryColor
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if backgroundStyle != .liquidGlass || widgetManager.glowColor != .none {
            shape
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            widgetManager.glowColor == .none ? Color.white.opacity(0.55) : glow.opacity(0.70),
                            Color.white.opacity(0.35),
                            widgetManager.glowColor == .none ? Color.white.opacity(0.12) : glow.opacity(0.25),
                            Color.white.opacity(0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.0
                )
        }
    }
}

// MARK: - 2. Composants Partagés Modernes

/// Barre de progression interactive : un clic ou un glissement déplace la lecture.
struct SeekBar: View {
    let elapsed: Double
    let duration: Double
    var trackColor: Color = Color.white.opacity(0.2)
    var fillColor: Color = .white
    var barHeight: CGFloat = 3
    var isEnabled: Bool = true
    let onSeek: (Double) -> Void

    @State private var dragFraction: Double? = nil
    @State private var isHovering = false

    private var canSeek: Bool { isEnabled && duration > 0 }

    var body: some View {
        GeometryReader { geo in
            let live = elapsed / max(1.0, duration)
            let fraction = min(1.0, max(0.0, dragFraction ?? live))
            let thickness = (dragFraction != nil || (isHovering && canSeek)) ? barHeight + 2 : barHeight
            ZStack(alignment: .leading) {
                Capsule().fill(trackColor)
                    .frame(height: thickness)
                Capsule().fill(fillColor)
                    .frame(width: max(thickness, geo.size.width * CGFloat(fraction)), height: thickness)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.12), value: thickness)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard canSeek else { return }
                        dragFraction = min(1.0, max(0.0, Double(value.location.x / max(1, geo.size.width))))
                    }
                    .onEnded { value in
                        guard canSeek else { dragFraction = nil; return }
                        let f = min(1.0, max(0.0, Double(value.location.x / max(1, geo.size.width))))
                        onSeek(f)
                        // Garde la position visée jusqu'au prochain rafraîchissement du lecteur.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { dragFraction = nil }
                    }
            )
            .onHover { isHovering = $0 }
        }
        .frame(height: max(18, barHeight + 12))
    }
}


// MARK: - Bouton de contrôle média réutilisable (zone de clic généreuse + retour visuel)

/// Bouton de transport utilisé par les widgets musicaux. Il offre une zone de clic
/// confortable (au moins 28×28 pt), un curseur main et un retour visuel au survol
/// et à l'enfoncement, pour que le widget se comporte comme un vrai lecteur.
struct MediaControlButton: View {
    let systemName: String
    var iconSize: CGFloat = 13
    var frameSize: CGFloat = 30
    var isPrimary: Bool = false
    var help: String? = nil
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: isPrimary ? .bold : .semibold))
                .foregroundStyle(.white.opacity(hovering ? 1.0 : (isPrimary ? 1.0 : 0.85)))
                .frame(width: frameSize, height: frameSize)
                .background {
                    if isPrimary {
                        Circle()
                            .fill(Color.white.opacity(hovering ? 0.30 : 0.20))
                            .overlay(
                                Circle().strokeBorder(
                                    Color.white.opacity(hovering ? 0.60 : 0.35),
                                    lineWidth: 0.8
                                )
                            )
                    } else {
                        Circle()
                            .fill(Color.white.opacity(hovering ? 0.16 : 0.001))
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(MediaPressButtonStyle())
        .onHover { inside in
            if inside {
                if !hovering { NSCursor.pointingHand.push() }
                hovering = true
            } else {
                if hovering { NSCursor.pop() }
                hovering = false
            }
        }
        .onDisappear {
            if hovering { NSCursor.pop(); hovering = false }
        }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(help ?? "")
        .accessibilityLabel(help ?? systemName)
    }
}

/// Léger enfoncement du bouton pour un retour tactile immédiat.
private struct MediaPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .brightness(configuration.isPressed ? 0.12 : 0)
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
    }
}

struct MiniEqualizerBars: View {
    let isPlaying: Bool
    var color: Color = .white
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage(PrefKey.reduceMotion) private var userReduceMotion = false
    @State private var barHeights: [CGFloat] = [0.35, 0.65, 0.95, 0.45, 0.8]

    private var reduceMotion: Bool { userReduceMotion || systemReduceMotion }

    var body: some View {
        HStack(spacing: 2.2) {
            ForEach(0..<barHeights.count, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.2)
                    .fill(color)
                    .frame(width: 2.5, height: max(3.5, 13 * (isPlaying ? barHeights[i] : 0.28)))
                    .animation(
                        isPlaying && !reduceMotion
                            ? .easeInOut(duration: 0.30 + Double(i) * 0.07).repeatForever(autoreverses: true)
                            : .easeOut(duration: 0.25),
                        value: barHeights[i]
                    )
            }
        }
        .frame(height: 14)
        .onAppear {
            if isPlaying && !reduceMotion {
                barHeights = [0.9, 0.35, 0.85, 0.45, 0.75]
            }
        }
        .onChange(of: isPlaying) { _, playing in
            if playing && !reduceMotion {
                barHeights = [0.9, 0.35, 0.85, 0.45, 0.75]
            } else {
                barHeights = [0.35, 0.65, 0.95, 0.45, 0.8]
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .launchpadVisibilityDidChange)) { notif in
            let isVisible = (notif.object as? Bool) ?? false
            if !isVisible {
                barHeights = [0.35, 0.65, 0.95, 0.45, 0.8]
            } else if isPlaying && !reduceMotion {
                barHeights = [0.9, 0.35, 0.85, 0.45, 0.75]
            }
        }
    }
}

struct CircularRingGauge: View {
    let progress: Double
    let gradient: LinearGradient
    let icon: String
    let value: String
    let label: String
    var size: CGFloat = 66

    var body: some View {
        let strokeW = max(2.5, size * 0.075)
        let iconSize = max(7.5, size * 0.17)
        let valueSize = max(8.0, size * 0.19)
        let labelSize = max(7.0, size * 0.15)
        let innerSpacing = max(0.5, size * 0.015)
        let outerSpacing = max(2.0, size * 0.075)

        VStack(spacing: outerSpacing) {
            ZStack {
                // Anneau de fond
                Circle()
                    .stroke(Color.white.opacity(0.10), lineWidth: strokeW)

                // Anneau de progression
                Circle()
                    .trim(from: 0.0, to: CGFloat(min(1.0, max(0.03, progress))))
                    .stroke(gradient, style: StrokeStyle(lineWidth: strokeW, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.45, dampingFraction: 0.8), value: progress)

                // Contenu central
                VStack(spacing: innerSpacing) {
                    Image(systemName: icon)
                        .font(.system(size: iconSize, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                    Text(value)
                        .font(.system(size: valueSize, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }
            }
            .frame(width: size, height: size)

            Text(label)
                .font(.system(size: labelSize, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(1)
        }
    }
}

// Cadran analogique vectoriel optimisé avec Metal drawingGroup
struct ClockDialFace: View, Equatable {
    let size: CGFloat

    var body: some View {
        ZStack {
            // Cadran en verre ultra-fin
            Circle()
                .fill(Color.white.opacity(0.06))
                .overlay(
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.35), Color.white.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )

            // Graduations des heures pré-calculées
            ForEach(0..<12) { i in
                Rectangle()
                    .fill(i % 3 == 0 ? Color.white.opacity(0.85) : Color.white.opacity(0.35))
                    .frame(width: i % 3 == 0 ? 2 : 1, height: i % 3 == 0 ? 6.5 : 4)
                    .offset(y: -size / 2 + 7)
                    .rotationEffect(.degrees(Double(i) * 30))
            }
        }
        .frame(width: size, height: size)
        .drawingGroup()
    }
}

struct AnalogClockFace: View {
    let date: Date
    var size: CGFloat = 110

    var body: some View {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date) % 12
        let minute = calendar.component(.minute, from: date)
        let second = calendar.component(.second, from: date)

        let hourAngle = Double(hour) * 30.0 + Double(minute) * 0.5
        let minuteAngle = Double(minute) * 6.0 + Double(second) * 0.1
        let secondAngle = Double(second) * 6.0

        ZStack {
            ClockDialFace(size: size)

            // Aiguille des heures
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white)
                .frame(width: 3.5, height: size * 0.28)
                .offset(y: -size * 0.14)
                .rotationEffect(.degrees(hourAngle))
                .shadow(color: .black.opacity(0.4), radius: 2, y: 1)

            // Aiguille des minutes
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.white.opacity(0.92))
                .frame(width: 2.5, height: size * 0.38)
                .offset(y: -size * 0.19)
                .rotationEffect(.degrees(minuteAngle))
                .shadow(color: .black.opacity(0.4), radius: 2, y: 1)

            // Aiguille des secondes orange Apple
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.orange)
                .frame(width: 1.5, height: size * 0.44)
                .offset(y: -size * 0.18)
                .rotationEffect(.degrees(secondAngle))

            // Pivot central
            Circle()
                .fill(Color.orange)
                .frame(width: 5, height: 5)
            Circle()
                .fill(Color.black)
                .frame(width: 2, height: 2)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 3. Widget Lecteur Vinyle (Inspiré de la Référence : Vinyle Flottant + Carte Adaptative Clair/Sombre)

/// Piste de démonstration utilisée lorsqu'aucun lecteur externe n'est actif,
/// permettant d'apprécier immédiatement le changement de pochette vinyle, la rotation
/// et le changement de couleur de la barre de lecture comme sur l'animation de référence.
private struct VinylDemoTrack {
    let title: String
    let artist: String
    let accentColor: Color
    let palette: [Color]
}

/// Bouton de transport épuré pour le lecteur vinyle (avec anneau circulaire au survol/clic comme sur la référence)
private struct VinylTransportButton: View {
    let systemName: String
    let iconSize: CGFloat
    let frameSize: CGFloat
    let foregroundColor: Color
    let ringColor: Color
    var showPersistentRing: Bool = false
    var help: String? = nil
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(
                        ringColor.opacity(hovering || showPersistentRing ? 1.0 : 0.0),
                        lineWidth: 1.3
                    )
                    .background(
                        Circle().fill(ringColor.opacity(hovering ? 0.16 : 0.001))
                    )
                    .frame(width: frameSize, height: frameSize)

                Image(systemName: systemName)
                    .font(.system(size: iconSize, weight: .bold))
                    .foregroundStyle(foregroundColor.opacity(hovering ? 1.0 : 0.90))
            }
            .frame(width: frameSize, height: frameSize)
            .contentShape(Circle())
        }
        .buttonStyle(MediaPressButtonStyle())
        .onHover { inside in
            if inside {
                if !hovering { NSCursor.pointingHand.push() }
                hovering = true
            } else {
                if hovering { NSCursor.pop() }
                hovering = false
            }
        }
        .onDisappear {
            if hovering { NSCursor.pop(); hovering = false }
        }
        .animation(.easeOut(duration: 0.14), value: hovering)
        .animation(.easeOut(duration: 0.18), value: showPersistentRing)
        .help(help ?? "")
        .accessibilityLabel(help ?? systemName)
    }
}

struct VinylPlayerWidgetView: View {
    let config: CustomWidgetConfig
    var targetSize: CGSize? = nil
    @ObservedObject private var widgetManager = WidgetManager.shared
    @ObservedObject private var musicManager = MusicServiceManager.shared
    @AppStorage(PrefKey.backgroundStyle) private var backgroundStyle = AppTheme.liquidGlass
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage(PrefKey.reduceMotion) private var userReduceMotion = false

    // États d'animation du disque vinyle et du changement de piste
    @State private var discRotation: Double = 0
    @State private var discScale: CGFloat = 1.0
    @State private var tonearmBounceAngle: Double = 0
    @State private var transitionDirection: Int = 1 // +1 = suivant, -1 = précédent
    @State private var trackTransitionID: Int = 0
    @State private var demoTrackIndex: Int = 0
    @State private var lastManualSkipDate: Date = .distantPast
    @State private var activeRingButton: String? = nil
    @State private var extractedAccentColor: Color? = nil

    private var reduceMotion: Bool { userReduceMotion || systemReduceMotion }

    private static let demoTracks: [VinylDemoTrack] = [
        VinylDemoTrack(
            title: "Supercut",
            artist: "Lorde",
            accentColor: Color(red: 0.05, green: 0.31, blue: 0.85),
            palette: [
                Color(red: 0.04, green: 0.18, blue: 0.68),
                Color(red: 0.12, green: 0.44, blue: 0.96),
                Color(red: 0.95, green: 0.58, blue: 0.24),
                Color(red: 0.06, green: 0.10, blue: 0.34)
            ]
        ),
        VinylDemoTrack(
            title: "Redbone",
            artist: "Childish Gambino",
            accentColor: Color(red: 0.86, green: 0.16, blue: 0.18),
            palette: [
                Color(red: 0.48, green: 0.09, blue: 0.08),
                Color(red: 0.88, green: 0.24, blue: 0.22),
                Color(red: 0.94, green: 0.55, blue: 0.58),
                Color(red: 0.28, green: 0.06, blue: 0.06)
            ]
        ),
        VinylDemoTrack(
            title: "The Moment",
            artist: "Tame Impala",
            accentColor: Color(red: 0.44, green: 0.16, blue: 0.88),
            palette: [
                Color(red: 0.26, green: 0.18, blue: 0.36),
                Color(red: 0.48, green: 0.28, blue: 0.64),
                Color(red: 0.88, green: 0.16, blue: 0.24),
                Color(red: 0.18, green: 0.14, blue: 0.26)
            ]
        )
    ]

    private var currentDemo: VinylDemoTrack {
        let count = Self.demoTracks.count
        let idx = ((demoTrackIndex % count) + count) % count
        return Self.demoTracks[idx]
    }

    /// Adaptation automatique au thème de l'application (Clair vs Sombre)
    private var isLightTheme: Bool {
        backgroundStyle == .light
    }

    private var track: NowPlayingTrack {
        musicManager.currentTrack
    }

    private var displayTitle: String {
        if track.hasTrack { return track.title }
        if demoTrackIndex != 0 { return currentDemo.title }
        return config.musicTrack.isEmpty ? currentDemo.title : config.musicTrack
    }

    private var displayArtist: String {
        if track.hasTrack { return track.artist }
        if demoTrackIndex != 0 { return currentDemo.artist }
        return config.musicArtist.isEmpty ? currentDemo.artist : config.musicArtist
    }

    private var isPlaying: Bool {
        track.hasTrack ? track.isPlaying : config.musicIsPlaying
    }

    private var elapsed: Int {
        track.hasTrack ? Int(track.elapsedSeconds) : config.musicElapsedSeconds
    }

    private var duration: Int {
        track.hasTrack ? Int(track.durationSeconds) : config.musicTotalSeconds
    }

    // Couleurs adaptatives selon le thème (Clair = carte blanche / texte noir comme la référence ; Sombre = carte anthracite / texte blanc)
    private var primaryTextColor: Color {
        isLightTheme ? Color(white: 0.10) : Color.white
    }

    private var secondaryTextColor: Color {
        isLightTheme ? Color(white: 0.48) : Color.white.opacity(0.62)
    }

    private var muteIconColor: Color {
        isLightTheme ? Color(white: 0.62) : Color.white.opacity(0.48)
    }

    private var controlIconColor: Color {
        isLightTheme ? Color(white: 0.08) : Color.white.opacity(0.95)
    }

    private var controlRingColor: Color {
        isLightTheme ? Color.black.opacity(0.20) : Color.white.opacity(0.26)
    }

    private var seekTrackColor: Color {
        isLightTheme ? Color.black.opacity(0.11) : Color.white.opacity(0.16)
    }

    private var spindleHoleColor: Color {
        if isLightTheme {
            return Color(white: 0.98)
        } else if backgroundStyle == .dark {
            return Color(red: 0.12, green: 0.12, blue: 0.14)
        } else {
            return Color(red: 0.11, green: 0.12, blue: 0.16)
        }
    }

    private var activeProgressColor: Color {
        if let extracted = extractedAccentColor, track.hasTrack {
            return extracted
        }
        return currentDemo.accentColor
    }

    var body: some View {
        let w = targetSize?.width ?? config.size.width
        let h = targetSize?.height ?? config.size.height

        GeometryReader { geo in
            let availW = geo.size.width
            let availH = geo.size.height
            let isVertical = config.size == .tall || availH > availW * 1.08
            let isSmallSquare = !isVertical && (config.size == .small || availW < availH * 1.35)

            if isVertical {
                verticalVinylTurntableLayout(availW: availW, availH: availH)
            } else if isSmallSquare {
                smallVinylPlayerLayout(availW: availW, availH: availH)
            } else {
                horizontalVinylPlayerLayout(availW: availW, availH: availH)
            }
        }
        .frame(width: w, height: h)
        .animation(.easeInOut(duration: 0.25), value: backgroundStyle)
        .onAppear {
            musicManager.refreshNowPlaying()
            updateExtractedAccentColor(from: track.displayImage)
        }
        .onChange(of: "\(track.title)|\(track.artist)") { oldVal, newVal in
            guard oldVal != newVal, !newVal.replacingOccurrences(of: "|", with: "").isEmpty else { return }
            updateExtractedAccentColor(from: track.displayImage)
            // Si le changement de piste vient du lecteur externe ou de la fin du morceau (et non d'un clic déjà animé)
            if Date().timeIntervalSince(lastManualSkipDate) > 0.75 {
                triggerTrackChangeAnimation(direction: 1)
            }
        }
        .onChange(of: track.artworkData) { _, _ in
            updateExtractedAccentColor(from: track.displayImage)
        }
    }

    // MARK: - Disposition Petite (1×1 Carrée — Cohérente avec le Moyen : Carte + Vinyle Débordant en Haut)

    @ViewBuilder
    private func smallVinylPlayerLayout(availW: CGFloat, availH: CGFloat) -> some View {
        let outerInset: CGFloat = max(3, min(6, min(availW, availH) * 0.035))
        let isUltraCompact = availH < 126 || availW < 126

        // Le disque vinyle circulaire (identique au Moyen) déborde au sommet de la carte
        let discSize: CGFloat = min(availW * (isUltraCompact ? 0.47 : 0.50), availH * (isUltraCompact ? 0.45 : 0.48))
        let discCenterX: CGFloat = availW / 2
        let discCenterY: CGFloat = outerInset + discSize / 2
        let discBottomY: CGFloat = discCenterY + discSize / 2

        let cardWidth: CGFloat = max(60, availW - outerInset * 2)
        let cardTopY: CGFloat = outerInset + discSize * 0.35
        let cardBottomY: CGFloat = availH - outerInset
        let cardHeight: CGFloat = max(54, cardBottomY - cardTopY)
        let cardCornerRadius: CGFloat = min(18, cardHeight * 0.22)

        let horizPad: CGFloat = isUltraCompact ? 8 : 11
        let contentWidth: CGFloat = max(48, cardWidth - horizPad * 2)
        let contentTopY: CGFloat = discBottomY + (isUltraCompact ? 2 : 4)
        let contentBottomY: CGFloat = cardBottomY - (isUltraCompact ? 4 : 6)
        let contentHeight: CGFloat = max(36, contentBottomY - contentTopY)

        let titleFontSize: CGFloat = isUltraCompact ? 10.0 : 12.0
        let artistFontSize: CGFloat = isUltraCompact ? 8.0 : 9.5
        let muteIconSize: CGFloat = isUltraCompact ? 8.5 : 10.0
        let barHeight: CGFloat = isUltraCompact ? 2.6 : 3.2
        let btnFrame: CGFloat = isUltraCompact ? 18 : 22
        let sideBtnIcon: CGFloat = btnFrame * 0.44
        let playBtnIcon: CGFloat = btnFrame * 0.50

        ZStack {
            // 1. Carte inférieure (même style Clair / Sombre / Verre que le Moyen)
            playerCardBackground(cornerRadius: cardCornerRadius)
                .frame(width: cardWidth, height: cardHeight)
                .position(x: availW / 2, y: cardTopY + cardHeight / 2)

            // 2. Bouton Muet en haut à droite de la carte (comme sur le Moyen)
            Button {
                musicManager.toggleMute()
            } label: {
                Image(systemName: musicManager.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: muteIconSize, weight: .medium))
                    .foregroundStyle(musicManager.isMuted ? activeProgressColor : muteIconColor)
                    .frame(width: muteIconSize + 8, height: muteIconSize + 8)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(musicManager.isMuted ? "Réactiver le son" : "Couper le son")
            .position(
                x: (availW + cardWidth) / 2 - (isUltraCompact ? 11 : 14),
                y: cardTopY + (isUltraCompact ? 11 : 14)
            )

            // 3. Contenu sous le vinyle : Titre + Artiste, Barre colorée et Boutons (<<  Play  >>)
            VStack(spacing: 0) {
                // Titre & Artiste centrés avec la même transition verticale au changement de piste
                ZStack {
                    VStack(spacing: isUltraCompact ? 0.5 : 1.0) {
                        Text(displayTitle)
                            .font(.system(size: titleFontSize, weight: .semibold))
                            .foregroundStyle(primaryTextColor)
                            .lineLimit(1)

                        Text(displayArtist)
                            .font(.system(size: artistFontSize, weight: .regular))
                            .foregroundStyle(secondaryTextColor)
                            .lineLimit(1)
                    }
                    .id(trackTransitionID)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: transitionDirection >= 0 ? .top : .bottom)
                                .combined(with: .opacity),
                            removal: .move(edge: transitionDirection >= 0 ? .bottom : .top)
                                .combined(with: .opacity)
                        )
                    )
                }
                .frame(width: contentWidth)
                .clipped()

                Spacer(minLength: 1)

                // Barre de progression dynamique assortie au vinyle en cours
                SeekBar(
                    elapsed: Double(elapsed),
                    duration: Double(max(1, duration)),
                    trackColor: seekTrackColor,
                    fillColor: activeProgressColor,
                    barHeight: barHeight,
                    isEnabled: track.hasTrack
                ) { fraction in
                    musicManager.seek(toFraction: fraction)
                }
                .frame(width: contentWidth, height: isUltraCompact ? 8 : 10)
                .animation(.easeInOut(duration: 0.35), value: activeProgressColor)

                Spacer(minLength: 1)

                // Boutons de transport avec anneau circulaire (identiques au Moyen)
                HStack(spacing: 0) {
                    VinylTransportButton(
                        systemName: "backward.fill",
                        iconSize: sideBtnIcon,
                        frameSize: btnFrame,
                        foregroundColor: controlIconColor,
                        ringColor: controlRingColor,
                        showPersistentRing: activeRingButton == "prev",
                        help: loc("music.control.previous")
                    ) {
                        handlePreviousTrackTap()
                    }

                    Spacer(minLength: 4)

                    VinylTransportButton(
                        systemName: isPlaying ? "pause.fill" : "play.fill",
                        iconSize: playBtnIcon,
                        frameSize: btnFrame,
                        foregroundColor: controlIconColor,
                        ringColor: controlRingColor,
                        showPersistentRing: activeRingButton == "play",
                        help: loc(isPlaying ? "music.control.pause" : "music.control.play")
                    ) {
                        handlePlayPauseTap()
                    }

                    Spacer(minLength: 4)

                    VinylTransportButton(
                        systemName: "forward.fill",
                        iconSize: sideBtnIcon,
                        frameSize: btnFrame,
                        foregroundColor: controlIconColor,
                        ringColor: controlRingColor,
                        showPersistentRing: activeRingButton == "next",
                        help: loc("music.control.next")
                    ) {
                        handleNextTrackTap()
                    }
                }
                .frame(width: contentWidth)
            }
            .frame(width: contentWidth, height: contentHeight)
            .position(x: availW / 2, y: contentTopY + contentHeight / 2)

            // 4. Disque Vinyle Circulaire du son en lecture débordant en haut (même disque et animation 360° que le Moyen)
            vinylRecordDisc(size: discSize)
                .scaleEffect(discScale)
                .rotationEffect(.degrees(discRotation))
                .shadow(
                    color: .black.opacity(isLightTheme ? 0.28 : 0.52),
                    radius: isUltraCompact ? 6 : 8,
                    x: 0,
                    y: isUltraCompact ? 3 : 4
                )
                .position(x: discCenterX, y: discCenterY)
        }
        .frame(width: availW, height: availH)
    }

    // MARK: - Disposition Horizontale (Carte Pilule + Vinyle Débordant à Gauche)

    @ViewBuilder
    private func horizontalVinylPlayerLayout(availW: CGFloat, availH: CGFloat) -> some View {
        let isWide = availW >= availH * 1.45

        // Proportions inspirées de l'image de référence :
        // Le disque vinyle circulaire à gauche est plus grand que la hauteur de la carte
        // et dépasse en haut, en bas et à gauche de la pilule rectangulaire.
        let rawDiscSize: CGFloat = isWide
            ? min(availH * 0.90, availW * 0.39)
            : min(availH * 0.72, availW * 0.42)
        let cardHeight: CGFloat = isWide
            ? min(availH * 0.74, rawDiscSize * 0.80)
            : max(min(availH * 0.68, rawDiscSize * 0.84), min(availH * 0.80, 74))
        let discSize: CGFloat = max(rawDiscSize, min(availH * 0.94, cardHeight * 1.14))

        let sideInset: CGFloat = max(3, min(8, availW * 0.02))
        let cardMinX: CGFloat = sideInset + discSize * 0.34
        let cardMaxX: CGFloat = availW - sideInset
        let cardWidth: CGFloat = max(60, cardMaxX - cardMinX)
        let cardCornerRadius: CGFloat = min(20, cardHeight * 0.22)

        let contentLeadX: CGFloat = sideInset + discSize + (isWide ? 14 : 7)
        let trailingPad: CGFloat = isWide ? 16 : 8
        let contentWidth: CGFloat = max(48, cardMaxX - trailingPad - contentLeadX)

        let isCompact = !isWide || cardHeight < 84 || contentWidth < 120
        let titleFontSize: CGFloat = isCompact ? min(max(cardHeight * 0.145, 10.5), 12.5) : min(max(cardHeight * 0.155, 13.5), 15.5)
        let artistFontSize: CGFloat = isCompact ? min(max(cardHeight * 0.118, 8.5), 10.0) : min(max(cardHeight * 0.122, 10.5), 12.0)
        let muteIconSize: CGFloat = isCompact ? 10 : 12.5
        let barHeight: CGFloat = isCompact ? 3.2 : 4.2
        let btnFrame: CGFloat = isCompact ? min(22, max(18, contentWidth * 0.25)) : min(32, max(26, cardHeight * 0.32))
        let sideBtnIcon: CGFloat = isCompact ? btnFrame * 0.44 : btnFrame * 0.42
        let playBtnIcon: CGFloat = isCompact ? btnFrame * 0.50 : btnFrame * 0.48

        ZStack(alignment: .leading) {
            // 1. Carte Horizontale (Blanche en thème Clair, Sombre/Verre en thème Sombre)
            playerCardBackground(cornerRadius: cardCornerRadius)
                .frame(width: cardWidth, height: cardHeight)
                .position(x: cardMinX + cardWidth / 2, y: availH / 2)

            // 2. Contenu de la carte à droite du disque vinyle
            VStack(alignment: .leading, spacing: 0) {
                // En-tête : Titre & Artiste (animés verticalement au changement de piste) + Bouton Muet
                HStack(alignment: .center, spacing: 4) {
                    ZStack(alignment: .leading) {
                        VStack(alignment: .leading, spacing: isCompact ? 0.5 : 1.5) {
                            Text(displayTitle)
                                .font(.system(size: titleFontSize, weight: .semibold))
                                .foregroundStyle(primaryTextColor)
                                .lineLimit(1)

                            Text(displayArtist)
                                .font(.system(size: artistFontSize, weight: .regular))
                                .foregroundStyle(secondaryTextColor)
                                .lineLimit(1)
                        }
                        .id(trackTransitionID)
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: transitionDirection >= 0 ? .top : .bottom)
                                    .combined(with: .opacity),
                                removal: .move(edge: transitionDirection >= 0 ? .bottom : .top)
                                    .combined(with: .opacity)
                            )
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()

                    // Icône haut-parleur / muet (comme en haut à droite sur l'image de référence)
                    Button {
                        musicManager.toggleMute()
                    } label: {
                        Image(systemName: musicManager.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: muteIconSize, weight: .medium))
                            .foregroundStyle(musicManager.isMuted ? activeProgressColor : muteIconColor)
                            .frame(width: muteIconSize + 8, height: muteIconSize + 8)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(musicManager.isMuted ? "Réactiver le son" : "Couper le son")
                }

                Spacer(minLength: 2)

                // Barre de lecture avec couleur dynamique assortie au vinyle en cours
                SeekBar(
                    elapsed: Double(elapsed),
                    duration: Double(max(1, duration)),
                    trackColor: seekTrackColor,
                    fillColor: activeProgressColor,
                    barHeight: barHeight,
                    isEnabled: track.hasTrack
                ) { fraction in
                    musicManager.seek(toFraction: fraction)
                }
                .frame(height: isCompact ? 12 : 16)
                .animation(.easeInOut(duration: 0.35), value: activeProgressColor)

                Spacer(minLength: 2)

                // Boutons de transport (<<   Play/Pause   >>) espacés sur toute la largeur
                HStack(spacing: 0) {
                    VinylTransportButton(
                        systemName: "backward.fill",
                        iconSize: sideBtnIcon,
                        frameSize: btnFrame,
                        foregroundColor: controlIconColor,
                        ringColor: controlRingColor,
                        showPersistentRing: activeRingButton == "prev",
                        help: loc("music.control.previous")
                    ) {
                        handlePreviousTrackTap()
                    }

                    Spacer(minLength: 4)

                    VinylTransportButton(
                        systemName: isPlaying ? "pause.fill" : "play.fill",
                        iconSize: playBtnIcon,
                        frameSize: btnFrame,
                        foregroundColor: controlIconColor,
                        ringColor: controlRingColor,
                        showPersistentRing: activeRingButton == "play",
                        help: loc(isPlaying ? "music.control.pause" : "music.control.play")
                    ) {
                        handlePlayPauseTap()
                    }

                    Spacer(minLength: 4)

                    VinylTransportButton(
                        systemName: "forward.fill",
                        iconSize: sideBtnIcon,
                        frameSize: btnFrame,
                        foregroundColor: controlIconColor,
                        ringColor: controlRingColor,
                        showPersistentRing: activeRingButton == "next",
                        help: loc("music.control.next")
                    ) {
                        handleNextTrackTap()
                    }
                }
            }
            .padding(.vertical, isCompact ? max(5, cardHeight * 0.08) : max(10, cardHeight * 0.12))
            .frame(width: contentWidth, height: cardHeight)
            .position(x: contentLeadX + contentWidth / 2, y: availH / 2)

            // 3. Disque Vinyle Circulaire du son en lecture (flottant à gauche et tournant au changement de piste)
            vinylRecordDisc(size: discSize)
                .scaleEffect(discScale)
                .rotationEffect(.degrees(discRotation))
                .shadow(
                    color: .black.opacity(isLightTheme ? 0.30 : 0.54),
                    radius: isCompact ? 7 : 10,
                    x: 2,
                    y: isCompact ? 3 : 5
                )
                .position(x: sideInset + discSize / 2, y: availH / 2)
        }
        .frame(width: availW, height: availH)
    }

    // MARK: - Disposition Verticale Minimaliste & Épurée avec Profondeur par Plans d'Ombres

    @ViewBuilder
    private func verticalVinylTurntableLayout(availW: CGFloat, availH: CGFloat) -> some View {
        let cornerRadius = widgetManager.cornerRadius
        let cardShape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        // Proportions fidèles à la photo verticale de référence :
        // Grand disque vinyle noir décalé sur la gauche (coupé par le bord gauche de la carte)
        // avec la pochette du son en lecture au centre et le bras de lecture épuré en haut à droite.
        let discSize = min(availW * 1.18, availH * 0.58)
        let discCenterX = availW * 0.34
        let discCenterY = availH * 0.34

        let isCompactVertical = availW < 175 || availH < 330
        let horizPad: CGFloat = isCompactVertical ? 14 : 18
        let bottomPad: CGFloat = isCompactVertical ? 12 : 16
        let titleFontSize: CGFloat = isCompactVertical ? 15.0 : 18.0
        let artistFontSize: CGFloat = isCompactVertical ? 11.5 : 13.0
        let muteIconSize: CGFloat = isCompactVertical ? 11.5 : 13.5
        let barHeight: CGFloat = isCompactVertical ? 3.5 : 4.2
        let btnFrame: CGFloat = isCompactVertical ? 28 : 34
        let sideBtnIcon: CGFloat = btnFrame * 0.42
        let playBtnIcon: CGFloat = btnFrame * 0.48

        ZStack {
            // Plan 1 : Surface mate minimaliste et épurée (Ivoire doux en Clair, Anthracite pur en Sombre)
            verticalDeckBackground(cornerRadius: cornerRadius)

            // Plan 2 & 3 : Disque Vinyle flottant + Bras de Lecture flottant (séparés uniquement par des ombres douces)
            ZStack {
                // Plan 2 : Grand disque vinyle noir épuré avec ombre diffuse profonde sur la carte
                verticalTurntableVinylDisc(size: discSize)
                    .scaleEffect(discScale)
                    .rotationEffect(.degrees(discRotation))
                    .shadow(
                        color: .black.opacity(isLightTheme ? 0.22 : 0.50),
                        radius: isCompactVertical ? 14 : 18,
                        x: isCompactVertical ? 4 : 5,
                        y: isCompactVertical ? 8 : 11
                    )
                    .position(x: discCenterX, y: discCenterY)

                // Plan 3 : Bras de lecture minimaliste flottant au-dessus du vinyle
                verticalTurntableTonearm(availW: availW, availH: availH, discSize: discSize)
            }
            .frame(width: availW, height: availH)
            .clipShape(cardShape)

            // Zone inférieure minimaliste : Titre, Artiste, Barre de lecture & Contrôles épurés
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: isCompactVertical ? 6 : 8) {
                    // Ligne Titre & Artiste (style "Magnetic" en bas à gauche) + Bouton Muet épuré
                    HStack(alignment: .center, spacing: 6) {
                        ZStack(alignment: .leading) {
                            VStack(alignment: .leading, spacing: 1.5) {
                                Text(displayTitle)
                                    .font(.system(size: titleFontSize, weight: .bold))
                                    .foregroundStyle(primaryTextColor)
                                    .lineLimit(1)

                                Text(displayArtist)
                                    .font(.system(size: artistFontSize, weight: .medium))
                                    .foregroundStyle(secondaryTextColor)
                                    .lineLimit(1)
                            }
                            .id(trackTransitionID)
                            .transition(
                                .asymmetric(
                                    insertion: .move(edge: transitionDirection >= 0 ? .top : .bottom)
                                        .combined(with: .opacity),
                                    removal: .move(edge: transitionDirection >= 0 ? .bottom : .top)
                                        .combined(with: .opacity)
                                )
                            )
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .clipped()

                        Button {
                            musicManager.toggleMute()
                        } label: {
                            Image(systemName: musicManager.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.system(size: muteIconSize, weight: .medium))
                                .foregroundStyle(musicManager.isMuted ? activeProgressColor : muteIconColor)
                                .frame(width: muteIconSize + 10, height: muteIconSize + 10)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help(musicManager.isMuted ? "Réactiver le son" : "Couper le son")
                    }

                    // Barre de progression minimaliste assortie à la couleur du morceau
                    SeekBar(
                        elapsed: Double(elapsed),
                        duration: Double(max(1, duration)),
                        trackColor: seekTrackColor,
                        fillColor: activeProgressColor,
                        barHeight: barHeight,
                        isEnabled: track.hasTrack
                    ) { fraction in
                        musicManager.seek(toFraction: fraction)
                    }
                    .frame(height: 12)
                    .animation(.easeInOut(duration: 0.35), value: activeProgressColor)

                    // Boutons de contrôle de la musique épurés en bas (<<   Play/Pause   >>)
                    HStack(spacing: 0) {
                        VinylTransportButton(
                            systemName: "backward.fill",
                            iconSize: sideBtnIcon,
                            frameSize: btnFrame,
                            foregroundColor: controlIconColor,
                            ringColor: controlRingColor,
                            showPersistentRing: activeRingButton == "prev",
                            help: loc("music.control.previous")
                        ) {
                            handlePreviousTrackTap()
                        }

                        Spacer(minLength: 8)

                        VinylTransportButton(
                            systemName: isPlaying ? "pause.fill" : "play.fill",
                            iconSize: playBtnIcon,
                            frameSize: btnFrame,
                            foregroundColor: controlIconColor,
                            ringColor: controlRingColor,
                            showPersistentRing: activeRingButton == "play",
                            help: loc(isPlaying ? "music.control.pause" : "music.control.play")
                        ) {
                            handlePlayPauseTap()
                        }

                        Spacer(minLength: 8)

                        VinylTransportButton(
                            systemName: "forward.fill",
                            iconSize: sideBtnIcon,
                            frameSize: btnFrame,
                            foregroundColor: controlIconColor,
                            ringColor: controlRingColor,
                            showPersistentRing: activeRingButton == "next",
                            help: loc("music.control.next")
                        ) {
                            handleNextTrackTap()
                        }
                    }
                    .padding(.top, isCompactVertical ? 1 : 2)
                }
                .padding(.horizontal, horizPad)
                .padding(.bottom, bottomPad)
            }
            .frame(width: availW, height: availH)
        }
        .frame(width: availW, height: availH)
    }

    // MARK: - Actions et Animations de Changement de Musique (Style Référence GIF)

    private func handleNextTrackTap() {
        lastManualSkipDate = Date()
        flashButtonRing("next")
        if !track.hasTrack {
            demoTrackIndex = (demoTrackIndex + 1) % Self.demoTracks.count
            musicManager.nextSystemTrack()
        } else {
            musicManager.nextTrack()
        }
        triggerTrackChangeAnimation(direction: 1)
    }

    private func handlePreviousTrackTap() {
        lastManualSkipDate = Date()
        flashButtonRing("prev")
        if !track.hasTrack {
            demoTrackIndex = (demoTrackIndex - 1 + Self.demoTracks.count) % Self.demoTracks.count
            musicManager.previousSystemTrack()
        } else {
            musicManager.previousTrack()
        }
        triggerTrackChangeAnimation(direction: -1)
    }

    private func handlePlayPauseTap() {
        flashButtonRing("play")
        if !reduceMotion {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                discScale = 0.95
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
                    discScale = 1.0
                }
            }
        }
        if track.hasTrack {
            musicManager.togglePlayPause()
        } else {
            widgetManager.toggleMusicPlayback(for: .vinylPlayer)
            musicManager.playRandomMusic()
        }
    }

    private func flashButtonRing(_ id: String) {
        activeRingButton = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            if activeRingButton == id {
                activeRingButton = nil
            }
        }
    }

    /// Reproduit fidèlement l'animation du GIF : rotation rapide 360° avec léger rebond élastique
    /// dans le sens du changement de piste + glissement vertical du titre et de l'artiste.
    private func triggerTrackChangeAnimation(direction: Int) {
        transitionDirection = direction
        withAnimation(.spring(response: 0.46, dampingFraction: 0.80)) {
            trackTransitionID &+= 1
        }
        guard !reduceMotion else { return }

        withAnimation(.easeOut(duration: 0.12)) {
            discScale = 0.94
            tonearmBounceAngle = -4.5
        }
        withAnimation(.spring(response: 0.64, dampingFraction: 0.66)) {
            discRotation += Double(direction) * 360.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.68)) {
                discScale = 1.0
                tonearmBounceAngle = 0
            }
        }
    }

    // MARK: - Arrière-plan et Composants Minimalistes & Épurés de la Version Verticale

    @ViewBuilder
    private func verticalDeckBackground(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if isLightTheme {
            // Thème Clair : Surface ivoire/crème mate très épurée (fidèle à la photo de référence)
            shape
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.968, green: 0.965, blue: 0.946),
                            Color(red: 0.948, green: 0.944, blue: 0.924)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    shape.strokeBorder(Color.black.opacity(0.06), lineWidth: 0.8)
                )
                .shadow(color: .black.opacity(0.16), radius: 14, x: 0, y: 7)
        } else if backgroundStyle == .dark {
            // Thème Sombre : Surface carbone/anthracite mate épurée
            shape
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.14, green: 0.14, blue: 0.16),
                            Color(red: 0.09, green: 0.09, blue: 0.11)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    shape.strokeBorder(Color.white.opacity(0.10), lineWidth: 0.8)
                )
                .shadow(color: .black.opacity(0.45), radius: 14, x: 0, y: 7)
        } else {
            // Thème Verre / Liquid Glass : Verre sombre translucide épuré
            playerCardBackground(cornerRadius: cornerRadius)
        }
    }

    /// Disque vinyle noir minimaliste de la version verticale avec sillons subtils
    /// et pochette circulaire épurée du morceau en lecture au centre (comme sur la photo "Magnetic / Super Real Me").
    private func verticalTurntableVinylDisc(size: CGFloat) -> some View {
        let centerCoverSize = size * 0.50
        let deadwaxRingSize = size * 0.565

        return ZStack {
            // 1. Disque en vinyle noir profond et sobre
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(white: 0.11),
                            Color(white: 0.05),
                            Color(white: 0.08),
                            Color(white: 0.04)
                        ],
                        center: .center,
                        startRadius: centerCoverSize * 0.45,
                        endRadius: size / 2
                    )
                )
                .frame(width: size, height: size)

            // 2. Reflet diagonal doux et naturel sur le vinyle noir (tourne avec le disque)
            Circle()
                .fill(
                    AngularGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color.white.opacity(0.01), location: 0.00),
                            .init(color: Color.white.opacity(0.13), location: 0.11),
                            .init(color: Color.white.opacity(0.01), location: 0.22),
                            .init(color: Color.black.opacity(0.22), location: 0.36),
                            .init(color: Color.white.opacity(0.01), location: 0.50),
                            .init(color: Color.white.opacity(0.13), location: 0.61),
                            .init(color: Color.white.opacity(0.01), location: 0.72),
                            .init(color: Color.black.opacity(0.22), location: 0.86),
                            .init(color: Color.white.opacity(0.01), location: 1.00)
                        ]),
                        center: .center,
                        angle: .degrees(-32)
                    )
                )
                .frame(width: size, height: size)

            // 3. Sillons concentriques très fins et discrets
            ForEach([0.04, 0.08, 0.12, 0.16, 0.20], id: \.self) { ratio in
                Circle()
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.6)
                    .padding(size * CGFloat(ratio))
            }

            // Anneau interne discret autour du macaron central
            Circle()
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.9)
                .frame(width: deadwaxRingSize, height: deadwaxRingSize)

            // 4. Macaron central : Pochette du son en lecture pure, entourée d'un simple filet blanc fin
            ZStack {
                if let art = track.displayImage {
                    Image(nsImage: art)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .frame(width: centerCoverSize, height: centerCoverSize)
                        .clipShape(Circle())
                } else {
                    demoVinylArtwork(diameter: centerCoverSize)
                        .clipShape(Circle())
                }
            }
            .frame(width: centerCoverSize, height: centerCoverSize)
            .overlay(
                Circle()
                    .strokeBorder(
                        Color.white.opacity(isLightTheme ? 0.92 : 0.78),
                        lineWidth: max(1.1, size * 0.0075)
                    )
            )
            .animation(.easeInOut(duration: 0.28), value: trackTransitionID)
        }
        .frame(width: size, height: size)
        .drawingGroup()
    }

    /// Bras de lecture (Tonearm) minimaliste et épuré fidèle à la photo :
    /// Formes géométriques pures, sans biseaux 3D superflus, avec une ombre portée douce qui crée la profondeur.
    private func verticalTurntableTonearm(availW: CGFloat, availH: CGFloat, discSize: CGFloat) -> some View {
        let pivotX = availW * 0.885
        let pivotY = availH * 0.175
        let baseSize = availW * 0.34
        let innerBaseSize = baseSize * 0.66

        let scale = max(0.72, min(1.35, discSize / 175.0))
        let rodLength = discSize * 0.44
        let armHousingFill = isLightTheme
            ? Color(red: 0.968, green: 0.965, blue: 0.948)
            : Color(red: 0.22, green: 0.22, blue: 0.25)
        let armHousingStroke = isLightTheme
            ? Color.black.opacity(0.08)
            : Color.white.opacity(0.14)
        let baseStroke = isLightTheme
            ? Color.black.opacity(0.15)
            : Color.white.opacity(0.18)

        // Angle du bras : posé sur les sillons (~23.5°) avec légère réaction au changement de piste
        let restOffset: Double = isPlaying ? 0.0 : -3.0
        let totalAngle: Double = 23.5 + restOffset + tonearmBounceAngle

        return ZStack {
            // 1. Socle circulaire minimaliste en haut à droite (avec ombre douce)
            ZStack {
                Circle()
                    .fill(
                        isLightTheme
                            ? Color(red: 0.962, green: 0.960, blue: 0.942).opacity(0.94)
                            : Color(red: 0.16, green: 0.16, blue: 0.19).opacity(0.94)
                    )
                    .frame(width: baseSize, height: baseSize)
                    .overlay(
                        Circle().strokeBorder(baseStroke, lineWidth: 0.9)
                    )
                    .shadow(color: .black.opacity(isLightTheme ? 0.10 : 0.32), radius: 8, x: -2, y: 4)

                Circle()
                    .strokeBorder(baseStroke.opacity(0.65), lineWidth: 0.75)
                    .frame(width: innerBaseSize, height: innerBaseSize)
            }
            .position(x: pivotX, y: pivotY)

            // 2. Bras minimaliste (formes géométriques épurées + ombre portée douce sur le vinyle)
            ZStack(alignment: .top) {
                // Contrepoids arrière épuré
                RoundedRectangle(cornerRadius: 2.2 * scale, style: .continuous)
                    .fill(armHousingFill)
                    .frame(width: 14 * scale, height: 9 * scale)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2.2 * scale, style: .continuous)
                            .strokeBorder(armHousingStroke, lineWidth: 0.6)
                    )
                    .offset(x: -1.5 * scale, y: -7 * scale)

                VStack(spacing: 0) {
                    // Bloc pivot rectangulaire minimaliste
                    HStack(spacing: 0) {
                        RoundedRectangle(cornerRadius: 2.2 * scale, style: .continuous)
                            .fill(armHousingFill)
                            .frame(width: 17 * scale, height: 19 * scale)
                            .overlay(
                                RoundedRectangle(cornerRadius: 2.2 * scale, style: .continuous)
                                    .strokeBorder(armHousingStroke, lineWidth: 0.6)
                            )

                        RoundedRectangle(cornerRadius: 1.8 * scale, style: .continuous)
                            .fill(armHousingFill)
                            .frame(width: 8 * scale, height: 21 * scale)
                            .overlay(
                                RoundedRectangle(cornerRadius: 1.8 * scale, style: .continuous)
                                    .strokeBorder(armHousingStroke, lineWidth: 0.6)
                            )
                            .offset(x: -1 * scale, y: 1.5 * scale)
                    }

                    // Manchon supérieur
                    RoundedRectangle(cornerRadius: 1.4 * scale, style: .continuous)
                        .fill(armHousingFill)
                        .frame(width: 6.5 * scale, height: 10 * scale)
                        .overlay(
                            RoundedRectangle(cornerRadius: 1.4 * scale, style: .continuous)
                                .strokeBorder(armHousingStroke, lineWidth: 0.5)
                        )
                        .offset(x: 3.5 * scale, y: -1 * scale)

                    // Tige fine en aluminium satiné
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(white: 0.62),
                                    Color(white: 0.90),
                                    Color(white: 0.76),
                                    Color(white: 0.52)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 4.0 * scale, height: rodLength)
                        .offset(x: 3.5 * scale, y: -1 * scale)

                    // Manchon inférieur + Porte-cellule rectangulaire épuré avec ergot
                    ZStack(alignment: .top) {
                        RoundedRectangle(cornerRadius: 1.4 * scale, style: .continuous)
                            .fill(armHousingFill)
                            .frame(width: 6.5 * scale, height: 9 * scale)
                            .overlay(
                                RoundedRectangle(cornerRadius: 1.4 * scale, style: .continuous)
                                    .strokeBorder(armHousingStroke, lineWidth: 0.5)
                            )

                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 2.2 * scale, style: .continuous)
                                .fill(armHousingFill)
                                .frame(width: 12.5 * scale, height: 23 * scale)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 2.2 * scale, style: .continuous)
                                        .strokeBorder(armHousingStroke, lineWidth: 0.6)
                                )

                            // Petit ergot (finger-lift) perpendiculaire au porte-cellule
                            Capsule()
                                .fill(armHousingFill)
                                .frame(width: 2.5 * scale, height: 8.5 * scale)
                                .overlay(Capsule().strokeBorder(armHousingStroke, lineWidth: 0.5))
                                .rotationEffect(.degrees(-88), anchor: .top)
                                .offset(x: -5.5 * scale, y: 2.5 * scale)
                        }
                        .rotationEffect(.degrees(28), anchor: .top)
                        .offset(x: -1.5 * scale, y: 6.5 * scale)
                    }
                    .offset(x: 3.5 * scale, y: -2 * scale)
                }
            }
            // Ombre portée douce et diffuse qui détache le bras du disque vinyle sans effet 3D lourd
            .drawingGroup()
            .shadow(
                color: .black.opacity(isLightTheme ? 0.24 : 0.50),
                radius: 7 * scale,
                x: -3 * scale,
                y: 6 * scale
            )
            .frame(width: 44 * scale, height: 220 * scale, alignment: .top)
            .offset(y: 100 * scale)
            .rotationEffect(.degrees(totalAngle), anchor: .center)
            .position(x: pivotX, y: pivotY)
            .animation(.spring(response: 0.48, dampingFraction: 0.72), value: totalAngle)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Arrière-plan de la Carte selon le Thème (Clair vs Sombre)

    @ViewBuilder
    private func playerCardBackground(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if isLightTheme {
            // Thème Clair : Carte blanche lumineuse fidèle à l'image de référence
            shape
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white,
                            Color(white: 0.965)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    shape.strokeBorder(Color.black.opacity(0.06), lineWidth: 0.8)
                )
                .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 5)
        } else if backgroundStyle == .dark {
            // Thème Sombre : Carte carbone profond élégante et contrastée
            shape
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.16, green: 0.16, blue: 0.19),
                            Color(red: 0.10, green: 0.10, blue: 0.12)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.18),
                                Color.white.opacity(0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.9
                    )
                )
                .shadow(color: .black.opacity(0.45), radius: 14, x: 0, y: 7)
        } else {
            // Thème Verre / Liquid Glass : Verre sombre translucide avec biseau lumineux
            shape
                .fill(.ultraThinMaterial)
                .overlay(
                    shape.fill(Color(red: 0.08, green: 0.09, blue: 0.13).opacity(widgetManager.glassOpacity * 0.82))
                )
                .overlay(
                    shape.fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.18),
                                Color.white.opacity(0.03),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
                )
                .overlay(
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [
                                widgetManager.glowColor == .none ? Color.white.opacity(0.45) : widgetManager.glowColor.primaryColor.opacity(0.60),
                                Color.white.opacity(0.14),
                                Color.white.opacity(0.20)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.0
                    )
                )
                .shadow(color: .black.opacity(0.38), radius: 14, x: 0, y: 7)
        }
    }

    // MARK: - Disque Vinyle du Son en Lecture

    private func vinylRecordDisc(size: CGFloat) -> some View {
        let rimWidth = max(3.5, size * 0.065)
        let artworkDiameter = max(10, size - rimWidth * 2)
        let centerCollarSize = size * 0.21
        let spindleSize = max(6, size * 0.115)

        return ZStack {
            // 1. Base du disque vinyle noir avec reflets anisotropes
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(white: 0.16),
                            Color(white: 0.07),
                            Color(white: 0.13),
                            Color(white: 0.05)
                        ],
                        center: .center,
                        startRadius: 2,
                        endRadius: size / 2
                    )
                )
                .frame(width: size, height: size)

            // 2. Pochette du son en lecture pressée sur le disque (Picture-Disc Vinyl)
            ZStack {
                if let art = track.displayImage {
                    Image(nsImage: art)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .frame(width: artworkDiameter, height: artworkDiameter)
                        .clipShape(Circle())
                } else {
                    // Illustration vinyle riche si aucun lecteur externe ne diffuse de miniature
                    demoVinylArtwork(diameter: artworkDiameter)
                }
            }
            .frame(width: artworkDiameter, height: artworkDiameter)
            .clipShape(Circle())
            .animation(.easeInOut(duration: 0.28), value: trackTransitionID)

            // 3. Sillons concentriques gravés sur toute la surface du vinyle (aspect authentique de vinyle)
            Circle()
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.7)
                .padding(rimWidth * 0.45)

            Circle()
                .strokeBorder(Color.black.opacity(0.35), lineWidth: 1.0)
                .padding(rimWidth)

            ForEach([0.14, 0.21, 0.28, 0.35], id: \.self) { ratio in
                Circle()
                    .strokeBorder(
                        AngularGradient(
                            colors: [
                                Color.white.opacity(0.16),
                                Color.black.opacity(0.22),
                                Color.white.opacity(0.14),
                                Color.black.opacity(0.22),
                                Color.white.opacity(0.16)
                            ],
                            center: .center
                        ),
                        lineWidth: 0.75
                    )
                    .padding(size * CGFloat(ratio))
            }

            // 4. Reflet spéculaire diagonal typique d'un disque vinyle en rotation
            Circle()
                .fill(
                    AngularGradient(
                        gradient: Gradient(stops: [
                            .init(color: .clear, location: 0.00),
                            .init(color: .white.opacity(0.18), location: 0.12),
                            .init(color: .clear, location: 0.25),
                            .init(color: .black.opacity(0.14), location: 0.38),
                            .init(color: .clear, location: 0.50),
                            .init(color: .white.opacity(0.18), location: 0.62),
                            .init(color: .clear, location: 0.75),
                            .init(color: .black.opacity(0.14), location: 0.88),
                            .init(color: .clear, location: 1.00)
                        ]),
                        center: .center,
                        angle: .degrees(-35)
                    )
                )
                .frame(width: size, height: size)
                .allowsHitTesting(false)

            // 5. Anneau central du macaron et trou d'axe (Spindle Hole) comme sur la référence
            Circle()
                .fill(Color.black.opacity(0.28))
                .frame(width: centerCollarSize, height: centerCollarSize)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.7)
                )

            Circle()
                .fill(spindleHoleColor)
                .frame(width: spindleSize, height: spindleSize)
                .overlay(
                    Circle()
                        .strokeBorder(Color.black.opacity(0.22), lineWidth: 0.8)
                )
                .shadow(color: .black.opacity(0.25), radius: 1.5, x: 0, y: 0.5)

            // Bordure extérieure fine du disque
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.28), Color.black.opacity(0.55)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.9
                )
                .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
        .drawingGroup()
    }

    @ViewBuilder
    private func demoVinylArtwork(diameter: CGFloat) -> some View {
        let colors = currentDemo.palette
        ZStack {
            AngularGradient(
                colors: [colors[0], colors[1], colors[2], colors[3], colors[0]],
                center: .center
            )
            RadialGradient(
                colors: [colors[2].opacity(0.65), colors[1].opacity(0.25), Color.clear],
                center: UnitPoint(x: 0.32, y: 0.28),
                startRadius: 2,
                endRadius: diameter * 0.55
            )
            // Détail graphique asymétrique permettant de bien visualiser la rotation 360°
            Path { path in
                path.move(to: CGPoint(x: diameter * 0.15, y: diameter * 0.20))
                path.addQuadCurve(
                    to: CGPoint(x: diameter * 0.85, y: diameter * 0.80),
                    control: CGPoint(x: diameter * 0.62, y: diameter * 0.30)
                )
            }
            .stroke(colors[2].opacity(0.85), lineWidth: max(1.5, diameter * 0.022))
        }
        .frame(width: diameter, height: diameter)
    }

    // MARK: - Extraction Rapide et Mise en Cache de la Couleur Dominante de la Pochette

    @MainActor
    private static var accentColorCache: [String: Color] = [:]

    private func updateExtractedAccentColor(from image: NSImage?) {
        guard let image else {
            if extractedAccentColor != nil { extractedAccentColor = nil }
            return
        }
        let cacheKey = "\(track.title)|\(track.artist)|\(track.artworkData?.count ?? 0)"
        if let cached = Self.accentColorCache[cacheKey] {
            if extractedAccentColor != cached {
                extractedAccentColor = cached
            }
            return
        }
        if let color = Self.extractVibrantColor(from: image) {
            if Self.accentColorCache.count > 64 {
                Self.accentColorCache.removeAll(keepingCapacity: true)
            }
            Self.accentColorCache[cacheKey] = color
            extractedAccentColor = color
        } else {
            extractedAccentColor = nil
        }
    }

    private static func extractVibrantColor(from image: NSImage) -> Color? {
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            return nil
        }
        let sampleSize = 12
        var pixels = [UInt8](repeating: 0, count: sampleSize * sampleSize * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels,
            width: sampleSize,
            height: sampleSize,
            bitsPerComponent: 8,
            bytesPerRow: sampleSize * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: sampleSize, height: sampleSize))

        var bestR: Double = 0.05
        var bestG: Double = 0.31
        var bestB: Double = 0.85
        var bestScore: Double = -1.0

        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[i]) / 255.0
            let g = Double(pixels[i + 1]) / 255.0
            let b = Double(pixels[i + 2]) / 255.0

            let maxC = max(r, max(g, b))
            let minC = min(r, min(g, b))
            let delta = maxC - minC
            let saturation = maxC > 0 ? (delta / maxC) : 0
            let brightness = maxC

            // Privilégie les teintes saturées ni trop noires ni trop blanches
            let score = saturation * 2.2 + (brightness > 0.18 && brightness < 0.92 ? 0.5 : 0.0)
            if score > bestScore {
                bestScore = score
                bestR = r
                bestG = g
                bestB = b
            }
        }

        let nsColor = NSColor(srgbRed: bestR, green: bestG, blue: bestB, alpha: 1.0)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        nsColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let adjustedS = max(0.65, min(0.95, s * 1.15))
        let adjustedB = max(0.58, min(0.88, b))
        return Color(hue: Double(h), saturation: Double(adjustedS), brightness: Double(adjustedB))
    }
}

// MARK: - 4. Widget Météo Typographique (Small, Medium, Tall)

struct WeatherWidgetView: View {
    let config: CustomWidgetConfig
    var targetSize: CGSize? = nil

    var body: some View {
        WidgetContainerView(size: config.size, targetSize: targetSize) {
            ZStack {
                // Aura atmosphérique selon la météo
                weatherAtmosphereAura

                switch config.size {
                case .medium:
                    mediumWeatherView
                case .tall:
                    tallWeatherView
                default:
                    smallWeatherView
                }
            }
        }
    }

    // Aura lumineuse adaptée au temps
    private var weatherAtmosphereAura: some View {
        let colors: [Color] = {
            switch config.weatherCondition.lowercased() {
            case "sunny", "clear":
                return [Color.orange.opacity(0.18), Color.yellow.opacity(0.08), Color.clear]
            case "rainy":
                return [Color.blue.opacity(0.20), Color.indigo.opacity(0.10), Color.clear]
            default:
                return [Color.cyan.opacity(0.12), Color.indigo.opacity(0.06), Color.clear]
            }
        }()
        return RadialGradient(
            colors: colors,
            center: .topTrailing,
            startRadius: 20,
            endRadius: 220
        )
    }

    // MARK: - Petit Format (1x1 ou 180x180)
    private var smallWeatherView: some View {
        GeometryReader { geo in
            let isCompact = geo.size.height < 175 || geo.size.width < 175
            let pad: CGFloat = isCompact ? 11 : 16
            let iconBox: CGFloat = isCompact ? 26 : 32
            let iconFont: CGFloat = isCompact ? 13 : 16
            let cityFont: CGFloat = isCompact ? 12 : 14
            let tempFont: CGFloat = isCompact ? 34 : 46
            let descFont: CGFloat = isCompact ? 11.5 : 13
            let detailFont: CGFloat = isCompact ? 9.5 : 10.5

            VStack(alignment: .leading, spacing: 0) {
                // En-tête : Ville + Symbole météo
                HStack(alignment: .top) {
                    HStack(spacing: 3) {
                        Image(systemName: "location.fill")
                            .font(.system(size: isCompact ? 9.5 : 11, weight: .bold))
                            .foregroundStyle(Color(red: 0.25, green: 0.80, blue: 1.0))
                        Text(config.weatherCity)
                            .font(.system(size: cityFont, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }

                    Spacer()

                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.12))
                            .frame(width: iconBox, height: iconBox)
                        Image(systemName: conditionIcon(config.weatherCondition))
                            .font(.system(size: iconFont))
                            .symbolRenderingMode(.multicolor)
                    }
                }

                Spacer(minLength: 2)

                // Température Héroïque
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(config.weatherTemp)°")
                        .font(.system(size: tempFont, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }

                // Description et ressenti
                VStack(alignment: .leading, spacing: 1.5) {
                    Text(localizedCondition(config.weatherCondition))
                        .font(.system(size: descFont, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        Text("\(loc("widget.weather.feels")) \(config.weatherFeelsLike)°")
                            .font(.system(size: detailFont, weight: .medium))
                            .foregroundStyle(.white.opacity(0.70))

                        Text("•")
                            .font(.system(size: 8))
                            .foregroundStyle(.white.opacity(0.40))

                        Text("H:\(config.weatherTemp + 3)° B:\(max(0, config.weatherTemp - 4))°")
                            .font(.system(size: detailFont, weight: .medium))
                            .foregroundStyle(.white.opacity(0.60))
                    }
                }
            }
            .padding(pad)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
    }

    // MARK: - Format Moyen (2x1) - Vue Héroïque + Prévisions Horaires
    private var mediumWeatherView: some View {
        GeometryReader { geo in
            let isCompact = geo.size.height < 120 || geo.size.width < 250
            HStack(spacing: isCompact ? 8 : 14) {
                // Côté Gauche : Température principale & Ville
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .font(.system(size: isCompact ? 9 : 11, weight: .bold))
                            .foregroundStyle(Color(red: 0.25, green: 0.80, blue: 1.0))
                        Text(config.weatherCity)
                            .font(.system(size: isCompact ? 11 : 13.5, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text("\(config.weatherTemp)°")
                        .font(.system(size: isCompact ? 28 : 38, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Spacer()

                    Text(localizedCondition(config.weatherCondition))
                        .font(.system(size: isCompact ? 10 : 12, weight: .semibold))
                        .foregroundStyle(.white)

                    Text("\(loc("widget.weather.feels")) \(config.weatherFeelsLike)°")
                        .font(.system(size: isCompact ? 8.5 : 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Côté Droit : Prévisions Horaires
                VStack(alignment: .leading, spacing: isCompact ? 3 : 5) {
                    Text(loc("widget.weather.forecast"))
                        .font(.system(size: isCompact ? 8 : 9.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.60))
                        .textCase(.uppercase)

                    HStack(spacing: isCompact ? 4 : 6) {
                        hourlySlot(time: "Maintenant", icon: conditionIcon(config.weatherCondition), temp: config.weatherTemp, isCompact: isCompact)
                        hourlySlot(time: "+2h", icon: "sun.max.fill", temp: config.weatherTemp + 1, isCompact: isCompact)
                        if !isCompact {
                            hourlySlot(time: "+4h", icon: "cloud.sun.fill", temp: config.weatherTemp, isCompact: isCompact)
                        }
                    }
                }
            }
            .padding(isCompact ? 8 : 12)
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    // MARK: - Format Vertical Haut (180x372) - Tableau de bord météo complet
    private var tallWeatherView: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Haut : Ville & Grande Température
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Image(systemName: "location.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(red: 0.25, green: 0.80, blue: 1.0))
                    Text(config.weatherCity)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: conditionIcon(config.weatherCondition))
                        .font(.system(size: 20))
                        .symbolRenderingMode(.multicolor)
                }

                Text("\(config.weatherTemp)°")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(localizedCondition(config.weatherCondition))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }

            Divider().background(Color.white.opacity(0.12))

            // Grille 2x2 des métriques météo
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    weatherStatTile(icon: "humidity.fill", title: loc("widget.weather.humidity"), value: "68%", color: .cyan)
                    weatherStatTile(icon: "wind", title: loc("widget.weather.wind"), value: "14 km/h", color: .teal)
                }
                HStack(spacing: 8) {
                    weatherStatTile(icon: "sun.max.trianglebadge.exclamationmark", title: loc("widget.weather.uv"), value: "3 Modéré", color: .orange)
                    weatherStatTile(icon: "eye.fill", title: loc("widget.weather.visibility"), value: "10 km", color: .blue)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private func hourlySlot(time: String, icon: String, temp: Int, isCompact: Bool = false) -> some View {
        VStack(spacing: isCompact ? 3 : 6) {
            Text(time)
                .font(.system(size: isCompact ? 8 : 9.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.70))

            Image(systemName: icon)
                .font(.system(size: isCompact ? 12 : 15))
                .symbolRenderingMode(.multicolor)
                .frame(height: isCompact ? 15 : 20)

            Text("\(temp)°")
                .font(.system(size: isCompact ? 10 : 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.vertical, isCompact ? 4 : 8)
        .padding(.horizontal, isCompact ? 4 : 6)
        .frame(width: isCompact ? 34 : 44)
        .background(
            RoundedRectangle(cornerRadius: isCompact ? 8 : 12, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: isCompact ? 8 : 12, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 0.8))
        )
    }

    private func weatherStatTile(icon: String, title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.60))
            }
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.07))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6))
        )
    }

    private func conditionIcon(_ cond: String) -> String {
        switch cond.lowercased() {
        case "sunny", "clear": return "sun.max.fill"
        case "rainy": return "cloud.rain.fill"
        default: return "cloud.sun.fill"
        }
    }

    private func localizedCondition(_ cond: String) -> String {
        loc("widget.weather.cond.\(cond.lowercased())")
    }
}

/// Symbole vectoriel Spotify (3 arcs incurvés) utilisé uniquement lorsque Spotify est la plateforme active.
private struct SpotifyGlyphShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        // Arc supérieur
        path.move(to: CGPoint(x: w * 0.20, y: h * 0.34))
        path.addQuadCurve(
            to: CGPoint(x: w * 0.82, y: h * 0.40),
            control: CGPoint(x: w * 0.52, y: h * 0.22)
        )

        // Arc médian
        path.move(to: CGPoint(x: w * 0.24, y: h * 0.53))
        path.addQuadCurve(
            to: CGPoint(x: w * 0.77, y: h * 0.58),
            control: CGPoint(x: w * 0.51, y: h * 0.43)
        )

        // Arc inférieur
        path.move(to: CGPoint(x: w * 0.29, y: h * 0.71))
        path.addQuadCurve(
            to: CGPoint(x: w * 0.71, y: h * 0.75),
            control: CGPoint(x: w * 0.50, y: h * 0.63)
        )

        return path
    }
}

// MARK: - 5. Widget Lecteur Multimédia (Small, Medium, Tall, Large)

struct MediaWideWidgetView: View {
    let config: CustomWidgetConfig
    var targetSize: CGSize? = nil
    @ObservedObject private var widgetManager = WidgetManager.shared
    @ObservedObject private var musicManager = MusicServiceManager.shared

    private var track: NowPlayingTrack {
        musicManager.currentTrack
    }

    var body: some View {
        WidgetContainerView(size: config.size, targetSize: targetSize) {
            if config.size == .medium || config.size == .large {
                landscapeMediaView
            } else if !track.hasTrack {
                emptyStateView
            } else {
                portraitMediaView
            }
        }
        .onAppear {
            musicManager.refreshNowPlaying()
        }
    }

    // MARK: - Style Portrait / Petit (Cover plein écran, pilule en haut, contrôles en bas)
    private var portraitMediaView: some View {
        GeometryReader { geo in
            let isCompact = geo.size.height < 175 || geo.size.width < 175
            // Sous ~112 pt, la version compacte ne tient plus : on resserre encore
            // les espacements pour que les trois boutons restent visibles.
            let isDense = geo.size.height < 112
            // Configuration extrême (beaucoup de lignes/colonnes) : on sacrifie
            // l'artiste et les compteurs pour conserver les contrôles.
            let isUltraDense = geo.size.height < 98
            ZStack(alignment: .bottom) {
                // Arrière-plan : Pochette d'album plein format
                if let art = track.artworkImage {
                    Image(nsImage: art)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    ZStack {
                        LinearGradient(
                            colors: [Color(red: 0.72, green: 0.16, blue: 0.14), Color(red: 0.28, green: 0.07, blue: 0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        // Aucune miniature publiée : icône de l'application source, centrée
                        if let icon = track.displayImage {
                            Image(nsImage: icon)
                                .resizable()
                                .scaledToFit()
                                .frame(width: min(geo.size.width, geo.size.height) * 0.42)
                                .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
                                .offset(y: -geo.size.height * 0.08)
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }

                // Dégradé sombre multicouche pour lisibilité maximale
                LinearGradient(
                    stops: [
                        .init(color: Color.black.opacity(0.45), location: 0.0),
                        .init(color: Color.black.opacity(0.12), location: 0.35),
                        .init(color: Color.black.opacity(0.72), location: 0.65),
                        .init(color: Color.black.opacity(0.94), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

                // Contenu
                VStack(spacing: 0) {
                    if !isCompact {
                        // Pilule flottante supérieure
                        HStack(spacing: 7) {
                            if let art = track.displayImage {
                                Image(nsImage: art)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 22, height: 22)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            } else {
                                Image(systemName: "music.note")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white.opacity(0.85))
                                    .frame(width: 22, height: 22)
                                    .background(Color.white.opacity(0.15))
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            }

                            VStack(alignment: .leading, spacing: 0.5) {
                                Text(track.title.isEmpty ? "Morceau" : track.title)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Text(track.album.isEmpty ? track.artist : track.album)
                                    .font(.system(size: 8.5, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.70))
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 0)

                            serviceBadgeIcon
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.20), lineWidth: 0.8))
                        .padding(.horizontal, 10)
                        .padding(.top, 10)
                    }

                    Spacer()

                    // Zone inférieure : Titre, barre de progression et contrôles
                    VStack(alignment: .leading, spacing: isUltraDense ? 1.5 : (isDense ? 2.5 : (isCompact ? 3.5 : 6))) {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(track.title.isEmpty ? track.artist : track.title)
                                    .font(.system(size: config.size == .tall ? 22 : (isUltraDense ? 11 : (isDense ? 11.5 : (isCompact ? 12.5 : 15))), weight: .bold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .shadow(color: .black.opacity(0.7), radius: 6, y: 2)

                                if !track.artist.isEmpty && !isUltraDense {
                                    Text(track.artist)
                                        .font(.system(size: config.size == .tall ? 13 : (isDense ? 9 : (isCompact ? 9.5 : 11)), weight: .medium))
                                        .foregroundStyle(.white.opacity(0.85))
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            MiniEqualizerBars(isPlaying: track.isPlaying, color: Color.white.opacity(0.90))
                        }

                        // Timers
                        if !isUltraDense {
                            HStack {
                                Text(formatSeconds(Int(track.elapsedSeconds)))
                                    .font(.system(size: isDense ? 8 : (isCompact ? 8.5 : 9.5), weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.75))
                                Spacer()
                                Text(formatSeconds(Int(track.durationSeconds)))
                                    .font(.system(size: isDense ? 8 : (isCompact ? 8.5 : 9.5), weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                            .padding(.top, isDense ? 0 : (isCompact ? 1 : 2))
                        }

                        // Barre de progression
                        SeekBar(
                            elapsed: track.elapsedSeconds,
                            duration: track.durationSeconds,
                            trackColor: Color.white.opacity(0.25),
                            fillColor: Color.white,
                            barHeight: isUltraDense ? 2 : (isDense ? 2 : (isCompact ? 2.5 : 3.5)),
                            isEnabled: true
                        ) { fraction in
                            musicManager.seek(toFraction: fraction)
                        }

                        // Contrôles de lecture
                        HStack {
                            Spacer()
                            MediaControlButton(
                                systemName: "backward.fill",
                                iconSize: isUltraDense ? 9 : (isDense ? 10 : (isCompact ? 10.5 : 13)),
                                frameSize: isUltraDense ? 24 : (isDense ? 28 : (isCompact ? 30 : 34)),
                                help: loc("music.control.previous")
                            ) {
                                musicManager.previousTrack()
                            }

                            Spacer()

                            MediaControlButton(
                                systemName: track.isPlaying ? "pause.fill" : "play.fill",
                                iconSize: isUltraDense ? 10 : (isDense ? 11 : (isCompact ? 11.5 : 14)),
                                frameSize: isUltraDense ? 26 : (isDense ? 30 : (isCompact ? 32 : 38)),
                                isPrimary: true,
                                help: loc(track.isPlaying ? "music.control.pause" : "music.control.play")
                            ) {
                                musicManager.togglePlayPause()
                            }

                            Spacer()

                            MediaControlButton(
                                systemName: "forward.fill",
                                iconSize: isUltraDense ? 9 : (isDense ? 10 : (isCompact ? 10.5 : 13)),
                                frameSize: isUltraDense ? 24 : (isDense ? 28 : (isCompact ? 30 : 34)),
                                help: loc("music.control.next")
                            ) {
                                musicManager.nextTrack()
                            }

                            Spacer()
                        }
                        .padding(.top, isDense ? 1 : (isCompact ? 2 : 4))
                        .padding(.bottom, isDense ? 1 : (isCompact ? 2 : 4))
                    }
                    .padding(.horizontal, isUltraDense ? 6 : (isDense ? 8 : (isCompact ? 10 : 14)))
                    .padding(.bottom, isUltraDense ? 4 : (isDense ? 6 : (isCompact ? 8 : 10)))
                }
            }
            // Badge discret en haut à droite en mode compact 1x1 : en superposition
            // pour ne pas réduire la hauteur disponible pour les contrôles.
            .overlay(alignment: .topTrailing) {
                if isCompact && !isUltraDense {
                    serviceBadgeIcon
                        .padding(6)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .padding(8)
                }
            }
        }
    }

    // MARK: - Détection dynamique de la plateforme musicale active

    private enum ActiveMediaPlatform {
        case appleMusic
        case spotify
        case browser(name: String, isSafari: Bool)
        case videoPlayer(name: String)
        case podcasts
        case customApp(name: String, bundleID: String)
    }

    private var activePlatform: ActiveMediaPlatform {
        let bundle = track.sourceBundleID.lowercased()

        if track.hasTrack {
            if track.serviceSource == .spotify || bundle.contains("spotify") {
                return .spotify
            }
            if track.serviceSource == .appleMusic || bundle == "com.apple.music" {
                return .appleMusic
            }
            if bundle.contains("podcasts") {
                return .podcasts
            }
            if bundle.contains("safari") {
                return .browser(name: track.sourceAppName.isEmpty ? "Safari" : track.sourceAppName, isSafari: true)
            }
            if bundle.contains("chrome") || bundle.contains("brave") || bundle.contains("arc") || bundle.contains("firefox") || bundle.contains("edgemac") || bundle.contains("opera") || bundle.contains("vivaldi") || bundle.contains("zen") {
                let name = track.sourceAppName.isEmpty ? "Web" : track.sourceAppName
                return .browser(name: name, isSafari: false)
            }
            if bundle.contains("vlc") || bundle.contains("iina") || bundle.contains("quicktime") || bundle == "com.apple.tv" {
                let name = track.sourceAppName.isEmpty ? "Vidéo" : track.sourceAppName
                return .videoPlayer(name: name)
            }
            if !track.sourceBundleID.isEmpty || !track.sourceAppName.isEmpty {
                let name = track.sourceAppName.isEmpty ? "Mac" : track.sourceAppName
                return .customApp(name: name, bundleID: track.sourceBundleID)
            }
        }

        // Aucune lecture active : on affiche la plateforme configurée ou ouverte sur le Mac
        if musicManager.preferredService == .spotify {
            return .spotify
        }
        if musicManager.preferredService == .appleMusic {
            return .appleMusic
        }
        if musicManager.spotifyStatus.isConnected && !musicManager.appleMusicStatus.isConnected {
            return .spotify
        }
        if musicManager.appleMusicStatus.isConnected && !musicManager.spotifyStatus.isConnected {
            return .appleMusic
        }
        if !NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty {
            return .spotify
        }
        return .appleMusic
    }

    private var activePlatformDisplayName: String {
        switch activePlatform {
        case .appleMusic:
            return "Apple Music"
        case .spotify:
            return "Spotify"
        case .browser(let name, _):
            return name
        case .videoPlayer(let name):
            return name
        case .podcasts:
            return "Podcasts"
        case .customApp(let name, _):
            return name
        }
    }

    @ViewBuilder
    private func activePlatformBadge(size: CGFloat) -> some View {
        ZStack {
            switch activePlatform {
            case .appleMusic:
                Image(systemName: "apple.logo")
                    .font(.system(size: size * 0.72, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.45), radius: 3, y: 1)

            case .spotify:
                SpotifyGlyphShape()
                    .stroke(
                        Color.white,
                        style: StrokeStyle(lineWidth: size * 0.11, lineCap: .round)
                    )
                    .frame(width: size * 0.85, height: size * 0.85)
                    .shadow(color: .black.opacity(0.45), radius: 3, y: 1)

            case .browser(_, let isSafari):
                Image(systemName: isSafari ? "safari.fill" : "globe")
                    .font(.system(size: size * 0.72, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.45), radius: 3, y: 1)

            case .videoPlayer:
                Image(systemName: "play.tv.fill")
                    .font(.system(size: size * 0.68, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.45), radius: 3, y: 1)

            case .podcasts:
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: size * 0.70, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.45), radius: 3, y: 1)

            case .customApp(_, let bundleID):
                if !bundleID.isEmpty, let icon = SystemNowPlayingClient.appIcon(bundleID: bundleID) {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: size, height: size)
                        .shadow(color: .black.opacity(0.40), radius: 3, y: 1)
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.70, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
                }
            }
        }
        .frame(width: size, height: size)
        .help(activePlatformDisplayName)
    }

    // MARK: - Style Paysage / Moyen (2x1) (Cover plein format, plateforme active, squircle play/pause & barre droite)
    private var landscapeMediaView: some View {
        GeometryReader { geo in
            let isCompact = geo.size.height < 138 || geo.size.width < 250
            let horizontalPad: CGFloat = isCompact ? 13 : 17
            let verticalPad: CGFloat = isCompact ? 11 : 14

            let displayTitle: String = {
                if track.hasTrack && !track.title.isEmpty {
                    return track.title
                }
                if !config.musicTrack.isEmpty {
                    return config.musicTrack
                }
                return loc("music.widget.no_track")
            }()

            let displayArtist: String = {
                if track.hasTrack && !track.artist.isEmpty {
                    return track.artist
                }
                if !config.musicArtist.isEmpty {
                    return config.musicArtist
                }
                return activePlatformDisplayName
            }()

            ZStack {
                // 1. Arrière-plan : Pochette d'album plein format (ou fond studio éditorial en veille)
                if let art = track.artworkImage {
                    Image(nsImage: art)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    ZStack {
                        LinearGradient(
                            colors: [
                                Color(red: 0.34, green: 0.35, blue: 0.36),
                                Color(red: 0.22, green: 0.23, blue: 0.24),
                                Color(red: 0.13, green: 0.14, blue: 0.15)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )

                        // Halo atmosphérique subtil (sans flou gaussien dynamique coûteux)
                        RadialGradient(
                            colors: [Color.white.opacity(0.16), Color.clear],
                            center: .top,
                            startRadius: 10,
                            endRadius: geo.size.width * 0.75
                        )
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }

                // 2. Voile de contraste atmosphérique pour garantir la lisibilité du texte et des contrôles
                ZStack {
                    Color.black.opacity(0.28)

                    LinearGradient(
                        stops: [
                            .init(color: Color.black.opacity(0.32), location: 0.0),
                            .init(color: Color.black.opacity(0.12), location: 0.38),
                            .init(color: Color.black.opacity(0.42), location: 0.72),
                            .init(color: Color.black.opacity(0.68), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.38),
                            Color.black.opacity(0.12),
                            Color.black.opacity(0.22)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
                .allowsHitTesting(false)

                // 3. Contenu structuré en 3 rangées (Haut : Plateforme, Milieu : Titre & Play/Pause, Bas : Transport & Ligne droite)
                VStack(alignment: .leading, spacing: 0) {
                    // Rangée supérieure : Icône de la plateforme utilisée à gauche + Icône casque en blanc à droite
                    HStack(alignment: .center) {
                        Button {
                            musicManager.openMusicApp()
                        } label: {
                            activePlatformBadge(size: isCompact ? 20 : 24)
                        }
                        .buttonStyle(MediaPressButtonStyle())

                        Spacer()

                        Button {
                            musicManager.openMusicApp()
                        } label: {
                            Image(systemName: "headphones")
                                .font(.system(size: isCompact ? 13 : 15, weight: .bold))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(MediaPressButtonStyle())
                        .help(activePlatformDisplayName)
                    }

                    Spacer(minLength: isCompact ? 4 : 8)

                    // Rangée centrale : Titre + Artiste à gauche, Bouton Play/Pause en blanc à droite (sans carré blanc)
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: isCompact ? 1.5 : 3) {
                            Text(displayTitle)
                                .font(.system(size: isCompact ? 15 : 18.5, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .shadow(color: .black.opacity(0.50), radius: 5, y: 1.5)

                            Text(displayArtist)
                                .font(.system(size: isCompact ? 11.5 : 13.5, weight: .medium))
                                .foregroundStyle(.white.opacity(0.90))
                                .lineLimit(1)
                                .shadow(color: .black.opacity(0.45), radius: 4, y: 1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // Bouton Play/Pause en blanc sans fond carré
                        Button {
                            if track.hasTrack {
                                musicManager.togglePlayPause()
                            } else {
                                musicManager.playRandomMusic()
                            }
                        } label: {
                            Image(systemName: track.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: isCompact ? 20 : 24, weight: .bold))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.45), radius: 4, y: 1.5)
                                .frame(width: isCompact ? 34 : 40, height: isCompact ? 34 : 40)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(MediaPressButtonStyle())
                        .help(loc(track.isPlaying ? "music.control.pause" : "music.control.play"))
                    }

                    Spacer(minLength: isCompact ? 6 : 10)

                    // Rangée inférieure : Précédent, Barre de progression en ligne droite, Suivant, Aléatoire (sans rond blanc)
                    HStack(alignment: .center, spacing: isCompact ? 10 : 14) {
                        Button {
                            if track.hasTrack {
                                musicManager.previousTrack()
                            } else {
                                musicManager.previousSystemTrack()
                            }
                        } label: {
                            Image(systemName: "backward.end.fill")
                                .font(.system(size: isCompact ? 12.5 : 14.5, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.95))
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(MediaPressButtonStyle())
                        .help(loc("music.control.previous"))

                        SeekBar(
                            elapsed: track.hasTrack ? track.elapsedSeconds : Double(config.musicElapsedSeconds),
                            duration: track.hasTrack ? track.durationSeconds : Double(max(1, config.musicTotalSeconds)),
                            trackColor: Color.white.opacity(0.35),
                            fillColor: Color.white,
                            barHeight: isCompact ? 2.5 : 3.0,
                            isEnabled: track.hasTrack
                        ) { fraction in
                            musicManager.seek(toFraction: fraction)
                        }
                        .frame(maxWidth: .infinity)

                        Button {
                            if track.hasTrack {
                                musicManager.nextTrack()
                            } else {
                                musicManager.nextSystemTrack()
                            }
                        } label: {
                            Image(systemName: "forward.end.fill")
                                .font(.system(size: isCompact ? 12.5 : 14.5, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.95))
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(MediaPressButtonStyle())
                        .help(loc("music.control.next"))

                        Button {
                            musicManager.playRandomMusic()
                        } label: {
                            Image(systemName: "shuffle")
                                .font(.system(size: isCompact ? 12.5 : 14.5, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.95))
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(MediaPressButtonStyle())
                        .help(loc("music.widget.open_app"))
                    }
                }
                .padding(.horizontal, horizontalPad)
                .padding(.vertical, verticalPad)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    // MARK: - État Lisible sans lecture
    private var emptyStateView: some View {
        GeometryReader { geo in
            let isCompact = geo.size.height < 175 || geo.size.width < 175
            let isUltraDense = geo.size.height < 98
            let showIcon = geo.size.height >= 76
            VStack(spacing: isUltraDense ? 3 : (isCompact ? 5 : 8)) {
                if showIcon {
                    Button {
                        musicManager.playRandomMusic()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.10))
                                .frame(width: isUltraDense ? 28 : (isCompact ? 36 : 46),
                                       height: isUltraDense ? 28 : (isCompact ? 36 : 46))
                            Image(systemName: "music.note")
                                .font(.system(size: isUltraDense ? 12 : (isCompact ? 15 : 19), weight: .semibold))
                                .foregroundStyle(.white.opacity(0.88))
                        }
                    }
                    .buttonStyle(.plain)
                }

                Text(loc("music.widget.no_track"))
                    .font(.system(size: isUltraDense ? 10.5 : (isCompact ? 11.5 : 13), weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if !isCompact {
                    Text(loc("music.widget.connect_hint"))
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(.white.opacity(0.60))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)
                }

                // Contrôles système disponibles même quand aucune métadonnée n'est publiée.
                if !isCompact {
                    HStack(spacing: 14) {
                        MediaControlButton(
                            systemName: "backward.fill",
                            iconSize: 11.5,
                            frameSize: 30,
                            help: loc("music.control.previous")
                        ) {
                            musicManager.previousSystemTrack()
                        }

                        MediaControlButton(
                            systemName: "play.fill",
                            iconSize: 12.5,
                            frameSize: 34,
                            isPrimary: true,
                            help: loc("music.control.play")
                        ) {
                            musicManager.playRandomMusic()
                        }

                        MediaControlButton(
                            systemName: "forward.fill",
                            iconSize: 11.5,
                            frameSize: 30,
                            help: loc("music.control.next")
                        ) {
                            musicManager.nextSystemTrack()
                        }
                    }
                }

                Button {
                    musicManager.playRandomMusic()
                } label: {
                    HStack(spacing: 5) {
                        if musicManager.isLaunchingRandomTrack {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "shuffle.circle.fill")
                                .font(.system(size: isUltraDense ? 9.5 : (isCompact ? 10.5 : 12)))
                        }
                        Text(loc("music.widget.open_app"))
                            .font(.system(size: isUltraDense ? 9.5 : (isCompact ? 10 : 11), weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, isUltraDense ? 8 : (isCompact ? 10 : 14))
                    .padding(.vertical, isUltraDense ? 3.5 : (isCompact ? 4.5 : 6))
                    .background(Capsule().fill(Color.white.opacity(0.18)))
                }
                .buttonStyle(.plain)
                .padding(.top, isUltraDense ? 0 : (isCompact ? 2 : 4))
            }
            .padding(isUltraDense ? 6 : (isCompact ? 8 : 12))
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
        }
    }

    @ViewBuilder
    private var serviceBadgeIcon: some View {
        if track.serviceSource == .spotify {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color(red: 0.12, green: 0.84, blue: 0.38))
                .help("Spotify")
        } else if track.serviceSource == .appleMusic {
            Image(systemName: "apple.logo")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.pink)
                .help("Apple Music")
        } else if track.serviceSource == .system {
            Image(systemName: track.sourceBundleID.isEmpty ? "play.rectangle.fill" : "play.circle.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.85))
                .help(track.sourceAppName)
        }
    }

    private func formatSeconds(_ s: Int) -> String {
        let m = max(0, s) / 60
        let sec = max(0, s) % 60
        return String(format: "%d:%02d", m, sec)
    }
}

// MARK: - 6. Widget Horloge & Date (Small & Medium)

struct ClockWidgetView: View {
    let config: CustomWidgetConfig
    var targetSize: CGSize? = nil
    @State private var currentDate = Date()
    @State private var timer: AnyCancellable?

    var body: some View {
        WidgetContainerView(size: config.size, targetSize: targetSize) {
            if config.size == .medium {
                mediumClockView
            } else {
                smallClockView
            }
        }
        .onAppear {
            currentDate = Date()
            startTimer()
        }
        .onDisappear {
            stopTimer()
        }
        .onReceive(NotificationCenter.default.publisher(for: .launchpadVisibilityDidChange)) { notif in
            let isVisible = (notif.object as? Bool) ?? false
            if isVisible {
                currentDate = Date()
                startTimer()
            } else {
                stopTimer()
            }
        }
    }

    private func startTimer() {
        guard timer == nil, LaunchpadViewModel.isLaunchpadVisible else { return }
        let isMedium = (config.size == .medium)
        // Le petit format n'affiche que les heures et minutes (sans secondes) : un rafraîchissement toutes les 15s suffit,
        // et on ne met à jour @State currentDate que lorsque la minute affichée change réellement.
        let interval: TimeInterval = isMedium ? 1.0 : 15.0
        let tolerance: TimeInterval = isMedium ? 0.25 : 3.0
        timer = Timer.publish(every: interval, tolerance: tolerance, on: .main, in: .common)
            .autoconnect()
            .sink { [self] date in
                guard LaunchpadViewModel.isLaunchpadVisible else { return }
                if isMedium {
                    self.currentDate = date
                } else {
                    let cal = Calendar.current
                    if cal.component(.minute, from: date) != cal.component(.minute, from: self.currentDate) ||
                       cal.component(.hour, from: date) != cal.component(.hour, from: self.currentDate) {
                        self.currentDate = date
                    }
                }
            }
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    // MARK: - Petit Format (1x1 ou 180x180) - Digital Épuré Apple Style
    private var smallClockView: some View {
        GeometryReader { geo in
            let isCompact = geo.size.height < 175 || geo.size.width < 175
            let timeFontSize: CGFloat = isCompact ? 30 : 40
            let pad: CGFloat = isCompact ? 12 : 16
            let greetingSize: CGFloat = isCompact ? 9.5 : 11
            let dateSize: CGFloat = isCompact ? 10 : 11.5

            VStack(alignment: .leading, spacing: 0) {
                // Pilule de salutation avec icône
                HStack(spacing: 4) {
                    Image(systemName: greetingIcon)
                        .font(.system(size: greetingSize, weight: .semibold))
                        .foregroundStyle(greetingColor)
                    Text(greetingText)
                        .font(.system(size: greetingSize, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
                .padding(.horizontal, isCompact ? 7 : 8)
                .padding(.vertical, isCompact ? 3 : 4)
                .background(Capsule().fill(Color.white.opacity(0.10)))

                Spacer(minLength: 2)

                // Grande Heure Digitale
                Text(formattedTime)
                    .font(.system(size: timeFontSize, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 2)

                // Date complète
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: dateSize))
                        .foregroundStyle(Color.red.opacity(0.9))
                    Text(formattedDate)
                        .font(.system(size: dateSize, weight: .medium))
                        .foregroundStyle(.white.opacity(0.70))
                        .lineLimit(1)
                }
            }
            .padding(pad)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
    }

    // MARK: - Format Moyen (2x1) - Double Vue Cadran Analogique + Digital
    private var mediumClockView: some View {
        GeometryReader { geo in
            let isCompact = geo.size.height < 120 || geo.size.width < 250
            let clockSize: CGFloat = isCompact ? 54 : 80
            HStack(spacing: isCompact ? 8 : 14) {
                // Côté Gauche : Véritable Cadran Analogique
                AnalogClockFace(date: currentDate, size: clockSize)
                    .padding(.leading, isCompact ? 4 : 8)

                // Côté Droit : Heure Digitale + Date & Calendrier
                VStack(alignment: .leading, spacing: isCompact ? 2 : 4) {
                    // Salutation
                    HStack(spacing: 4) {
                        Image(systemName: greetingIcon)
                            .font(.system(size: isCompact ? 8.5 : 10.5, weight: .semibold))
                            .foregroundStyle(greetingColor)
                        Text(greetingText)
                            .font(.system(size: isCompact ? 9.5 : 11.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.90))
                            .lineLimit(1)
                    }

                    // Heure digitale avec secondes
                    Text(formattedTimeWithSeconds)
                        .font(.system(size: isCompact ? 20 : 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    // Vignette Calendrier Apple Style + Date
                    HStack(spacing: isCompact ? 6 : 8) {
                        // Icône de calendrier
                        VStack(spacing: 0) {
                            Text(currentMonthShort)
                                .font(.system(size: isCompact ? 6 : 7.5, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 1)
                                .background(Color.red)
                            Text(currentDayNumber)
                                .font(.system(size: isCompact ? 10 : 12.5, weight: .bold, design: .rounded))
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.white)
                        }
                        .frame(width: isCompact ? 22 : 28, height: isCompact ? 24 : 30)
                        .clipShape(RoundedRectangle(cornerRadius: isCompact ? 4.5 : 6, style: .continuous))
                        .shadow(color: .black.opacity(0.25), radius: 2.5, y: 1)

                        VStack(alignment: .leading, spacing: 0.5) {
                            Text(loc("widget.clock.today"))
                                .font(.system(size: isCompact ? 7.5 : 9.5, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.60))
                                .textCase(.uppercase)
                            Text(formattedDate)
                                .font(.system(size: isCompact ? 9.5 : 11.5, weight: .medium))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }
                    }
                    .padding(.top, 1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, isCompact ? 6 : 12)
            }
            .padding(.vertical, isCompact ? 6 : 10)
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    @MainActor
    private static let time24Formatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt
    }()

    @MainActor
    private static let time12Formatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "h:mm a"
        return fmt
    }()

    @MainActor
    private static let time24SecFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        return fmt
    }()

    @MainActor
    private static let time12SecFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "h:mm:ss a"
        return fmt
    }()

    @MainActor
    private static let mediumDateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .none
        return fmt
    }()

    @MainActor
    private static let shortMonthFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM"
        return fmt
    }()

    private static let cachedUserFirstName: String = {
        let first = NSFullUserName().components(separatedBy: " ").first ?? ""
        return (first.isEmpty || first == "root") ? "" : first
    }()

    private var formattedTime: String {
        let fmt = config.clockFormat24h ? Self.time24Formatter : Self.time12Formatter
        return fmt.string(from: currentDate)
    }

    private var formattedTimeWithSeconds: String {
        let fmt = config.clockFormat24h ? Self.time24SecFormatter : Self.time12SecFormatter
        return fmt.string(from: currentDate)
    }

    private var formattedDate: String {
        let fmt = Self.mediumDateFormatter
        let locale = LocalizationManager.shared.effectiveLocale
        if fmt.locale != locale { fmt.locale = locale }
        return fmt.string(from: currentDate).capitalized
    }

    private var currentMonthShort: String {
        let fmt = Self.shortMonthFormatter
        let locale = LocalizationManager.shared.effectiveLocale
        if fmt.locale != locale { fmt.locale = locale }
        return fmt.string(from: currentDate).uppercased()
    }

    private var currentDayNumber: String {
        let cal = Calendar.current
        return "\(cal.component(.day, from: currentDate))"
    }

    private var greetingIcon: String {
        let hour = Calendar.current.component(.hour, from: currentDate)
        if hour < 12 { return "sun.max.fill" }
        if hour < 18 { return "sun.haze.fill" }
        return "moon.stars.fill"
    }

    private var greetingColor: Color {
        let hour = Calendar.current.component(.hour, from: currentDate)
        if hour < 12 { return Color.yellow }
        if hour < 18 { return Color.orange }
        return Color(red: 0.70, green: 0.60, blue: 1.0)
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: currentDate)
        let greet = hour < 12 ? loc("widgets.greeting_morning") : (hour < 18 ? loc("widgets.greeting_afternoon") : loc("widgets.greeting_evening"))
        let user = Self.cachedUserFirstName
        return user.isEmpty ? greet : "\(greet), \(user)"
    }
}

// MARK: - 7. Widget Moniteur Système (Small & Medium)

struct SystemWidgetView: View {
    let config: CustomWidgetConfig
    var targetSize: CGSize? = nil
    @ObservedObject private var stats = SystemStatsMonitor.shared
    @ObservedObject private var widgetManager = WidgetManager.shared

    var body: some View {
        WidgetContainerView(size: config.size, targetSize: targetSize) {
            if config.size == .medium {
                mediumSystemView
            } else {
                smallSystemView
            }
        }
        .onAppear { stats.startMonitoring() }
        .onDisappear { stats.stopMonitoring() }
    }

    // MARK: - Format Carré / Petit (1x1 ou 180x180) - Double Anneaux d'Activité
    private var smallSystemView: some View {
        GeometryReader { geo in
            let isCompact = geo.size.height < 175 || geo.size.width < 175
            let ringSize: CGFloat = isCompact ? 50 : 64
            let ringSpacing: CGFloat = isCompact ? 10 : 16
            let pad: CGFloat = isCompact ? 10 : 14

            VStack(spacing: isCompact ? 8 : 12) {
                // Anneaux CPU et RAM côte à côte
                HStack(spacing: ringSpacing) {
                    CircularRingGauge(
                        progress: Double(stats.cpuPercent) / 100.0,
                        gradient: LinearGradient(colors: [Color.cyan, Color.blue], startPoint: .topLeading, endPoint: .bottomTrailing),
                        icon: "cpu",
                        value: "\(stats.cpuPercent)%",
                        label: loc("widget.system.processor"),
                        size: ringSize
                    )

                    CircularRingGauge(
                        progress: Double(stats.ramPercent) / 100.0,
                        gradient: LinearGradient(colors: [Color(red: 0.75, green: 0.45, blue: 1.0), Color.purple], startPoint: .topLeading, endPoint: .bottomTrailing),
                        icon: "memorychip",
                        value: String(format: "%.1f", stats.ramUsedGB),
                        label: "RAM Go",
                        size: ringSize
                    )
                }
                .padding(.top, isCompact ? 2 : 4)

                // Pilule d'Énergie / Batterie en bas
                if stats.hasBattery {
                    HStack(spacing: isCompact ? 4 : 6) {
                        Image(systemName: stats.isCharging ? "battery.100.bolt" : "battery.100")
                            .font(.system(size: isCompact ? 9.5 : 11, weight: .semibold))
                            .foregroundStyle(stats.batteryPercent < 20 ? Color.red : (stats.isCharging ? Color.yellow : Color.green))

                        Text("\(stats.batteryPercent)%")
                            .font(.system(size: isCompact ? 9.5 : 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .monospacedDigit()

                        Text("•")
                            .font(.system(size: 7))
                            .foregroundStyle(.white.opacity(0.35))

                        Text(stats.isCharging ? loc("widget.system.charging") : loc("widget.system.on_battery"))
                            .font(.system(size: isCompact ? 8.5 : 9.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, isCompact ? 8 : 10)
                    .padding(.vertical, isCompact ? 3.5 : 4.5)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6))
                }
            }
            .padding(pad)
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    // MARK: - Format Moyen (2x1) - Triptyque Télémétrique
    private var mediumSystemView: some View {
        GeometryReader { geo in
            let isCompact = geo.size.height < 120 || geo.size.width < 250
            let ringSize: CGFloat = isCompact ? 34 : 52
            HStack(spacing: isCompact ? 4 : 8) {
                // Pod 1 : Processeur
                telemetryPod(
                    ring: CircularRingGauge(
                        progress: Double(stats.cpuPercent) / 100.0,
                        gradient: LinearGradient(colors: [Color.cyan, Color.blue], startPoint: .topLeading, endPoint: .bottomTrailing),
                        icon: "cpu",
                        value: "\(stats.cpuPercent)%",
                        label: loc("widget.system.processor"),
                        size: ringSize
                    ),
                    subtitle: "\(stats.cpuPercent < 40 ? "Charge normale" : "Activité élevée")",
                    isCompact: isCompact
                )

                // Pod 2 : RAM
                telemetryPod(
                    ring: CircularRingGauge(
                        progress: Double(stats.ramPercent) / 100.0,
                        gradient: LinearGradient(colors: [Color(red: 0.75, green: 0.45, blue: 1.0), Color.purple], startPoint: .topLeading, endPoint: .bottomTrailing),
                        icon: "memorychip",
                        value: "\(stats.ramPercent)%",
                        label: loc("widget.system.memory"),
                        size: ringSize
                    ),
                    subtitle: String(format: "%.1f / %.0f Go", stats.ramUsedGB, stats.ramTotalGB > 0 ? stats.ramTotalGB : 16),
                    isCompact: isCompact
                )

                // Pod 3 : Énergie & Batterie
                telemetryPod(
                    ring: CircularRingGauge(
                        progress: Double(stats.batteryPercent) / 100.0,
                        gradient: LinearGradient(
                            colors: stats.batteryPercent < 20
                                ? [Color.red, Color.orange]
                                : [Color.green, Color(red: 0.20, green: 0.85, blue: 0.50)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        icon: stats.isCharging ? "bolt.fill" : "battery.100",
                        value: "\(stats.batteryPercent)%",
                        label: loc("widget.system.energy"),
                        size: ringSize
                    ),
                    subtitle: stats.isCharging ? loc("widget.system.charging") : (stats.hasBattery ? loc("widget.system.on_battery") : loc("widget.system.on_power")),
                    isCompact: isCompact
                )
            }
            .padding(isCompact ? 5 : 10)
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func telemetryPod(ring: CircularRingGauge, subtitle: String, isCompact: Bool = false) -> some View {
        VStack(spacing: isCompact ? 1.5 : 3) {
            ring
            Text(subtitle)
                .font(.system(size: isCompact ? 7.5 : 9.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, isCompact ? 3 : 6)
        .background(
            RoundedRectangle(cornerRadius: isCompact ? 8 : 12, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: isCompact ? 8 : 12, style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 0.8))
        )
    }
}

// MARK: - 8. Widget Note Rapide (Small & Medium)

struct QuickNoteWidgetView: View {
    let config: CustomWidgetConfig
    var targetSize: CGSize? = nil
    @AppStorage(PrefKey.widgetQuickNoteText) private var noteText = ""
    @State private var showCopiedCheckmark = false

    var body: some View {
        WidgetContainerView(size: config.size, targetSize: targetSize, isPureTranslucent: true) {
            GeometryReader { geo in
                let isCompact = geo.size.height < 175 || geo.size.width < 175
                VStack(alignment: .leading, spacing: isCompact ? 5 : 8) {
                    // En-tête : Style Apple Notes sur fond blanc soyeux
                    HStack(spacing: isCompact ? 6 : 8) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [Color.yellow, Color.orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: isCompact ? 20 : 24, height: isCompact ? 20 : 24)
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: isCompact ? 9.5 : 11, weight: .bold))
                                .foregroundStyle(.black)
                        }

                        Text(loc("widget.quickNote.title"))
                            .font(.system(size: isCompact ? 11.5 : 12.5, weight: .bold))
                            .foregroundStyle(.white)

                        Spacer()

                        // Bouton Copier
                        if !noteText.isEmpty {
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(noteText, forType: .string)
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                    showCopiedCheckmark = true
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    withAnimation { showCopiedCheckmark = false }
                                }
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: showCopiedCheckmark ? "checkmark" : "doc.on.doc")
                                        .font(.system(size: isCompact ? 9 : 10, weight: .semibold))
                                    if showCopiedCheckmark {
                                        Text(loc("widget.quickNote.copied"))
                                            .font(.system(size: isCompact ? 8.5 : 9.5, weight: .bold))
                                    }
                                }
                                .foregroundStyle(showCopiedCheckmark ? Color.green : Color.white.opacity(0.85))
                                .padding(.horizontal, isCompact ? 6 : 7)
                                .padding(.vertical, isCompact ? 2.5 : 3.5)
                                .background(Capsule().fill(Color.white.opacity(0.12)))
                            }
                            .buttonStyle(.plain)

                            // Bouton Effacer
                            Button {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    noteText = ""
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: isCompact ? 11 : 12))
                                    .foregroundStyle(Color.white.opacity(0.65))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Zone de saisie
                    ZStack(alignment: .topLeading) {
                        if noteText.isEmpty {
                            Text(loc("widget.quickNote.placeholder"))
                                .font(.system(size: isCompact ? 11 : 12, weight: .regular))
                                .foregroundStyle(Color.white.opacity(0.55))
                                .padding(.top, 4)
                                .padding(.leading, 3)
                                .allowsHitTesting(false)
                        }

                        TextEditor(text: $noteText)
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .font(.system(size: isCompact ? 11.5 : 12.5))
                            .foregroundStyle(.white)
                            .lineSpacing(isCompact ? 2 : 3)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Pied de carte : Compteur
                    if !noteText.isEmpty {
                        HStack {
                            Spacer()
                            Text("\(noteText.count) car.")
                                .font(.system(size: isCompact ? 8.5 : 9.5, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.65))
                        }
                    }
                }
                .padding(isCompact ? 10 : 14)
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }
}

// MARK: - 9. Hôte Universel de Widget

struct WidgetHostView: View, Equatable {
    let config: CustomWidgetConfig
    var targetSize: CGSize? = nil

    static func == (lhs: WidgetHostView, rhs: WidgetHostView) -> Bool {
        lhs.config == rhs.config && lhs.targetSize == rhs.targetSize
    }

    var body: some View {
        switch config.kind {
        case .vinylPlayer:
            VinylPlayerWidgetView(config: config, targetSize: targetSize)
        case .weather:
            WeatherWidgetView(config: config, targetSize: targetSize)
        case .mediaWide:
            MediaWideWidgetView(config: config, targetSize: targetSize)
        case .clock:
            ClockWidgetView(config: config, targetSize: targetSize)
        case .system:
            SystemWidgetView(config: config, targetSize: targetSize)
        case .quickNote:
            QuickNoteWidgetView(config: config, targetSize: targetSize)
        }
    }
}
