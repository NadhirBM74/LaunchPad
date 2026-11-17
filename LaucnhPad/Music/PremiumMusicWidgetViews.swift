import SwiftUI
import AppKit
import Combine

// MARK: - Styles de Widgets de Musique (Fidèles à la Photo de Référence 3)

public enum MusicWidgetStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case fullBleedPill = "fullBleedPill"         // Pochette plein écran + pilule sombre en haut (Photo 3 Bas-Gauche, Bas-Milieu, Bas-Droite)
    case vinylSplatterWide = "vinylSplatterWide" // Vinyle marbré/splatter + carte givrée claire (Photo 3 Haut-Gauche & Haut-Droite)
    case vinylWhiteGrooved = "vinylWhiteGrooved" // Vinyle blanc microsillon + carte claire (Photo 3 Col 2 Haut)
    case framedEditorial = "framedEditorial"     // Pochette encadrée sur carte claire givrée (Photo 3 Col 3 Haut & Bas, Bas-Droite-Bas)
    case classicTurntable = "classicTurntable"   // Platine vinyle classique avec bras de lecture
    case adaptiveGlass = "adaptiveGlass"         // Liquid Glass teinté par la pochette d'album

    public var id: String { rawValue }

    public var title: String {
        loc("music_style.\(rawValue)")
    }
}

// MARK: - Suivi Fluide de Rotation du Disque Vinyle

@MainActor
final class MusicVinylRotationTracker {
    var angle: Double = 0
    var lastDate: Date? = nil
    let speedDegreesPerSecond: Double = 22.0

    func advance(to date: Date, isSpinning: Bool) -> Double {
        guard isSpinning else {
            lastDate = nil
            return angle
        }
        if let last = lastDate {
            let dt = min(max(0, date.timeIntervalSince(last)), 0.1)
            angle = (angle + dt * speedDegreesPerSecond).truncatingRemainder(dividingBy: 360.0)
        }
        lastDate = date
        return angle
    }

    func reset() {
        lastDate = nil
    }
}

// MARK: - Disques Vinyles Haute Fidélité (Marbré Cyan Splatter & Blanc Microsillon)

struct ReferenceVinylDiscView: View, Equatable {
    enum DiscVariant {
        case cyanSplatter // Photo 3 Haut-Gauche & Haut-Droite : Vinyle marbré bleu/cyan/blanc
        case whiteGrooved // Photo 3 Col 2 Haut : Vinyle blanc/argenté microsillon
        case classicBlack // Vinyle noir classique
    }

    let size: CGFloat
    let variant: DiscVariant
    let artwork: NSImage?

    static func == (lhs: ReferenceVinylDiscView, rhs: ReferenceVinylDiscView) -> Bool {
        lhs.size == rhs.size && lhs.variant == rhs.variant && lhs.artwork === rhs.artwork
    }

    var body: some View {
        let labelSize = size * 0.36

        ZStack {
            switch variant {
            case .cyanSplatter:
                cyanSplatterDiscBase
            case .whiteGrooved:
                whiteGroovedDiscBase
            case .classicBlack:
                blackGroovedDiscBase
            }

            // Sillons concentriques subtils
            ForEach([0.06, 0.12, 0.18, 0.24, 0.29], id: \.self) { ratio in
                Circle()
                    .strokeBorder(
                        variant == .classicBlack
                            ? Color.white.opacity(0.08)
                            : Color.black.opacity(0.06),
                        lineWidth: 0.65
                    )
                    .padding(size * CGFloat(ratio))
            }

            // Reflet spéculaire diagonal de rotation
            Circle()
                .fill(
                    AngularGradient(
                        gradient: Gradient(stops: [
                            .init(color: .clear, location: 0.00),
                            .init(color: .white.opacity(variant == .whiteGrooved ? 0.45 : 0.22), location: 0.12),
                            .init(color: .clear, location: 0.25),
                            .init(color: .black.opacity(0.08), location: 0.38),
                            .init(color: .clear, location: 0.50),
                            .init(color: .white.opacity(variant == .whiteGrooved ? 0.45 : 0.22), location: 0.62),
                            .init(color: .clear, location: 0.75),
                            .init(color: .black.opacity(0.08), location: 0.88),
                            .init(color: .clear, location: 1.00)
                        ]),
                        center: .center,
                        angle: .degrees(-35)
                    )
                )
                .frame(width: size, height: size)

            // Macaron central : Pochette de l'album (Red Velvet ou piste en cours)
            ZStack {
                if let artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .frame(width: labelSize, height: labelSize)
                        .clipShape(Circle())
                } else {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: variant == .classicBlack
                                        ? [Color(red: 0.22, green: 0.24, blue: 0.30), Color(red: 0.10, green: 0.11, blue: 0.15)]
                                        : [Color(red: 0.18, green: 0.52, blue: 0.88), Color(red: 0.08, green: 0.28, blue: 0.62)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Image(systemName: "music.note")
                            .font(.system(size: max(10, labelSize * 0.38), weight: .bold))
                            .foregroundStyle(.white.opacity(0.92))
                    }
                    .frame(width: labelSize, height: labelSize)
                    .clipShape(Circle())
                }
            }
            .overlay(
                Circle()
                    .strokeBorder(Color.white.opacity(0.55), lineWidth: 1.0)
            )
            .shadow(color: .black.opacity(0.22), radius: 3)
        }
        .frame(width: size, height: size)
        .overlay(
            Circle()
                .strokeBorder(
                    variant == .classicBlack ? Color.white.opacity(0.20) : Color.white.opacity(0.65),
                    lineWidth: 0.9
                )
        )
        .drawingGroup()
    }

    private var cyanSplatterDiscBase: some View {
        ZStack {
            // Base blanche/glace translucide
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.25, green: 0.68, blue: 0.88),
                            Color(red: 0.78, green: 0.88, blue: 0.95),
                            Color(red: 0.92, green: 0.95, blue: 0.98)
                        ],
                        center: .center,
                        startRadius: size * 0.14,
                        endRadius: size * 0.50
                    )
                )

            // Halo central turquoise marbré (comme sur la Photo 3 Haut-Droite)
            Circle()
                .fill(
                    AngularGradient(
                        colors: [
                            Color(red: 0.22, green: 0.68, blue: 0.90).opacity(0.85),
                            Color(red: 0.52, green: 0.82, blue: 0.96).opacity(0.65),
                            Color(red: 0.18, green: 0.56, blue: 0.82).opacity(0.90),
                            Color(red: 0.68, green: 0.88, blue: 0.96).opacity(0.70),
                            Color(red: 0.22, green: 0.68, blue: 0.90).opacity(0.85)
                        ],
                        center: .center
                    )
                )
                .frame(width: size * 0.72, height: size * 0.72)
                .blur(radius: size * 0.03)

            // Rayons splatter radiaux (éclaboussures bleues et anthracite sur vinyle)
            ForEach(0..<24, id: \.self) { i in
                let angle = Double(i) * 15.0 + Double((i % 3) * 4)
                let len = size * (i % 2 == 0 ? 0.16 : 0.10)
                let dist = size * (i % 3 == 0 ? 0.36 : 0.28)
                Capsule()
                    .fill(
                        i % 4 == 0
                            ? Color(red: 0.22, green: 0.24, blue: 0.32).opacity(0.55)
                            : Color(red: 0.14, green: 0.58, blue: 0.86).opacity(0.65)
                    )
                    .frame(width: max(1.5, size * 0.016), height: len)
                    .offset(y: -dist)
                    .rotationEffect(.degrees(angle))
            }
        }
    }

    private var whiteGroovedDiscBase: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.93, green: 0.94, blue: 0.95),
                            Color(red: 0.86, green: 0.87, blue: 0.89),
                            Color(red: 0.95, green: 0.96, blue: 0.97)
                        ],
                        center: .center,
                        startRadius: size * 0.15,
                        endRadius: size * 0.50
                    )
                )
        }
    }

    private var blackGroovedDiscBase: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color(white: 0.14),
                        Color(white: 0.06),
                        Color(white: 0.11),
                        Color(white: 0.04)
                    ],
                    center: .center,
                    startRadius: size * 0.15,
                    endRadius: size * 0.50
                )
            )
    }
}

// MARK: - Composant Principal Unifié des Widgets de Musique (Photo de Référence 3)

struct ReferenceMusicWidgetView: View {
    let config: CustomWidgetConfig
    var targetSize: CGSize? = nil
    var isPreview: Bool = false

    @ObservedObject private var musicManager = MusicServiceManager.shared
    @ObservedObject private var widgetManager = WidgetManager.shared
    @ObservedObject private var locManager = LocalizationManager.shared
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage(PrefKey.reduceMotion) private var userReduceMotion = false

    @State private var spinTracker = MusicVinylRotationTracker()
    @State private var discBounceScale: CGFloat = 1.0
    @State private var extraDiscRotation: Double = 0
    @State private var bounceTask: Task<Void, Never>?
    @State private var isWindowVisible: Bool = LaunchpadViewModel.isLaunchpadVisible || ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"

    private var reduceMotion: Bool { userReduceMotion || systemReduceMotion }

    private var track: NowPlayingTrack {
        musicManager.currentTrack
    }

    /// Titre affiché (Morceau réel en cours, sinon "Red Velvet" comme sur la Photo de Référence 3)
    private var displayTitle: String {
        if track.hasTrack && !track.title.isEmpty {
            return track.title
        }
        if !config.musicTrack.isEmpty && config.musicTrack != "Supercut" && config.musicTrack != "Past Alone" {
            return config.musicTrack
        }
        return "Red Velvet"
    }

    /// Artiste affiché (Artiste réel en cours, sinon "Past Alone" comme sur la Photo de Référence 3)
    private var displayArtist: String {
        if track.hasTrack && !track.artist.isEmpty {
            return track.artist
        }
        if !config.musicArtist.isEmpty && config.musicArtist != "Lorde" && config.musicArtist != "Red Velvet" {
            return config.musicArtist
        }
        return "Past Alone"
    }

    /// Album affiché (Album réel en cours, sinon "Water (Deluxe)" comme sur la Photo de Référence 3)
    private var displayAlbum: String {
        if track.hasTrack && !track.album.isEmpty {
            return track.album
        }
        if !config.musicAlbum.isEmpty && config.musicAlbum != "Melodrama" {
            return config.musicAlbum
        }
        return "Water (Deluxe)"
    }

    private var isPlaying: Bool {
        if track.hasTrack { return track.isPlaying }
        if let live = widgetManager.widgets.first(where: { $0.id == config.id }) {
            return live.musicIsPlaying
        }
        return config.musicIsPlaying
    }

    private var elapsedSeconds: Double {
        if track.hasTrack { return track.elapsedSeconds }
        return 80 // 1:20 comme sur la Photo 3
    }

    private var durationSeconds: Double {
        if track.hasTrack && track.durationSeconds > 0 { return track.durationSeconds }
        return 147 // 2:27 comme sur la Photo 3
    }

    private var isSpinning: Bool {
        isPlaying && !reduceMotion && isWindowVisible && !isPreview
    }

    private var isDarkMusic: Bool {
        config.musicAppearance == .dark
    }

    private var cardTitleColor: Color {
        isDarkMusic ? Color.white.opacity(0.96) : Color(white: 0.06)
    }

    private var cardSubtitleColor: Color {
        isDarkMusic ? Color.white.opacity(0.70) : Color(white: 0.28)
    }

    private var cardTimestampColor: Color {
        isDarkMusic ? Color.white.opacity(0.78) : Color(white: 0.16)
    }

    private var cardControlColor: Color {
        isDarkMusic ? Color.white.opacity(0.95) : Color(white: 0.06)
    }

    private var cardSeekTrackColor: Color {
        isDarkMusic ? Color.white.opacity(0.20) : Color.black.opacity(0.16)
    }

    private var cardSeekFillColor: Color {
        isDarkMusic ? Color.white.opacity(0.92) : Color(white: 0.08)
    }

    var body: some View {
        let w = targetSize?.width ?? config.size.width
        let h = targetSize?.height ?? config.size.height
        let cornerRadius = widgetManager.cornerRadius

        GeometryReader { geo in
            let availW = geo.size.width
            let availH = geo.size.height

            ZStack {
                if !isPreview && !track.hasTrack {
                    emptyLaunchMusicView(width: availW, height: availH)
                } else {
                    switch config.musicStyle {
                    case .fullBleedPill:
                        fullBleedPillLayout(width: availW, height: availH)

                    case .vinylSplatterWide:
                        vinylSplatterLayout(width: availW, height: availH)

                    case .vinylWhiteGrooved:
                        vinylWhiteGroovedLayout(width: availW, height: availH)

                    case .framedEditorial:
                        framedEditorialLayout(width: availW, height: availH)

                    case .classicTurntable, .adaptiveGlass:
                        vinylSplatterLayout(width: availW, height: availH)
                    }
                }
            }
            .frame(width: availW, height: availH)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: isDarkMusic
                                ? [
                                    Color.white.opacity(0.65),
                                    Color.white.opacity(0.18),
                                    Color.white.opacity(0.32)
                                ]
                                : [
                                    Color.white.opacity(0.85),
                                    Color.black.opacity(0.08),
                                    Color.black.opacity(0.12)
                                ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.0
                    )
            )
            .shadow(color: .black.opacity(isDarkMusic ? 0.28 : 0.16), radius: 14, x: 0, y: 7)
        }
        .frame(width: w, height: h)
        .environment(\.colorScheme, isDarkMusic ? .dark : .light)
        .onAppear {
            if !isPreview {
                musicManager.refreshNowPlaying()
            }
            if LaunchpadViewModel.isLaunchpadVisible {
                isWindowVisible = true
            }
        }
        .onDisappear {
            spinTracker.reset()
            bounceTask?.cancel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .launchpadVisibilityDidChange)) { notif in
            guard let visible = notif.object as? Bool else { return }
            isWindowVisible = visible
            if !visible { spinTracker.reset() }
        }
    }

    @ViewBuilder
    private func emptyLaunchMusicView(width: CGFloat, height: CGFloat) -> some View {
        let platform = musicManager.preferredConnectedPlatformName
        let isSpotify = (platform == "Spotify")
        let btnSize = min(64, max(44, min(width, height) * 0.34))

        ZStack {
            musicCardBackground

            RadialGradient(
                colors: [
                    (isSpotify ? Color(red: 0.11, green: 0.73, blue: 0.33) : Color(red: 0.98, green: 0.22, blue: 0.38)).opacity(isDarkMusic ? 0.28 : 0.18),
                    Color.clear
                ],
                center: .center,
                startRadius: 4,
                endRadius: max(width, height) * 0.6
            )

            VStack(spacing: min(12, height * 0.07)) {
                Button {
                    musicManager.launchAndPlayPreferredPlatform()
                } label: {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: isSpotify
                                        ? [Color(red: 0.14, green: 0.80, blue: 0.38), Color(red: 0.09, green: 0.62, blue: 0.28)]
                                        : [Color(red: 1.00, green: 0.26, blue: 0.42), Color(red: 0.86, green: 0.14, blue: 0.30)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: btnSize, height: btnSize)
                            .shadow(color: (isSpotify ? Color.green : Color.pink).opacity(0.45), radius: 12, y: 4)

                        Image(systemName: "play.fill")
                            .font(.system(size: btnSize * 0.40, weight: .bold))
                            .foregroundStyle(.white)
                            .offset(x: 2)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(loc("music.launch_app", platform))

                VStack(spacing: 2) {
                    Text(loc("music.launch_app", platform))
                        .font(.system(size: min(14, max(11.5, width * 0.055)), weight: .bold))
                        .foregroundStyle(cardTitleColor)
                        .lineLimit(1)
                    if height > 125 {
                        Text(loc("music.tap_to_start"))
                            .font(.system(size: 10.5))
                            .foregroundStyle(cardSubtitleColor)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                }
            }
            .padding(12)
        }
    }

    // MARK: - 1. Full-Bleed Artwork + Floating Header Pill (Photo 3 Bas-Gauche, Col 2 Bas, Bas-Droite)

    @ViewBuilder
    private func fullBleedPillLayout(width w: CGFloat, height h: CGFloat) -> some View {
        let isCompact = (h < 165 || w < 165) && config.size == .small
        let isTall = h > w * 1.15
        let pad: CGFloat = isCompact ? 10 : 14
        let hasCoverArt = (track.artworkImage != nil)

        let titleFG: Color = hasCoverArt ? .white : cardTitleColor
        let timestampFG: Color = hasCoverArt ? .white.opacity(0.92) : cardTimestampColor
        let seekTrack: Color = hasCoverArt ? .white.opacity(0.32) : cardSeekTrackColor
        let seekFill: Color = hasCoverArt ? .white : cardSeekFillColor
        let controlFG: Color = hasCoverArt ? .white : cardControlColor

        ZStack {
            // 1. Pochette réelle si disponible, sinon fond givré propre (Clair ou Sombre) sans image factice
            if let art = track.artworkImage {
                Image(nsImage: art)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: w, height: h)
                    .clipped()

                LinearGradient(
                    stops: [
                        .init(color: Color.black.opacity(0.10), location: 0.0),
                        .init(color: Color.clear, location: 0.40),
                        .init(color: Color.black.opacity(0.38), location: 0.72),
                        .init(color: Color.black.opacity(0.72), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
            } else {
                musicCardBackground
            }

            // 2. Contenu : Pilule supérieure + Titre, Barre et Contrôles en bas
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: isCompact ? 7 : 9) {
                    artworkThumbnail(size: isCompact ? 22 : 28, cornerRadius: isCompact ? 5 : 7)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(displayArtist)
                            .font(.system(size: isCompact ? 9.5 : 11.5, weight: .bold))
                            .foregroundStyle(isDarkMusic ? .white : Color(white: 0.08))
                            .lineLimit(1)

                        Text(displayAlbum)
                            .font(.system(size: isCompact ? 8.0 : 9.5, weight: .regular))
                            .foregroundStyle(isDarkMusic ? .white.opacity(0.80) : Color(white: 0.35))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    if musicManager.isLaunchingRandomTrack {
                        ProgressView().controlSize(.mini)
                    }
                }
                .padding(.horizontal, isCompact ? 7 : 9)
                .padding(.vertical, isCompact ? 5 : 6)
                .background(
                    RoundedRectangle(cornerRadius: isCompact ? 10 : 12, style: .continuous)
                        .fill(isDarkMusic ? Color.black.opacity(hasCoverArt ? 0.56 : 0.34) : Color.white.opacity(0.78))
                        .background(
                            .ultraThinMaterial,
                            in: RoundedRectangle(cornerRadius: isCompact ? 10 : 12, style: .continuous)
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: isCompact ? 10 : 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(isDarkMusic ? 0.14 : 0.45), lineWidth: 0.7)
                )

                Spacer(minLength: 4)

                VStack(alignment: .leading, spacing: isCompact ? 3 : 5) {
                    Text(displayTitle)
                        .font(.system(size: isTall ? 20 : (isCompact ? 14 : 18), weight: .bold))
                        .foregroundStyle(titleFG)
                        .lineLimit(1)
                        .shadow(color: hasCoverArt ? .black.opacity(0.45) : .clear, radius: 4, y: 1)

                    progressSection(
                        textColor: timestampFG,
                        trackColor: seekTrack,
                        fillColor: seekFill,
                        isCompact: isCompact
                    )

                    transportButtonsRow(
                        color: controlFG,
                        iconSize: isCompact ? 11.5 : 14,
                        spacing: isCompact ? 20 : 28
                    )
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, isCompact ? 1 : 2)
                }
            }
            .padding(pad)
        }
    }

    // MARK: - 2. Vinyle Marbré Cyan (Photo 3 Haut-Gauche 1×1 Demi-Vinyle & Haut-Droite 2×1 Vinyle Complet)

    @ViewBuilder
    private func vinylSplatterLayout(width w: CGFloat, height h: CGFloat) -> some View {
        let isWide = w > h * 1.25
        let isTall = h > w * 1.15
        let isLargeSquare = w >= 210 && h >= 210

        ZStack {
            musicCardBackground

            if isWide {
                let discSize = min(h * 0.68, w * 0.44)
                VStack(spacing: 0) {
                    HStack(alignment: .center, spacing: 12) {
                        spinningDiscView(size: discSize, variant: .cyanSplatter, shadowOpacity: isDarkMusic ? 0.40 : 0.18, shadowRadius: 8, shadowY: 4)

                        VStack(spacing: 4) {
                            Text(displayTitle)
                                .font(.system(size: min(16, h * 0.115), weight: .bold))
                                .foregroundStyle(cardTitleColor)
                                .lineLimit(1)

                            Text(displayArtist)
                                .font(.system(size: min(11.5, h * 0.08), weight: .medium))
                                .foregroundStyle(cardSubtitleColor)
                                .lineLimit(1)

                            transportButtonsRow(
                                color: cardControlColor,
                                iconSize: min(14, h * 0.095),
                                spacing: 22
                            )
                            .padding(.top, 4)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .frame(maxHeight: .infinity)

                    progressSection(
                        textColor: cardTimestampColor,
                        trackColor: cardSeekTrackColor,
                        fillColor: cardSeekFillColor,
                        isCompact: h < 135
                    )
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            } else if isTall || isLargeSquare {
                vinylTallInternal(width: w, height: h, variant: .cyanSplatter)
            } else {
                let discSize = w * 0.80
                let isCompact = h < 145

                ZStack(alignment: .bottom) {
                    spinningDiscView(size: discSize, variant: .cyanSplatter, shadowOpacity: isDarkMusic ? 0.40 : 0.18, shadowRadius: 8, shadowY: 4)
                        .position(x: w / 2, y: discSize * 0.08)

                    VStack(spacing: isCompact ? 2.5 : 4) {
                        VStack(spacing: 1) {
                            Text(displayTitle)
                                .font(.system(size: isCompact ? 11.5 : 13.5, weight: .bold))
                                .foregroundStyle(cardTitleColor)
                                .lineLimit(1)

                            Text(displayArtist)
                                .font(.system(size: isCompact ? 8.5 : 10, weight: .medium))
                                .foregroundStyle(cardSubtitleColor)
                                .lineLimit(1)
                        }

                        progressSection(
                            textColor: cardTimestampColor,
                            trackColor: cardSeekTrackColor,
                            fillColor: cardSeekFillColor,
                            isCompact: true
                        )

                        transportButtonsRow(
                            color: cardControlColor,
                            iconSize: isCompact ? 10.5 : 12.5,
                            spacing: isCompact ? 18 : 24
                        )
                    }
                    .padding(.horizontal, isCompact ? 10 : 12)
                    .padding(.bottom, isCompact ? 7 : 10)
                }
            }
        }
    }

    // MARK: - 3. Vinyle Blanc Studio

    @ViewBuilder
    private func vinylWhiteGroovedLayout(width w: CGFloat, height h: CGFloat) -> some View {
        let isWide = w > h * 1.25
        ZStack {
            musicCardBackground

            if isWide {
                let discSize = min(h * 0.68, w * 0.44)
                VStack(spacing: 0) {
                    HStack(alignment: .center, spacing: 12) {
                        spinningDiscView(size: discSize, variant: .whiteGrooved, shadowOpacity: isDarkMusic ? 0.38 : 0.15, shadowRadius: 8, shadowY: 4)

                        VStack(spacing: 4) {
                            Text(displayTitle)
                                .font(.system(size: min(16, h * 0.115), weight: .bold))
                                .foregroundStyle(cardTitleColor)
                                .lineLimit(1)
                            Text(displayArtist)
                                .font(.system(size: min(11.5, h * 0.08), weight: .medium))
                                .foregroundStyle(cardSubtitleColor)
                                .lineLimit(1)
                            transportButtonsRow(color: cardControlColor, iconSize: 13.5, spacing: 22)
                                .padding(.top, 4)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .frame(maxHeight: .infinity)

                    progressSection(
                        textColor: cardTimestampColor,
                        trackColor: cardSeekTrackColor,
                        fillColor: cardSeekFillColor,
                        isCompact: h < 135
                    )
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            } else {
                vinylTallInternal(width: w, height: h, variant: .whiteGrooved)
            }
        }
    }

    @ViewBuilder
    private func vinylTallInternal(width w: CGFloat, height h: CGFloat, variant: ReferenceVinylDiscView.DiscVariant) -> some View {
        let isSmall = h < 195
        let isNarrowVertical = h > w * 1.15 && w < 210
        let discSize = isSmall
            ? min(w * 0.48, h * 0.42)
            : (isNarrowVertical ? min(w * 0.78, h * 0.44) : min(w * 0.78, h * 0.52))

        VStack(spacing: isSmall ? 3 : (isNarrowVertical ? 8 : 10)) {
            Spacer(minLength: 2)

            spinningDiscView(size: discSize, variant: variant, shadowOpacity: isDarkMusic ? 0.42 : 0.18, shadowRadius: 10, shadowY: 5)

            Spacer(minLength: 2)

            VStack(spacing: isSmall ? 1 : 2) {
                Text(displayTitle)
                    .font(.system(size: isSmall ? 12 : (isNarrowVertical ? 14 : 16), weight: .bold))
                    .foregroundStyle(cardTitleColor)
                    .lineLimit(1)

                Text(displayArtist)
                    .font(.system(size: isSmall ? 8.5 : (isNarrowVertical ? 10.5 : 11.5), weight: .medium))
                    .foregroundStyle(cardSubtitleColor)
                    .lineLimit(1)
            }

            progressSection(
                textColor: cardTimestampColor,
                trackColor: cardSeekTrackColor,
                fillColor: cardSeekFillColor,
                isCompact: isSmall || isNarrowVertical
            )

            transportButtonsRow(
                color: cardControlColor,
                iconSize: isSmall ? 11 : (isNarrowVertical ? 13 : 14),
                spacing: isSmall ? 18 : (isNarrowVertical ? 18 : 28)
            )
            .padding(.bottom, isSmall ? 3 : 8)
        }
        .padding(.horizontal, isSmall ? 10 : (isNarrowVertical ? 11 : 16))
        .padding(.vertical, isSmall ? 6 : 10)
    }

    // MARK: - 4. Cadre Éditorial

    @ViewBuilder
    private func framedEditorialLayout(width w: CGFloat, height h: CGFloat) -> some View {
        let isWide = w > h * 1.25
        let isTall = h > w * 1.15
        let isCompact = h < 155 && !isWide

        ZStack {
            musicCardBackground

            if isWide {
                let coverSize = min(h - 20, w * 0.42)
                HStack(spacing: 14) {
                    artworkView(width: coverSize, height: coverSize, showSignature: false)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: .black.opacity(0.16), radius: 6, y: 3)

                    VStack(spacing: 6) {
                        VStack(spacing: 1.5) {
                            Text(displayTitle)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(cardTitleColor)
                                .lineLimit(1)
                            Text(displayArtist)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(cardSubtitleColor)
                                .lineLimit(1)
                        }

                        progressSection(
                            textColor: cardTimestampColor,
                            trackColor: cardSeekTrackColor,
                            fillColor: cardSeekFillColor,
                            isCompact: true
                        )

                        transportButtonsRow(
                            color: cardControlColor,
                            iconSize: 13,
                            spacing: 22
                        )
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(10)
            } else {
                let pad: CGFloat = isCompact ? 8 : 11
                let coverW = max(40, w - pad * 2)
                let coverH = isTall
                    ? min(coverW * 1.12, h * 0.54)
                    : max(36, h * 0.46)

                VStack(spacing: isCompact ? 3 : 6) {
                    artworkView(width: coverW, height: coverH, showSignature: isTall)
                        .clipShape(RoundedRectangle(cornerRadius: isCompact ? 10 : 14, style: .continuous))
                        .shadow(color: .black.opacity(0.16), radius: 6, y: 3)

                    Spacer(minLength: 0)

                    VStack(spacing: 1) {
                        Text(displayTitle)
                            .font(.system(size: isCompact ? 11.5 : (isTall ? 14.5 : 13.5), weight: .bold))
                            .foregroundStyle(cardTitleColor)
                            .lineLimit(1)

                        Text(displayArtist)
                            .font(.system(size: isCompact ? 8.5 : (isTall ? 10 : 9.5), weight: .medium))
                            .foregroundStyle(cardSubtitleColor)
                            .lineLimit(1)
                    }

                    progressSection(
                        textColor: cardTimestampColor,
                        trackColor: cardSeekTrackColor,
                        fillColor: cardSeekFillColor,
                        isCompact: isCompact || (isTall && w < 200)
                    )

                    transportButtonsRow(
                        color: cardControlColor,
                        iconSize: isCompact ? 10.5 : 13,
                        spacing: isCompact || (isTall && w < 200) ? 18 : 26
                    )
                }
                .padding(pad)
            }
        }
    }

    // MARK: - Sous-composants Partagés (Barre 1:20 / 2:27, Boutons, Pochette, Vinyle Animé)

    private var musicCardBackground: some View {
        ZStack {
            if isDarkMusic {
                LinearGradient(
                    colors: [
                        Color(red: 0.13, green: 0.14, blue: 0.18).opacity(0.94),
                        Color(red: 0.08, green: 0.09, blue: 0.12).opacity(0.95),
                        Color(red: 0.11, green: 0.12, blue: 0.16).opacity(0.94)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(0.12), location: 0.0),
                        .init(color: Color.clear, location: 0.45),
                        .init(color: Color.white.opacity(0.06), location: 0.80),
                        .init(color: Color.clear, location: 1.0)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.95, green: 0.96, blue: 0.98).opacity(0.96),
                        Color(red: 0.89, green: 0.90, blue: 0.93).opacity(0.95),
                        Color(red: 0.96, green: 0.97, blue: 0.99).opacity(0.97)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(0.45), location: 0.0),
                        .init(color: Color.clear, location: 0.45),
                        .init(color: Color.white.opacity(0.35), location: 0.78),
                        .init(color: Color.clear, location: 1.0)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }

    @ViewBuilder
    private func spinningDiscView(
        size: CGFloat,
        variant: ReferenceVinylDiscView.DiscVariant,
        shadowOpacity: Double = 0.25,
        shadowRadius: CGFloat = 8,
        shadowY: CGFloat = 4
    ) -> some View {
        ZStack {
            // Masque d'ombre circulaire statique mis en cache GPU (ne se recalcule pas pendant la rotation 120 Hz)
            Circle()
                .fill(Color.black.opacity(0.88))
                .padding(2)
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, y: shadowY)

            TimelineView(.animation(paused: !isSpinning)) { timeline in
                let angle = spinTracker.advance(to: timeline.date, isSpinning: isSpinning)
                ReferenceVinylDiscView(
                    size: size,
                    variant: variant,
                    artwork: track.displayImage
                )
                .equatable()
                .scaleEffect(discBounceScale)
                .rotationEffect(.degrees(angle + extraDiscRotation))
            }
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private func artworkView(width: CGFloat, height: CGFloat, showSignature: Bool) -> some View {
        if let art = track.artworkImage {
            Image(nsImage: art)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: width, height: height)
                .clipped()
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: isDarkMusic
                                ? [Color(white: 0.18), Color(white: 0.11)]
                                : [Color(red: 0.98, green: 0.25, blue: 0.42), Color(red: 0.84, green: 0.14, blue: 0.30)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "music.note")
                    .font(.system(size: max(18, min(width, height) * 0.36), weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
            }
            .frame(width: width, height: height)
            .clipped()
        }
    }

    @ViewBuilder
    private func artworkThumbnail(size: CGFloat, cornerRadius: CGFloat) -> some View {
        if let art = track.displayImage {
            Image(nsImage: art)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.98, green: 0.25, blue: 0.42), Color(red: 0.84, green: 0.14, blue: 0.30)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "music.note")
                    .font(.system(size: max(10, size * 0.46), weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
        }
    }

    @ViewBuilder
    private func progressSection(
        textColor: Color,
        trackColor: Color,
        fillColor: Color,
        isCompact: Bool
    ) -> some View {
        ReferenceProgressSectionView(
            progressState: musicManager.progressState,
            hasTrack: track.hasTrack,
            durationSeconds: durationSeconds,
            textColor: textColor,
            trackColor: trackColor,
            fillColor: fillColor,
            isCompact: isCompact
        ) { fraction in
            if track.hasTrack {
                musicManager.seek(toFraction: fraction)
            }
        }
    }

    @ViewBuilder
    private func transportButtonsRow(color: Color, iconSize: CGFloat, spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            Button {
                animateSkip(direction: -1)
                if track.hasTrack {
                    musicManager.previousTrack()
                } else {
                    musicManager.previousSystemTrack()
                }
            } label: {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: iconSize, weight: .bold))
                    .foregroundStyle(color)
                    .frame(width: iconSize + 10, height: iconSize + 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(loc("music.control.previous"))

            Button {
                animatePlayPause()
                if track.hasTrack {
                    musicManager.togglePlayPause()
                } else {
                    widgetManager.toggleMusicPlayback(for: config.kind)
                    musicManager.playRandomMusic()
                }
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: iconSize * 1.08, weight: .bold))
                    .foregroundStyle(color)
                    .frame(width: iconSize + 12, height: iconSize + 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(loc(isPlaying ? "music.control.pause" : "music.control.play"))

            Button {
                animateSkip(direction: 1)
                if track.hasTrack {
                    musicManager.nextTrack()
                } else {
                    musicManager.nextSystemTrack()
                }
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: iconSize, weight: .bold))
                    .foregroundStyle(color)
                    .frame(width: iconSize + 10, height: iconSize + 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(loc("music.control.next"))
        }
    }

    private func animateSkip(direction: Int) {
        guard !reduceMotion else { return }
        bounceTask?.cancel()
        withAnimation(AppleDesignSystem.Springs.bouncy) {
            extraDiscRotation += Double(direction) * 180.0
            discBounceScale = 0.94
        }
        bounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled else { return }
            withAnimation(AppleDesignSystem.Springs.bouncy) {
                discBounceScale = 1.0
            }
        }
    }

    private func animatePlayPause() {
        guard !reduceMotion else { return }
        bounceTask?.cancel()
        withAnimation(AppleDesignSystem.Springs.snappy) {
            discBounceScale = 0.95
        }
        bounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            withAnimation(AppleDesignSystem.Springs.bouncy) {
                discBounceScale = 1.0
            }
        }
    }
}

/// Sous-vue isolée pour la barre de progression et le compteur temporel :
/// seul ce composant est invalidé toutes les 2 s sans redessiner la pochette floutée ou le vinyle.
private struct ReferenceProgressSectionView: View {
    @ObservedObject var progressState: MusicProgressState
    let hasTrack: Bool
    let durationSeconds: Double
    let textColor: Color
    let trackColor: Color
    let fillColor: Color
    let isCompact: Bool
    let onSeek: (Double) -> Void

    private var elapsedSeconds: Double {
        hasTrack ? progressState.elapsedSeconds : 80
    }

    var body: some View {
        VStack(spacing: isCompact ? 1.5 : 2.5) {
            HStack {
                Text(formatTime(Int(elapsedSeconds)))
                    .font(.system(size: isCompact ? 8.0 : 9.0, weight: .bold))
                    .foregroundStyle(textColor)
                    .monospacedDigit()
                Spacer()
                Text(formatTime(Int(durationSeconds)))
                    .font(.system(size: isCompact ? 8.0 : 9.0, weight: .bold))
                    .foregroundStyle(textColor)
                    .monospacedDigit()
            }

            SeekBar(
                elapsed: elapsedSeconds,
                duration: max(1, durationSeconds),
                trackColor: trackColor,
                fillColor: fillColor,
                barHeight: isCompact ? 2.5 : 3.2,
                isEnabled: true,
                onSeek: onSeek
            )
            .frame(height: isCompact ? 8 : 10)
        }
    }

    private func formatTime(_ seconds: Int) -> String {
        let m = max(0, seconds) / 60
        let s = max(0, seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}
