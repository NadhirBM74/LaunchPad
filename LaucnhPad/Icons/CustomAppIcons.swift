import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers
import Combine

// MARK: - Modes d'Apparence des Icônes (Tous styles compatibles HD 512×512)

public enum IconAppearanceStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case original = "original"           // Icônes originales haute définition des applications (recommandé)
    case dark = "dark"                   // Sombre profond + lueur ambiante (Photos 1 & 4)
    case light = "light"                 // Clair lumineux + couleurs vives (Photos 1 & 2)
    case tinted = "tinted"               // Teinté monochrome dégradé (Photo 1 Tinted)
    case monochrome = "monochrome"       // Monochrome argenté/graphite haute lisibilité
    case transparent = "transparent"     // Transparent / Verre cristal sans fond opaque
    case clearDark = "clearDark"         // Verre sombre translucide (Photo 1 Clear Row 1)
    case frostedGlass = "frostedGlass"   // Verre dépoli clair avec reflet diagonal (Photo 1 Clear Row 2)
    case clearLiquid = "clearLiquid"     // Verre liquide réfractif (Photo 1 Clear Row 3)
    case classicApple = "classicApple"   // Pack Studio Apple (App Store sable, Calendrier matriciel)
    case system = "system"               // Suit automatiquement l'apparence de macOS

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .original: return "Originales HD"
        case .dark: return "Sombre"
        case .light: return "Clair"
        case .tinted: return "Teinté"
        case .monochrome: return "Monochrome"
        case .transparent: return "Transparent"
        case .clearDark: return "Verre Sombre"
        case .frostedGlass: return "Verre Givré"
        case .clearLiquid: return "Verre Liquide"
        case .classicApple: return "Pack Studio Apple"
        case .system: return "Automatique (macOS)"
        }
    }

    public var subtitle: String {
        switch self {
        case .original: return "Les vraies icônes en couleur de vos applications en très haute définition"
        case .dark: return "Fond sombre élégant qui met en valeur les couleurs de chaque icône"
        case .light: return "Rendu lumineux et éclatant adapté aux ambiances claires"
        case .tinted: return "Harmonise toutes vos icônes avec votre couleur préférée"
        case .monochrome: return "Style épuré en nuances d'argent et de graphite à fort contraste"
        case .transparent: return "Fond en verre transparent laissant apparaître votre fond d'écran"
        case .clearDark: return "Surface vitrée sombre translucide avec icônes colorées"
        case .frostedGlass: return "Verre dépoli lumineux avec reflet diagonal soyeux"
        case .clearLiquid: return "Effet verre liquide Apple avec contour lumineux"
        case .classicApple: return "Icônes revisitées (App Store sable chaud, Calendrier à points)"
        case .system: return "Utilise le style d'icônes configuré dans les Réglages Système de votre Mac"
        }
    }

    public var badgeIcon: String {
        switch self {
        case .original: return "sparkles.rectangle.stack.fill"
        case .dark: return "moon.stars.fill"
        case .light: return "sun.max.fill"
        case .tinted: return "paintpalette.fill"
        case .monochrome: return "circle.lefthalf.filled"
        case .transparent: return "square.on.square.dashed"
        case .clearDark: return "rectangle.fill.on.rectangle.fill"
        case .frostedGlass: return "snowflake"
        case .clearLiquid: return "drop.fill"
        case .classicApple: return "apple.logo"
        case .system: return "macwindow"
        }
    }
}

// MARK: - Catalogue des Icônes Vectorielles Reproduites en Code Swift

public enum CustomAppIconKind: String, CaseIterable, Identifiable, Sendable {
    case freeform
    case photos
    case home
    case keynote
    case weather
    case maps
    case appStore
    case calendar
    case phone
    case facetime
    case telegram
    case messages
    case books
    case safari
    case mail
    case music
    case spotify
    case finder
    case settings
    case notes
    case reminders
    case clock
    case tv
    case podcasts
    case calculator
    case terminal
    case xcode
    case findMy

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .freeform: return "Freeform"
        case .photos: return "Photos"
        case .home: return "Maison"
        case .keynote: return "Keynote"
        case .weather: return "Météo"
        case .maps: return "Plans"
        case .appStore: return "App Store"
        case .calendar: return "Calendar"
        case .phone: return "Phone"
        case .facetime: return "FaceTime"
        case .telegram: return "Telegram"
        case .messages: return "Messages"
        case .books: return "Books"
        case .safari: return "Safari"
        case .mail: return "Mail"
        case .music: return "Music"
        case .spotify: return "Spotify"
        case .finder: return "Finder"
        case .settings: return "Réglages"
        case .notes: return "Notes"
        case .reminders: return "Rappels"
        case .clock: return "Horloge"
        case .tv: return "TV"
        case .podcasts: return "Podcasts"
        case .calculator: return "Calculette"
        case .terminal: return "Terminal"
        case .xcode: return "Xcode"
        case .findMy: return "Localiser"
        }
    }

    /// Associe un chemin d'application ou un bundleID macOS à notre icône vectorielle sur mesure
    nonisolated public static func match(path: String, bundleID: String?, name: String) -> CustomAppIconKind? {
        let lowerPath = path.lowercased()
        let lowerBundle = (bundleID ?? "").lowercased()
        let lowerName = name.lowercased()

        if lowerBundle == "com.apple.freeform" || lowerPath.contains("freeform.app") || lowerName == "freeform" {
            return .freeform
        }
        if lowerBundle == "com.apple.photos" || lowerPath.contains("/photos.app") || lowerName == "photos" {
            return .photos
        }
        if lowerBundle == "com.apple.home" || lowerPath.contains("/home.app") || lowerName == "home" || lowerName == "maison" {
            return .home
        }
        if lowerBundle == "com.apple.iwork.keynote" || lowerPath.contains("keynote.app") || lowerName == "keynote" {
            return .keynote
        }
        if lowerBundle == "com.apple.weather" || lowerPath.contains("weather.app") || lowerName == "weather" || lowerName == "météo" {
            return .weather
        }
        if lowerBundle == "com.apple.maps" || lowerPath.contains("/maps.app") || lowerName == "maps" || lowerName == "plans" {
            return .maps
        }
        if lowerBundle == "com.apple.appstore" || lowerPath.contains("app store.app") || lowerName == "app store" {
            return .appStore
        }
        if lowerBundle == "com.apple.ical" || lowerPath.contains("calendar.app") || lowerName == "calendar" || lowerName == "calendrier" {
            return .calendar
        }
        if lowerBundle == "com.apple.mobilephone" || lowerBundle == "com.apple.facetime.phone" || lowerName == "phone" || lowerName == "téléphone" {
            return .phone
        }
        if lowerBundle == "com.apple.facetime" || lowerPath.contains("facetime.app") || lowerName == "facetime" {
            return .facetime
        }
        if lowerBundle.contains("telegram") || lowerPath.contains("telegram.app") || lowerName.contains("telegram") {
            return .telegram
        }
        if lowerBundle == "com.apple.mobilesms" || lowerPath.contains("messages.app") || lowerName == "messages" {
            return .messages
        }
        if lowerBundle == "com.apple.ibooksx" || lowerPath.contains("books.app") || lowerName == "books" || lowerName == "livres" {
            return .books
        }
        if lowerBundle == "com.apple.safari" || lowerPath.contains("safari.app") {
            return .safari
        }
        if lowerBundle == "com.apple.mail" || lowerPath.contains("/mail.app") {
            return .mail
        }
        if lowerBundle == "com.apple.music" || lowerPath.contains("/music.app") || lowerName == "musique" {
            return .music
        }
        if lowerBundle == "com.spotify.client" || lowerPath.contains("spotify.app") {
            return .spotify
        }
        if lowerBundle == "com.apple.finder" || lowerPath.contains("finder.app") {
            return .finder
        }
        if lowerBundle == "com.apple.systempreferences" || lowerPath.contains("system settings.app") || lowerName.contains("réglages") || lowerName == "system settings" {
            return .settings
        }
        if lowerBundle == "com.apple.notes" || lowerPath.contains("/notes.app") {
            return .notes
        }
        if lowerBundle == "com.apple.reminders" || lowerPath.contains("reminders.app") || lowerName == "rappels" {
            return .reminders
        }
        if lowerBundle == "com.apple.clock" || lowerPath.contains("/clock.app") || lowerName == "horloge" {
            return .clock
        }
        if lowerBundle == "com.apple.tv" || lowerPath.contains("/tv.app") {
            return .tv
        }
        if lowerBundle == "com.apple.podcasts" || lowerPath.contains("podcasts.app") {
            return .podcasts
        }
        if lowerBundle == "com.apple.calculator" || lowerPath.contains("calculator.app") || lowerName == "calculette" {
            return .calculator
        }
        if lowerBundle == "com.apple.terminal" || lowerPath.contains("terminal.app") {
            return .terminal
        }
        if lowerBundle == "com.apple.dt.xcode" || lowerPath.contains("xcode.app") {
            return .xcode
        }
        if lowerBundle == "com.apple.findmy" || lowerPath.contains("find my.app") || lowerName == "localiser" {
            return .findMy
        }
        return nil
    }
}

// MARK: - Vue SwiftUI Vectorielle Haute Fidélité pour chaque Icône

public struct CustomAppIconView: View {
    public let kind: CustomAppIconKind
    public var style: IconAppearanceStyle = .dark
    public var tintColor: Color = Color(red: 0.12, green: 0.56, blue: 1.0)
    public var size: CGFloat = 128

    public init(
        kind: CustomAppIconKind,
        style: IconAppearanceStyle = .dark,
        tintColor: Color = Color(red: 0.12, green: 0.56, blue: 1.0),
        size: CGFloat = 128
    ) {
        self.kind = kind
        self.style = style
        self.tintColor = tintColor
        self.size = size
    }

    private var inset: CGFloat { size * 0.09 }
    private var bodySize: CGFloat { size - inset * 2 }
    private var cornerRadius: CGFloat { bodySize * 0.228 }

    public var body: some View {
        let s = bodySize
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        ZStack {
            // 1. Fond Squircle selon le style (Dark, Light, Tinted, Clear Glass, Frosted Glass, Classic)
            squircleBackground(size: s, shape: shape)

            // 2. Contenu Vectoriel Spécifique à l'Application
            iconGlyphContent(size: s)
                .frame(width: s, height: s)
                .saturation(style == .monochrome ? 0.0 : 1.0)
                .contrast(style == .monochrome ? 1.12 : 1.0)
                .clipShape(shape)

            // 3. Reflet Spéculaire de Verre & Bordure Lumineuse (selon le style)
            squircleGlassOverlay(size: s, shape: shape)
        }
        .frame(width: s, height: s)
        .shadow(
            color: Color.black.opacity(style == .light ? 0.18 : 0.34),
            radius: size * 0.042,
            x: 0,
            y: size * 0.022
        )
        .frame(width: size, height: size)
    }

    // MARK: - Fond Squircle Adaptatif (Photos 1, 2 & 4)

    @ViewBuilder
    private func squircleBackground(size s: CGFloat, shape: RoundedRectangle) -> some View {
        if kind == .calendar && (style == .classicApple || style == .light || style == .frostedGlass) {
            // Calendrier matriciel iconique de la Photo 2 : Bandeau rouge vif en haut + corps gris-taupe chaud
            ZStack(alignment: .top) {
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.61, green: 0.58, blue: 0.55),
                            Color(red: 0.52, green: 0.49, blue: 0.46)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 1.00, green: 0.14, blue: 0.28),
                                Color(red: 0.98, green: 0.10, blue: 0.22)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: s * 0.27)
            }
            .clipShape(shape)
        } else if kind == .appStore && style == .classicApple {
            // App Store Photo 2 : Fond pêche/sable chaud translucide
            shape.fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.90, green: 0.72, blue: 0.59),
                        Color(red: 0.85, green: 0.64, blue: 0.50)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        } else if kind == .maps && style != .tinted {
            // Plans Photo 1 : Fond carte routière complet
            mapsBackgroundCanvas(size: s)
                .clipShape(shape)
        } else {
            switch style {
            case .dark, .system, .original:
                ZStack {
                    shape.fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.15, green: 0.15, blue: 0.17),
                                Color(red: 0.06, green: 0.06, blue: 0.08)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    // Halo ambiant subtil sur les bords comme sur la Photo 4 (Phone, FaceTime, Telegram, Messages, Books)
                    ambientGlowForDarkIcon(size: s)
                        .clipShape(shape)
                }

            case .light, .classicApple:
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color.white,
                            Color(red: 0.93, green: 0.94, blue: 0.96)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            case .tinted:
                ZStack {
                    shape.fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.03, green: 0.08, blue: 0.15),
                                Color(red: 0.01, green: 0.03, blue: 0.06)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    RadialGradient(
                        colors: [tintColor.opacity(0.28), Color.clear],
                        center: .topLeading,
                        startRadius: 2,
                        endRadius: s * 0.85
                    )
                    .clipShape(shape)
                }

            case .clearDark:
                // Photo 1 (Clear Colored Row 1) : Verre sombre bleuté/indigo translucide
                ZStack {
                    shape.fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.14, green: 0.15, blue: 0.34).opacity(0.84),
                                Color(red: 0.08, green: 0.09, blue: 0.22).opacity(0.90)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    RadialGradient(
                        colors: [Color.white.opacity(0.12), Color.clear],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: s * 0.75
                    )
                    .clipShape(shape)
                }

            case .frostedGlass:
                // Photo 1 (Clear Colored Row 2) : Verre givré clair avec reflet diagonal soyeux
                ZStack {
                    shape.fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.86, green: 0.88, blue: 0.98).opacity(0.88),
                                Color(red: 0.74, green: 0.77, blue: 0.94).opacity(0.82),
                                Color(red: 0.88, green: 0.90, blue: 0.99).opacity(0.90)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    // Bande de réflexion diagonale brillante (comme sur Social / Clear Row 2)
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.55), location: 0.0),
                            .init(color: Color.white.opacity(0.12), location: 0.32),
                            .init(color: Color.clear, location: 0.52),
                            .init(color: Color.white.opacity(0.42), location: 0.78),
                            .init(color: Color.white.opacity(0.15), location: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(shape)
                }

            case .clearLiquid, .transparent:
                // Photo 1 (Clear Colored Row 3) : Liquid Glass cristallin avec bulle de réfraction
                ZStack {
                    shape.fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(style == .transparent ? 0.14 : 0.28),
                                Color(red: 0.55, green: 0.62, blue: 1.0).opacity(style == .transparent ? 0.10 : 0.22),
                                Color.white.opacity(style == .transparent ? 0.06 : 0.14)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    // Reflet lenticulaire incurvé en haut à gauche
                    Ellipse()
                        .fill(
                            RadialGradient(
                                colors: [Color.white.opacity(0.52), Color.white.opacity(0.12), Color.clear],
                                center: .topLeading,
                                startRadius: 2,
                                endRadius: s * 0.62
                            )
                        )
                        .frame(width: s * 0.95, height: s * 0.75)
                        .offset(x: -s * 0.15, y: -s * 0.18)
                        .clipShape(shape)
                }

            case .monochrome:
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color(white: 0.20),
                            Color(white: 0.09)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
    }

    @ViewBuilder
    private func ambientGlowForDarkIcon(size s: CGFloat) -> some View {
        let glowColors: (Color, Color) = {
            switch kind {
            case .phone:
                return (Color(red: 0.85, green: 0.12, blue: 0.22).opacity(0.42), Color(red: 0.12, green: 0.82, blue: 0.32).opacity(0.22))
            case .facetime:
                return (Color(red: 0.10, green: 0.75, blue: 0.35).opacity(0.28), Color(red: 0.08, green: 0.45, blue: 0.35).opacity(0.22))
            case .telegram:
                return (Color(red: 0.75, green: 0.14, blue: 0.18).opacity(0.38), Color(red: 0.35, green: 0.10, blue: 0.15).opacity(0.24))
            case .messages:
                return (Color(red: 0.12, green: 0.78, blue: 0.38).opacity(0.28), Color(red: 0.08, green: 0.42, blue: 0.68).opacity(0.25))
            case .books:
                return (Color(red: 0.12, green: 0.58, blue: 0.55).opacity(0.28), Color(red: 0.95, green: 0.52, blue: 0.12).opacity(0.25))
            case .home:
                return (Color.orange.opacity(0.25), Color.yellow.opacity(0.12))
            case .freeform:
                return (Color.cyan.opacity(0.20), Color.orange.opacity(0.18))
            default:
                return (Color.white.opacity(0.08), Color.clear)
            }
        }()

        ZStack {
            RadialGradient(
                colors: [glowColors.0, Color.clear],
                center: .bottomLeading,
                startRadius: 2,
                endRadius: s * 0.75
            )
            RadialGradient(
                colors: [glowColors.1, Color.clear],
                center: .topTrailing,
                startRadius: 2,
                endRadius: s * 0.75
            )
        }
    }

    @ViewBuilder
    private func squircleGlassOverlay(size s: CGFloat, shape: RoundedRectangle) -> some View {
        let lineWidth = max(0.8, s * 0.014)
        switch style {
        case .light:
            shape.strokeBorder(
                LinearGradient(
                    colors: [Color.white.opacity(0.95), Color.black.opacity(0.10)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: lineWidth
            )
        case .tinted:
            shape.strokeBorder(
                LinearGradient(
                    colors: [tintColor.opacity(0.55), tintColor.opacity(0.12), Color.white.opacity(0.15)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: lineWidth
            )
        case .frostedGlass, .clearLiquid, .classicApple:
            shape.strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.85),
                        Color.white.opacity(0.35),
                        Color.white.opacity(0.15),
                        Color.white.opacity(0.55)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: lineWidth * 1.15
            )
        default:
            shape.strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.38),
                        Color.white.opacity(0.10),
                        Color.white.opacity(0.04),
                        Color.white.opacity(0.18)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: lineWidth
            )
        }
    }

    // MARK: - Glyphes Vectoriels Haute Fidélité

    @ViewBuilder
    private func iconGlyphContent(size s: CGFloat) -> some View {
        switch kind {
        case .freeform:
            freeformGlyph(size: s)
        case .photos:
            photosFlowerGlyph(size: s)
        case .home:
            homeLayeredGlyph(size: s)
        case .keynote:
            keynotePodiumGlyph(size: s)
        case .weather:
            weatherSunCloudGlyph(size: s)
        case .maps:
            mapsNavigationGlyph(size: s)
        case .appStore:
            appStoreSticksGlyph(size: s)
        case .calendar:
            calendarDotMatrixGlyph(size: s)
        case .phone:
            phoneHandsetGlyph(size: s)
        case .facetime:
            facetimeCameraGlyph(size: s)
        case .telegram:
            telegramPaperPlaneGlyph(size: s)
        case .messages:
            messagesBubbleGlyph(size: s)
        case .books:
            booksOpenGlyph(size: s)
        case .safari:
            safariCompassGlyph(size: s)
        case .mail:
            mailEnvelopeGlyph(size: s)
        case .music:
            musicNoteGlyph(size: s)
        case .spotify:
            spotifyGlyph(size: s)
        case .finder:
            finderSmileGlyph(size: s)
        case .settings:
            settingsGearsGlyph(size: s)
        case .notes:
            notesPadGlyph(size: s)
        case .reminders:
            remindersListGlyph(size: s)
        case .clock:
            clockDialGlyph(size: s)
        case .tv:
            tvGlyph(size: s)
        case .podcasts:
            podcastsGlyph(size: s)
        case .calculator:
            calculatorGlyph(size: s)
        case .terminal:
            terminalGlyph(size: s)
        case .xcode:
            xcodeHammerGlyph(size: s)
        case .findMy:
            findMyRadarGlyph(size: s)
        }
    }

    // 1. FREEFORM (Photo 1 Col 1 : Cercle orange + Carré cyan + Courbe manuscrite)
    private func freeformGlyph(size s: CGFloat) -> some View {
        let isTinted = (style == .tinted)
        let circleColor = isTinted
            ? LinearGradient(colors: [tintColor.opacity(0.65), tintColor.opacity(0.32)], startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [Color(red: 1.0, green: 0.50, blue: 0.26), Color(red: 0.92, green: 0.34, blue: 0.18)], startPoint: .topLeading, endPoint: .bottomTrailing)
        let rectColor = isTinted
            ? LinearGradient(colors: [tintColor, tintColor.opacity(0.70)], startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [Color(red: 0.05, green: 0.84, blue: 1.0), Color(red: 0.0, green: 0.62, blue: 0.92)], startPoint: .top, endPoint: .bottom)
        let strokeColor: Color = isTinted ? Color(red: 0.02, green: 0.08, blue: 0.18) : Color(red: 0.12, green: 0.12, blue: 0.14)

        return ZStack {
            // Cercle corail en bas à gauche
            Circle()
                .fill(circleColor)
                .frame(width: s * 0.48, height: s * 0.48)
                .offset(x: -s * 0.11, y: s * 0.11)
                .shadow(color: .black.opacity(0.18), radius: s * 0.03, y: s * 0.015)

            // Carré arrondi cyan en haut à droite (translucide)
            RoundedRectangle(cornerRadius: s * 0.10, style: .continuous)
                .fill(rectColor)
                .frame(width: s * 0.46, height: s * 0.44)
                .opacity(0.88)
                .offset(x: s * 0.08, y: -s * 0.08)
                .shadow(color: .black.opacity(0.15), radius: s * 0.03, y: s * 0.015)

            // Trait de plume sinusoïdal (comme sur la Photo 1)
            Path { path in
                path.move(to: CGPoint(x: s * 0.18, y: s * 0.62))
                path.addCurve(
                    to: CGPoint(x: s * 0.44, y: s * 0.52),
                    control1: CGPoint(x: s * 0.25, y: s * 0.34),
                    control2: CGPoint(x: s * 0.38, y: s * 0.36)
                )
                path.addCurve(
                    to: CGPoint(x: s * 0.62, y: s * 0.54),
                    control1: CGPoint(x: s * 0.49, y: s * 0.65),
                    control2: CGPoint(x: s * 0.56, y: s * 0.38)
                )
                path.addCurve(
                    to: CGPoint(x: s * 0.84, y: s * 0.50),
                    control1: CGPoint(x: s * 0.68, y: s * 0.66),
                    control2: CGPoint(x: s * 0.77, y: s * 0.60)
                )
            }
            .stroke(strokeColor, style: StrokeStyle(lineWidth: s * 0.045, lineCap: .round, lineJoin: .round))
        }
    }

    // 2. PHOTOS (Photo 1 Col 2 : Rosace à 8 pétales arc-en-ciel ou teintée)
    private func photosFlowerGlyph(size s: CGFloat) -> some View {
        let isTinted = (style == .tinted)
        let petalColors: [Color] = [
            Color(red: 1.00, green: 0.23, blue: 0.19), // Haut : Rouge/Corail
            Color(red: 1.00, green: 0.58, blue: 0.00), // Haut-Droite : Orange
            Color(red: 1.00, green: 0.82, blue: 0.00), // Droite : Jaune
            Color(red: 0.25, green: 0.82, blue: 0.38), // Bas-Droite : Vert
            Color(red: 0.10, green: 0.72, blue: 0.86), // Bas : Turquoise
            Color(red: 0.05, green: 0.45, blue: 0.98), // Bas-Gauche : Bleu
            Color(red: 0.48, green: 0.32, blue: 0.92), // Gauche : Violet
            Color(red: 0.96, green: 0.24, blue: 0.62)  // Haut-Gauche : Rose/Magenta
        ]
        let petalW = s * 0.24
        let petalH = s * 0.37
        let offsetR = s * 0.175

        return ZStack {
            ForEach(0..<8, id: \.self) { i in
                let angle = Double(i) * 45.0
                let baseColor = isTinted
                    ? tintColor.opacity(0.55 + Double(i % 3) * 0.14)
                    : petalColors[i]
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [baseColor.opacity(0.94), baseColor.opacity(0.76)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: petalW, height: petalH)
                    .offset(y: -offsetR)
                    .rotationEffect(.degrees(angle))
                    .blendMode(style == .light ? .multiply : .plusLighter)
            }
        }
        .compositingGroup()
    }

    // 3. HOME / MAISON (Photo 1 Col 3 : 3 maisons concentriques lumineuses en relief)
    private func homeLayeredGlyph(size s: CGFloat) -> some View {
        let isTinted = (style == .tinted)
        let outerGrad = isTinted
            ? LinearGradient(colors: [tintColor.opacity(0.50), tintColor.opacity(0.28)], startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [Color(red: 1.00, green: 0.62, blue: 0.05), Color(red: 0.90, green: 0.42, blue: 0.00)], startPoint: .top, endPoint: .bottom)
        let midGrad = isTinted
            ? LinearGradient(colors: [tintColor.opacity(0.78), tintColor.opacity(0.48)], startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [Color(red: 1.00, green: 0.76, blue: 0.18), Color(red: 0.98, green: 0.56, blue: 0.04)], startPoint: .top, endPoint: .bottom)
        let innerGrad = isTinted
            ? LinearGradient(colors: [tintColor, tintColor.opacity(0.75)], startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [Color(red: 1.00, green: 0.92, blue: 0.58), Color(red: 1.00, green: 0.78, blue: 0.25)], startPoint: .top, endPoint: .bottom)
        let coreColor = isTinted ? Color.white.opacity(0.92) : Color(red: 1.0, green: 0.98, blue: 0.90)

        return ZStack(alignment: .bottom) {
            HouseSilhouetteShape()
                .fill(outerGrad)
                .frame(width: s * 0.68, height: s * 0.62)
                .shadow(color: .black.opacity(0.18), radius: s * 0.025, y: s * 0.01)

            HouseSilhouetteShape()
                .fill(midGrad)
                .frame(width: s * 0.48, height: s * 0.44)
                .offset(y: -s * 0.03)

            HouseSilhouetteShape()
                .fill(innerGrad)
                .frame(width: s * 0.30, height: s * 0.28)
                .offset(y: -s * 0.05)

            Capsule(style: .continuous)
                .fill(coreColor)
                .frame(width: s * 0.11, height: s * 0.14)
                .offset(y: -s * 0.06)
        }
    }

    // 4. KEYNOTE (Photo 1 Droite Col 1 : Pupitre + tableau avec camembert coloré)
    private func keynotePodiumGlyph(size s: CGFloat) -> some View {
        let isTinted = (style == .tinted)
        let standColor = isTinted ? tintColor : Color(red: 0.18, green: 0.68, blue: 0.98)
        let boardFill = (style == .dark || style == .clearDark)
            ? LinearGradient(colors: [Color.white, Color(white: 0.90)], startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [Color(red: 0.08, green: 0.74, blue: 1.0), Color(red: 0.02, green: 0.56, blue: 0.94)], startPoint: .top, endPoint: .bottom)

        return ZStack {
            // Pied vertical et socle
            VStack(spacing: 0) {
                Spacer().frame(height: s * 0.42)
                Rectangle()
                    .fill(standColor)
                    .frame(width: s * 0.048, height: s * 0.34)
                Capsule()
                    .fill(standColor)
                    .frame(width: s * 0.34, height: s * 0.048)
            }

            // Panneau de présentation incliné en haut
            ZStack {
                KeynoteBoardShape()
                    .fill(isTinted ? AnyShapeStyle(tintColor.opacity(0.85)) : AnyShapeStyle(boardFill))
                    .frame(width: s * 0.64, height: s * 0.32)
                    .shadow(color: .black.opacity(0.20), radius: s * 0.03, y: s * 0.02)

                // Camembert 3 couleurs au centre du tableau
                if !isTinted {
                    ZStack {
                        Circle()
                            .trim(from: 0.0, to: 0.36)
                            .fill(Color(red: 0.22, green: 0.80, blue: 0.36))
                        Circle()
                            .trim(from: 0.36, to: 0.72)
                            .fill(Color(red: 1.00, green: 0.32, blue: 0.28))
                        Circle()
                            .trim(from: 0.72, to: 1.0)
                            .fill(Color(red: 0.18, green: 0.56, blue: 0.98))
                    }
                    .rotationEffect(.degrees(-90))
                    .frame(width: s * 0.18, height: s * 0.18)
                } else {
                    Circle()
                        .fill(Color.white.opacity(0.85))
                        .frame(width: s * 0.16, height: s * 0.16)
                }
            }
            .offset(y: -s * 0.15)
        }
    }

    // 5. WEATHER / MÉTÉO (Photo 1 Droite Col 3 : Soleil 3D doré + Nuage sculpté)
    private func weatherSunCloudGlyph(size s: CGFloat) -> some View {
        let isTinted = (style == .tinted)
        let sunGrad = isTinted
            ? LinearGradient(colors: [tintColor, tintColor.opacity(0.55)], startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [Color(red: 1.00, green: 0.86, blue: 0.22), Color(red: 0.98, green: 0.62, blue: 0.05)], startPoint: .top, endPoint: .bottom)

        let cloudGrad: LinearGradient = {
            if isTinted {
                return LinearGradient(colors: [tintColor.opacity(0.92), tintColor.opacity(0.45)], startPoint: .top, endPoint: .bottom)
            } else if style == .clearDark || style == .dark {
                return LinearGradient(
                    colors: [
                        Color(red: 0.88, green: 0.89, blue: 0.91),
                        Color(red: 0.46, green: 0.48, blue: 0.50)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                return LinearGradient(
                    colors: [
                        Color.white,
                        Color(red: 0.64, green: 0.78, blue: 0.94)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }()

        return ZStack {
            // Soleil doré en haut à droite
            Circle()
                .fill(sunGrad)
                .frame(width: s * 0.38, height: s * 0.38)
                .shadow(color: (isTinted ? tintColor : Color.orange).opacity(0.40), radius: s * 0.05)
                .offset(x: s * 0.15, y: -s * 0.10)

            // Nuage 3D sculpté au premier plan
            CloudSculptedShape()
                .fill(cloudGrad)
                .frame(width: s * 0.68, height: s * 0.44)
                .overlay(
                    CloudSculptedShape()
                        .stroke(Color.white.opacity(0.55), lineWidth: s * 0.01)
                )
                .shadow(color: .black.opacity(0.24), radius: s * 0.04, y: s * 0.025)
                .offset(x: -s * 0.04, y: s * 0.07)
        }
    }

    // 6. MAPS / PLANS (Photo 1 Droite Col 4 : Fond routier + Badge flèche de navigation)
    private func mapsBackgroundCanvas(size s: CGFloat) -> some View {
        let isDarkMap = (style == .dark || style == .clearDark)
        return ZStack {
            // Fond de carte
            (isDarkMap ? Color(red: 0.12, green: 0.13, blue: 0.17) : Color(red: 0.95, green: 0.62, blue: 0.78))

            // Zone verte parc à droite
            Path { path in
                path.move(to: CGPoint(x: s * 0.42, y: 0))
                path.addLine(to: CGPoint(x: s, y: 0))
                path.addLine(to: CGPoint(x: s, y: s))
                path.addLine(to: CGPoint(x: s * 0.42, y: s * 0.48))
                path.closeSubpath()
            }
            .fill(isDarkMap ? Color(red: 0.16, green: 0.20, blue: 0.18) : Color(red: 0.28, green: 0.86, blue: 0.45))

            // Anneaux concentriques en haut à droite
            Circle()
                .stroke(Color.white.opacity(isDarkMap ? 0.14 : 0.45), lineWidth: s * 0.035)
                .frame(width: s * 0.55, height: s * 0.55)
                .offset(x: s * 0.42, y: -s * 0.35)
            Circle()
                .stroke(Color.white.opacity(isDarkMap ? 0.14 : 0.45), lineWidth: s * 0.035)
                .frame(width: s * 0.35, height: s * 0.35)
                .offset(x: s * 0.42, y: -s * 0.35)

            // Route diagonale jaune en bas
            Path { path in
                path.move(to: CGPoint(x: s * 0.15, y: s * 0.45))
                path.addLine(to: CGPoint(x: s * 0.85, y: s))
            }
            .stroke(isDarkMap ? Color(red: 0.25, green: 0.24, blue: 0.28) : Color(red: 1.00, green: 0.82, blue: 0.08), lineWidth: s * 0.18)

            // Autoroute verticale bleue à gauche
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.08, green: 0.58, blue: 0.98), Color(red: 0.04, green: 0.42, blue: 0.88)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: s * 0.22, height: s)
                .offset(x: -s * 0.14)
        }
    }

    private func mapsNavigationGlyph(size s: CGFloat) -> some View {
        let isTinted = (style == .tinted)
        return ZStack {
            // Anneau externe vitré autour du badge
            Circle()
                .fill(Color.white.opacity(0.22))
                .frame(width: s * 0.54, height: s * 0.54)
                .overlay(Circle().stroke(Color.white.opacity(0.45), lineWidth: s * 0.012))

            // Cercle bleu vif
            Circle()
                .fill(
                    LinearGradient(
                        colors: isTinted
                            ? [tintColor, tintColor.opacity(0.65)]
                            : [Color(red: 0.15, green: 0.68, blue: 1.00), Color(red: 0.02, green: 0.46, blue: 0.96)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: s * 0.44, height: s * 0.44)
                .shadow(color: .black.opacity(0.28), radius: s * 0.03, y: s * 0.015)

            // Flèche de navigation blanche pointant vers le haut
            NavigationArrowShape()
                .fill(Color.white)
                .frame(width: s * 0.22, height: s * 0.24)
                .offset(y: -s * 0.01)
        }
        .offset(x: -s * 0.14, y: s * 0.12)
    }

    // 7. APP STORE (Photo 2 : 3 bâtons bleus entrecroisés formant le "A")
    private func appStoreSticksGlyph(size s: CGFloat) -> some View {
        let isTinted = (style == .tinted)
        let barW = s * 0.115
        let barLen = s * 0.62
        let blueTop = isTinted ? tintColor : Color(red: 0.12, green: 0.72, blue: 1.00)
        let blueBot = isTinted ? tintColor.opacity(0.65) : Color(red: 0.02, green: 0.44, blue: 0.96)
        let stickGrad = LinearGradient(colors: [blueTop, blueBot], startPoint: .top, endPoint: .bottom)

        return ZStack {
            // Barre horizontale
            Capsule(style: .continuous)
                .fill(stickGrad)
                .frame(width: s * 0.58, height: barW)
                .offset(y: s * 0.11)
                .shadow(color: .black.opacity(0.18), radius: s * 0.02, y: s * 0.01)

            // Barre diagonale gauche (montante)
            Capsule(style: .continuous)
                .fill(stickGrad)
                .frame(width: barW, height: barLen)
                .rotationEffect(.degrees(28))
                .offset(x: -s * 0.07, y: -s * 0.01)
                .shadow(color: .black.opacity(0.18), radius: s * 0.02, y: s * 0.01)

            // Barre diagonale droite (descendante)
            Capsule(style: .continuous)
                .fill(stickGrad)
                .frame(width: barW, height: barLen)
                .rotationEffect(.degrees(-28))
                .offset(x: s * 0.07, y: -s * 0.01)
                .shadow(color: .black.opacity(0.20), radius: s * 0.02, y: s * 0.01)
        }
    }

    // 8. CALENDAR DOT MATRIX (Photo 2 : Grille de points avec le point du jour en rouge vif)
    private func calendarDotMatrixGlyph(size s: CGFloat) -> some View {
        let isTinted = (style == .tinted)
        let isDarkBg = (style == .dark || style == .clearDark || style == .tinted)
        let dotColor = isTinted
            ? tintColor.opacity(0.55)
            : (isDarkBg ? Color.white.opacity(0.75) : Color(red: 0.12, green: 0.11, blue: 0.10))
        let redDotColor = isTinted ? Color.white : Color(red: 1.00, green: 0.16, blue: 0.16)
        let spacingX = s * 0.092
        let spacingY = s * 0.125
        let dotSize = s * 0.044

        return ZStack {
            // Si le style n'a pas déjà dessiné le bandeau rouge en haut, on l'ajoute
            if style != .classicApple && style != .light && style != .frostedGlass {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(isTinted ? tintColor.opacity(0.85) : Color(red: 1.00, green: 0.15, blue: 0.28))
                        .frame(height: s * 0.26)
                    Spacer()
                }
            }

            // Matrice 7 colonnes × 3 rangées (fidèle à la Photo 2)
            VStack(spacing: spacingY) {
                // Rangée 1 : 5 points alignés à droite (début de mois)
                HStack(spacing: spacingX) {
                    ForEach(0..<7, id: \.self) { col in
                        Circle()
                            .fill(col < 2 ? Color.clear : dotColor)
                            .frame(width: dotSize, height: dotSize)
                    }
                }
                // Rangée 2 : 7 points dont le 5e est le grand point rouge lumineux !
                HStack(spacing: spacingX) {
                    ForEach(0..<7, id: \.self) { col in
                        if col == 4 {
                            Circle()
                                .fill(redDotColor)
                                .frame(width: dotSize * 1.65, height: dotSize * 1.65)
                                .shadow(color: redDotColor.opacity(0.65), radius: s * 0.025)
                        } else {
                            Circle()
                                .fill(dotColor)
                                .frame(width: dotSize, height: dotSize)
                        }
                    }
                }
                // Rangée 3 : 5 points alignés à gauche (fin de mois)
                HStack(spacing: spacingX) {
                    ForEach(0..<7, id: \.self) { col in
                        Circle()
                            .fill(col < 5 ? dotColor : Color.clear)
                            .frame(width: dotSize, height: dotSize)
                    }
                }
            }
            .offset(y: s * 0.11)
        }
    }

    // 9. PHONE (Photo 4 Col 1 : Combiné téléphonique vert 3D brillant)
    private func phoneHandsetGlyph(size s: CGFloat) -> some View {
        let isTinted = (style == .tinted)
        let greenGrad = isTinted
            ? LinearGradient(colors: [tintColor, tintColor.opacity(0.60)], startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(
                colors: [
                    Color(red: 0.25, green: 0.92, blue: 0.42),
                    Color(red: 0.08, green: 0.68, blue: 0.24)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

        return Image(systemName: "phone.fill")
            .resizable()
            .scaledToFit()
            .frame(width: s * 0.54, height: s * 0.54)
            .foregroundStyle(greenGrad)
            .shadow(color: (isTinted ? tintColor : Color.green).opacity(0.35), radius: s * 0.04, y: s * 0.02)
    }

    // 10. FACETIME (Photo 4 Col 2 : Caméra vidéo verte 3D)
    private func facetimeCameraGlyph(size s: CGFloat) -> some View {
        let isTinted = (style == .tinted)
        let greenGrad = isTinted
            ? LinearGradient(colors: [tintColor, tintColor.opacity(0.60)], startPoint: .top, endPoint: .bottom)
            : LinearGradient(
                colors: [
                    Color(red: 0.22, green: 0.90, blue: 0.40),
                    Color(red: 0.06, green: 0.66, blue: 0.25)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

        return Image(systemName: "video.fill")
            .resizable()
            .scaledToFit()
            .frame(width: s * 0.58, height: s * 0.42)
            .foregroundStyle(greenGrad)
            .shadow(color: (isTinted ? tintColor : Color.green).opacity(0.35), radius: s * 0.04, y: s * 0.02)
    }

    // 11. TELEGRAM (Photo 4 Col 3 : Avion en papier blanc ciselé)
    private func telegramPaperPlaneGlyph(size s: CGFloat) -> some View {
        let isTinted = (style == .tinted)
        let planeColor = isTinted
            ? LinearGradient(colors: [tintColor, tintColor.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(
                colors: [
                    Color.white,
                    Color(red: 0.88, green: 0.90, blue: 0.95)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

        return Image(systemName: "paperplane.fill")
            .resizable()
            .scaledToFit()
            .frame(width: s * 0.52, height: s * 0.52)
            .foregroundStyle(planeColor)
            .offset(x: -s * 0.02, y: s * 0.01)
            .shadow(color: .black.opacity(0.28), radius: s * 0.03, y: s * 0.02)
    }

    // 12. MESSAGES (Photo 4 Col 4 : Bulle de discussion verte 3D brillante)
    private func messagesBubbleGlyph(size s: CGFloat) -> some View {
        let isTinted = (style == .tinted)
        let greenGrad = isTinted
            ? LinearGradient(colors: [tintColor, tintColor.opacity(0.60)], startPoint: .top, endPoint: .bottom)
            : LinearGradient(
                colors: [
                    Color(red: 0.26, green: 0.94, blue: 0.44),
                    Color(red: 0.06, green: 0.68, blue: 0.24)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

        return Image(systemName: "message.fill")
            .resizable()
            .scaledToFit()
            .frame(width: s * 0.58, height: s * 0.54)
            .foregroundStyle(greenGrad)
            .shadow(color: (isTinted ? tintColor : Color.green).opacity(0.35), radius: s * 0.04, y: s * 0.02)
    }

    // 13. BOOKS / LIVRES (Photo 4 Col 5 : Livre ouvert doré/orange avec couverture blanche)
    private func booksOpenGlyph(size s: CGFloat) -> some View {
        let isTinted = (style == .tinted)
        let pageGrad = isTinted
            ? LinearGradient(colors: [tintColor, tintColor.opacity(0.65)], startPoint: .top, endPoint: .bottom)
            : LinearGradient(
                colors: [
                    Color(red: 1.00, green: 0.92, blue: 0.72),
                    Color(red: 0.98, green: 0.64, blue: 0.16)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

        return ZStack {
            // Couverture arrière orange vif
            RoundedRectangle(cornerRadius: s * 0.04, style: .continuous)
                .fill(isTinted ? tintColor.opacity(0.45) : Color(red: 0.98, green: 0.56, blue: 0.08))
                .frame(width: s * 0.60, height: s * 0.46)
                .offset(y: s * 0.02)

            // Livre ouvert
            Image(systemName: "book.fill")
                .resizable()
                .scaledToFit()
                .frame(width: s * 0.56, height: s * 0.46)
                .foregroundStyle(pageGrad)
                .shadow(color: .black.opacity(0.25), radius: s * 0.025, y: s * 0.015)
        }
    }

    // 14. SAFARI (Boussole bleue & aiguille rouge/blanche)
    private func safariCompassGlyph(size s: CGFloat) -> some View {
        let isTinted = (style == .tinted)
        let dialGrad = isTinted
            ? LinearGradient(colors: [tintColor, tintColor.opacity(0.55)], startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [Color(red: 0.14, green: 0.72, blue: 1.0), Color(red: 0.04, green: 0.42, blue: 0.94)], startPoint: .top, endPoint: .bottom)

        return ZStack {
            Circle()
                .fill(dialGrad)
                .frame(width: s * 0.72, height: s * 0.72)
                .shadow(color: .black.opacity(0.25), radius: s * 0.03, y: s * 0.02)

            ForEach(0..<12, id: \.self) { i in
                Rectangle()
                    .fill(Color.white.opacity(0.75))
                    .frame(width: s * 0.012, height: s * 0.055)
                    .offset(y: -s * 0.30)
                    .rotationEffect(.degrees(Double(i) * 30))
            }

            // Aiguille Nord (Rouge) / Sud (Blanche)
            VStack(spacing: 0) {
                TrianglePointerShape()
                    .fill(isTinted ? Color.white : Color(red: 1.0, green: 0.23, blue: 0.19))
                    .frame(width: s * 0.09, height: s * 0.28)
                TrianglePointerShape()
                    .fill(Color.white.opacity(0.92))
                    .frame(width: s * 0.09, height: s * 0.28)
                    .rotationEffect(.degrees(180))
            }
            .rotationEffect(.degrees(45))
        }
    }

    // 15. MAIL
    private func mailEnvelopeGlyph(size s: CGFloat) -> some View {
        let isTinted = (style == .tinted)
        let grad = isTinted
            ? LinearGradient(colors: [tintColor, tintColor.opacity(0.65)], startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [Color(red: 0.15, green: 0.68, blue: 1.0), Color(red: 0.05, green: 0.46, blue: 0.96)], startPoint: .top, endPoint: .bottom)
        return Image(systemName: "envelope.fill")
            .resizable()
            .scaledToFit()
            .frame(width: s * 0.58, height: s * 0.44)
            .foregroundStyle(grad)
            .shadow(color: .black.opacity(0.22), radius: s * 0.03, y: s * 0.015)
    }

    // 16. MUSIC
    private func musicNoteGlyph(size s: CGFloat) -> some View {
        let isTinted = (style == .tinted)
        let grad = isTinted
            ? LinearGradient(colors: [tintColor, tintColor.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(colors: [Color(red: 1.0, green: 0.22, blue: 0.38), Color(red: 0.92, green: 0.12, blue: 0.56)], startPoint: .topLeading, endPoint: .bottomTrailing)
        return Image(systemName: "music.note")
            .resizable()
            .scaledToFit()
            .frame(width: s * 0.50, height: s * 0.54)
            .foregroundStyle(grad)
            .shadow(color: (isTinted ? tintColor : Color.pink).opacity(0.35), radius: s * 0.04, y: s * 0.02)
    }

    // 17. SPOTIFY
    private func spotifyGlyph(size s: CGFloat) -> some View {
        let isTinted = (style == .tinted)
        let green = isTinted ? tintColor : Color(red: 0.114, green: 0.725, blue: 0.329)
        return ZStack {
            Circle()
                .fill(green)
                .frame(width: s * 0.68, height: s * 0.68)
                .shadow(color: green.opacity(0.35), radius: s * 0.04, y: s * 0.02)
            SpotifyWavesShape()
                .stroke(Color.black.opacity(0.88), style: StrokeStyle(lineWidth: s * 0.06, lineCap: .round))
                .frame(width: s * 0.44, height: s * 0.44)
        }
    }

    // 18. FINDER
    private func finderSmileGlyph(size s: CGFloat) -> some View {
        let isTinted = (style == .tinted)
        let grad = isTinted
            ? LinearGradient(colors: [tintColor, tintColor.opacity(0.65)], startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [Color(red: 0.18, green: 0.74, blue: 1.0), Color(red: 0.04, green: 0.44, blue: 0.94)], startPoint: .top, endPoint: .bottom)
        return Image(systemName: "face.smiling.inverse")
            .resizable()
            .scaledToFit()
            .frame(width: s * 0.60, height: s * 0.60)
            .foregroundStyle(grad)
    }

    // 19. SYSTEM SETTINGS
    private func settingsGearsGlyph(size s: CGFloat) -> some View {
        let isTinted = (style == .tinted)
        let grad = isTinted
            ? LinearGradient(colors: [tintColor, tintColor.opacity(0.60)], startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [Color(white: 0.85), Color(white: 0.52)], startPoint: .top, endPoint: .bottom)
        return Image(systemName: "gearshape.2.fill")
            .resizable()
            .scaledToFit()
            .frame(width: s * 0.60, height: s * 0.60)
            .foregroundStyle(grad)
    }

    // 20. NOTES
    private func notesPadGlyph(size s: CGFloat) -> some View {
        let isTinted = (style == .tinted)
        return VStack(spacing: 0) {
            Rectangle()
                .fill(isTinted ? tintColor : Color(red: 1.0, green: 0.78, blue: 0.05))
                .frame(width: s * 0.62, height: s * 0.18)
            ZStack {
                Rectangle()
                    .fill(isTinted ? tintColor.opacity(0.35) : Color.white)
                    .frame(width: s * 0.62, height: s * 0.44)
                VStack(spacing: s * 0.08) {
                    Rectangle().fill(Color.gray.opacity(0.35)).frame(width: s * 0.46, height: s * 0.02)
                    Rectangle().fill(Color.gray.opacity(0.35)).frame(width: s * 0.46, height: s * 0.02)
                    Rectangle().fill(Color.gray.opacity(0.35)).frame(width: s * 0.46, height: s * 0.02)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: s * 0.12, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: s * 0.03, y: s * 0.015)
    }

    // 21. REMINDERS
    private func remindersListGlyph(size s: CGFloat) -> some View {
        let isTinted = (style == .tinted)
        let colors: [Color] = isTinted
            ? [tintColor, tintColor.opacity(0.8), tintColor.opacity(0.6)]
            : [Color(red: 0.05, green: 0.58, blue: 1.0), Color(red: 1.0, green: 0.25, blue: 0.22), Color(red: 1.0, green: 0.62, blue: 0.05)]
        return VStack(spacing: s * 0.09) {
            ForEach(0..<3, id: \.self) { i in
                HStack(spacing: s * 0.06) {
                    Circle().fill(colors[i]).frame(width: s * 0.11, height: s * 0.11)
                    Capsule().fill((style == .light ? Color.black : Color.white).opacity(0.65)).frame(width: s * 0.36, height: s * 0.045)
                }
            }
        }
    }

    // 22. CLOCK
    private func clockDialGlyph(size s: CGFloat) -> some View {
        let isTinted = (style == .tinted)
        return ZStack {
            Circle()
                .fill(style == .light ? Color.black : Color.white)
                .frame(width: s * 0.68, height: s * 0.68)
            Rectangle()
                .fill(style == .light ? Color.white : Color.black)
                .frame(width: s * 0.035, height: s * 0.18)
                .offset(y: -s * 0.08)
                .rotationEffect(.degrees(-60))
            Rectangle()
                .fill(style == .light ? Color.white : Color.black)
                .frame(width: s * 0.03, height: s * 0.24)
                .offset(y: -s * 0.11)
                .rotationEffect(.degrees(60))
            Circle()
                .fill(isTinted ? tintColor : Color.orange)
                .frame(width: s * 0.06, height: s * 0.06)
        }
    }

    // 23. TV
    private func tvGlyph(size s: CGFloat) -> some View {
        let isTinted = (style == .tinted)
        let fg = isTinted ? tintColor : (style == .light ? Color.black : Color.white)
        return HStack(spacing: s * 0.02) {
            Image(systemName: "apple.logo")
                .font(.system(size: s * 0.26, weight: .bold))
            Text("tv")
                .font(.system(size: s * 0.32, weight: .bold, design: .rounded))
        }
        .foregroundStyle(fg)
    }

    // 24. PODCASTS
    private func podcastsGlyph(size s: CGFloat) -> some View {
        let isTinted = (style == .tinted)
        let grad = isTinted
            ? LinearGradient(colors: [tintColor, tintColor.opacity(0.60)], startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [Color(red: 0.82, green: 0.32, blue: 1.0), Color(red: 0.54, green: 0.12, blue: 0.82)], startPoint: .top, endPoint: .bottom)
        return Image(systemName: "antenna.radiowaves.left.and.right")
            .resizable()
            .scaledToFit()
            .frame(width: s * 0.56, height: s * 0.56)
            .foregroundStyle(grad)
    }

    // 25. CALCULATOR
    private func calculatorGlyph(size s: CGFloat) -> some View {
        let isTinted = (style == .tinted)
        return Image(systemName: "plus.forwardslash.minus")
            .resizable()
            .scaledToFit()
            .frame(width: s * 0.52, height: s * 0.52)
            .foregroundStyle(isTinted ? tintColor : Color.orange)
    }

    // 26. TERMINAL
    private func terminalGlyph(size s: CGFloat) -> some View {
        let isTinted = (style == .tinted)
        return Text(">_")
            .font(.system(size: s * 0.36, weight: .heavy, design: .monospaced))
            .foregroundStyle(isTinted ? tintColor : (style == .light ? Color.black : Color.white))
            .offset(x: -s * 0.06, y: -s * 0.04)
    }

    // 27. XCODE
    private func xcodeHammerGlyph(size s: CGFloat) -> some View {
        let isTinted = (style == .tinted)
        let grad = isTinted
            ? LinearGradient(colors: [tintColor, tintColor.opacity(0.60)], startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [Color(red: 0.14, green: 0.72, blue: 1.0), Color(red: 0.04, green: 0.44, blue: 0.96)], startPoint: .top, endPoint: .bottom)
        return Image(systemName: "hammer.fill")
            .resizable()
            .scaledToFit()
            .frame(width: s * 0.54, height: s * 0.54)
            .foregroundStyle(grad)
    }

    // 28. FIND MY
    private func findMyRadarGlyph(size s: CGFloat) -> some View {
        let isTinted = (style == .tinted)
        let green = isTinted ? tintColor : Color(red: 0.20, green: 0.86, blue: 0.42)
        return ZStack {
            Circle().fill(green.opacity(0.28)).frame(width: s * 0.68, height: s * 0.68)
            Circle().fill(green.opacity(0.55)).frame(width: s * 0.42, height: s * 0.42)
            Circle().fill(isTinted ? Color.white : Color(red: 0.05, green: 0.52, blue: 1.0)).frame(width: s * 0.18, height: s * 0.18)
                .overlay(Circle().stroke(Color.white, lineWidth: s * 0.02))
        }
    }
}

// MARK: - Formes Vectorielles sur Mesure (SwiftUI Shapes)

struct HouseSilhouetteShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let roofPeakY = h * 0.04
        let eaveY = h * 0.46
        let cornerR = min(w, h) * 0.12

        path.move(to: CGPoint(x: w * 0.5, y: roofPeakY))
        path.addLine(to: CGPoint(x: w * 0.96, y: eaveY))
        path.addLine(to: CGPoint(x: w * 0.86, y: eaveY))
        path.addLine(to: CGPoint(x: w * 0.86, y: h - cornerR))
        path.addQuadCurve(to: CGPoint(x: w * 0.86 - cornerR, y: h), control: CGPoint(x: w * 0.86, y: h))
        path.addLine(to: CGPoint(x: w * 0.14 + cornerR, y: h))
        path.addQuadCurve(to: CGPoint(x: w * 0.14, y: h - cornerR), control: CGPoint(x: w * 0.14, y: h))
        path.addLine(to: CGPoint(x: w * 0.14, y: eaveY))
        path.addLine(to: CGPoint(x: w * 0.04, y: eaveY))
        path.closeSubpath()
        return path
    }
}

struct KeynoteBoardShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let insetTop = w * 0.08
        let r = min(w, h) * 0.16

        path.move(to: CGPoint(x: insetTop + r, y: 0))
        path.addLine(to: CGPoint(x: w - insetTop - r, y: 0))
        path.addQuadCurve(to: CGPoint(x: w - insetTop, y: r), control: CGPoint(x: w - insetTop, y: 0))
        path.addLine(to: CGPoint(x: w, y: h - r))
        path.addQuadCurve(to: CGPoint(x: w - r, y: h), control: CGPoint(x: w, y: h))
        path.addLine(to: CGPoint(x: r, y: h))
        path.addQuadCurve(to: CGPoint(x: 0, y: h - r), control: CGPoint(x: 0, y: h))
        path.addLine(to: CGPoint(x: insetTop, y: r))
        path.addQuadCurve(to: CGPoint(x: insetTop + r, y: 0), control: CGPoint(x: insetTop, y: 0))
        path.closeSubpath()
        return path
    }
}

struct CloudSculptedShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        path.move(to: CGPoint(x: w * 0.25, y: h * 0.92))
        path.addLine(to: CGPoint(x: w * 0.78, y: h * 0.92))
        path.addCurve(
            to: CGPoint(x: w * 0.96, y: h * 0.62),
            control1: CGPoint(x: w * 0.90, y: h * 0.92),
            control2: CGPoint(x: w * 0.96, y: h * 0.78)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.76, y: h * 0.34),
            control1: CGPoint(x: w * 0.96, y: h * 0.46),
            control2: CGPoint(x: w * 0.87, y: h * 0.35)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.34, y: h * 0.22),
            control1: CGPoint(x: w * 0.68, y: h * 0.05),
            control2: CGPoint(x: w * 0.42, y: h * 0.04)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.06, y: h * 0.58),
            control1: CGPoint(x: w * 0.16, y: h * 0.24),
            control2: CGPoint(x: w * 0.06, y: h * 0.40)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.25, y: h * 0.92),
            control1: CGPoint(x: w * 0.06, y: h * 0.78),
            control2: CGPoint(x: w * 0.14, y: h * 0.92)
        )
        path.closeSubpath()
        return path
    }
}

struct NavigationArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: w * 0.5, y: 0))
        path.addLine(to: CGPoint(x: w * 0.95, y: h * 0.95))
        path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.74))
        path.addLine(to: CGPoint(x: w * 0.05, y: h * 0.95))
        path.closeSubpath()
        return path
    }
}

struct TrianglePointerShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Gestionnaire d'Icônes Personnalisées par Application (Images & Symboles)

public struct CustomAppIconOverride: Codable, Equatable, Sendable {
    public var appID: String
    public var customImageFilename: String?
    public var symbolName: String?
    public var backgroundColorHex: String?

    public init(
        appID: String,
        customImageFilename: String? = nil,
        symbolName: String? = nil,
        backgroundColorHex: String? = nil
    ) {
        self.appID = appID
        self.customImageFilename = customImageFilename
        self.symbolName = symbolName
        self.backgroundColorHex = backgroundColorHex
    }
}

@MainActor
public final class CustomIconManager: ObservableObject {
    public static let shared = CustomIconManager()

    @Published public private(set) var overrides: [String: CustomAppIconOverride] = [:]
    @Published public var activePickerAppID: String? = nil

    private let directoryURL: URL
    private let metadataURL: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("LaunchPad/custom_icons", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.directoryURL = base
        self.metadataURL = base.appendingPathComponent("overrides.json")
        load()
    }

    public func hasOverride(for appID: String) -> Bool {
        overrides[appID] != nil
    }

    public func setCustomImage(from sourceURL: URL, for appID: String) -> Bool {
        let ext = sourceURL.pathExtension.isEmpty ? "png" : sourceURL.pathExtension.lowercased()
        let safeName = UUID().uuidString + "." + ext
        let destURL = directoryURL.appendingPathComponent(safeName)
        do {
            if let old = overrides[appID]?.customImageFilename {
                try? FileManager.default.removeItem(at: directoryURL.appendingPathComponent(old))
            }
            let accessed = sourceURL.startAccessingSecurityScopedResource()
            defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            overrides[appID] = CustomAppIconOverride(appID: appID, customImageFilename: safeName)
            save()
            IconCache.shared.invalidate([appID])
            NotificationCenter.default.post(name: .launchpadIconStyleDidChange, object: nil)
            return true
        } catch {
            return false
        }
    }

    public func setCustomSymbol(symbol: String, colorHex: String, for appID: String) {
        if let old = overrides[appID]?.customImageFilename {
            try? FileManager.default.removeItem(at: directoryURL.appendingPathComponent(old))
        }
        overrides[appID] = CustomAppIconOverride(
            appID: appID,
            customImageFilename: nil,
            symbolName: symbol,
            backgroundColorHex: colorHex
        )
        save()
        IconCache.shared.invalidate([appID])
        NotificationCenter.default.post(name: .launchpadIconStyleDidChange, object: nil)
    }

    public func removeOverride(for appID: String) {
        if let old = overrides[appID]?.customImageFilename {
            try? FileManager.default.removeItem(at: directoryURL.appendingPathComponent(old))
        }
        overrides.removeValue(forKey: appID)
        save()
        IconCache.shared.invalidate([appID])
        NotificationCenter.default.post(name: .launchpadIconStyleDidChange, object: nil)
    }

    public func removeAllOverrides() {
        for (_, ov) in overrides {
            if let file = ov.customImageFilename {
                try? FileManager.default.removeItem(at: directoryURL.appendingPathComponent(file))
            }
        }
        overrides.removeAll()
        save()
        IconCache.shared.removeAll()
        NotificationCenter.default.post(name: .launchpadIconStyleDidChange, object: nil)
    }

    nonisolated public func overrideImageURL(filename: String) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("LaunchPad/custom_icons", isDirectory: true)
        return base.appendingPathComponent(filename)
    }

    private func load() {
        guard let data = try? Data(contentsOf: metadataURL),
              let decoded = try? JSONDecoder().decode([String: CustomAppIconOverride].self, from: data) else {
            return
        }
        self.overrides = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(overrides) else { return }
        try? data.write(to: metadataURL, options: .atomic)
    }
}

// MARK: - Fenêtre de Personnalisation Simple d'une Icône d'Application

public struct AppCustomIconPickerSheet: View {
    public let appID: String
    public let appName: String
    @Binding public var isPresented: Bool

    @ObservedObject private var customManager = CustomIconManager.shared
    @State private var selectedSymbol: String = "star.fill"
    @State private var selectedColorHex: String = "#0A84FF"
    @State private var statusFeedback: String? = nil

    private let popularSymbols: [String] = [
        "star.fill", "bolt.fill", "sparkles", "terminal.fill", "paintbrush.fill",
        "music.note", "gamecontroller.fill", "camera.fill", "video.fill", "envelope.fill",
        "safari.fill", "folder.fill", "doc.text.fill", "cpu.fill", "globe",
        "bubble.left.and.bubble.right.fill", "book.fill", "hammer.fill", "heart.fill", "shield.fill"
    ]

    private let colorPalette: [(String, String, Color)] = [
        ("#0A84FF", "Bleu", Color(red: 0.04, green: 0.52, blue: 1.0)),
        ("#BF5AF2", "Violet", Color(red: 0.75, green: 0.35, blue: 0.95)),
        ("#FF9F0A", "Orange", Color(red: 1.0, green: 0.62, blue: 0.04)),
        ("#30D158", "Vert", Color(red: 0.19, green: 0.82, blue: 0.35)),
        ("#FF2D55", "Rose", Color(red: 1.0, green: 0.18, blue: 0.33)),
        ("#22D3EE", "Turquoise", Color(red: 0.13, green: 0.83, blue: 0.93)),
        ("#181920", "Obsidienne", Color(red: 0.10, green: 0.10, blue: 0.14)),
        ("#F5F6FA", "Blanc Pur", Color(red: 0.95, green: 0.96, blue: 0.98))
    ]

    public init(appID: String, appName: String, isPresented: Binding<Bool>) {
        self.appID = appID
        self.appName = appName
        self._isPresented = isPresented
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(nsImage: IconCache.shared.icon(for: appID))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Personnaliser l'icône de « \(appName) »")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Choisissez une image sur votre Mac ou créez une icône sur mesure.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.68))
                }
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Fermer")
            }

            Divider().background(Color.white.opacity(0.14))

            // Option 1 : Importer un fichier image
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("1. Utiliser une image de votre Mac")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Formats acceptés : PNG, ICNS, JPG, HEIC (haute résolution conseillée)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.62))
                }
                Spacer()
                Button {
                    chooseImageFromDisk()
                } label: {
                    Label("Choisir une image…", systemImage: "photo.badge.plus")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.white, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            // Option 2 : Créer une icône avec symbole et couleur d'arrière-plan
            VStack(alignment: .leading, spacing: 10) {
                Text("2. Ou choisir un symbole et une couleur de fond")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)

                HStack(spacing: 8) {
                    ForEach(colorPalette, id: \.0) { hex, label, color in
                        let isSelected = selectedColorHex == hex
                        Button {
                            selectedColorHex = hex
                        } label: {
                            Circle()
                                .fill(color)
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Circle().strokeBorder(isSelected ? Color.white : Color.white.opacity(0.25), lineWidth: isSelected ? 2.5 : 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(label)
                        .accessibilityLabel("Couleur \(label)")
                    }
                    Spacer()
                    Button {
                        customManager.setCustomSymbol(symbol: selectedSymbol, colorHex: selectedColorHex, for: appID)
                        statusFeedback = "Nouvelle icône appliquée !"
                    } label: {
                        Text("Appliquer ce symbole")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.accentColor, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(popularSymbols, id: \.self) { sym in
                            let isChosen = selectedSymbol == sym
                            Button {
                                selectedSymbol = sym
                            } label: {
                                Image(systemName: sym)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(isChosen ? .black : .white.opacity(0.85))
                                    .frame(width: 34, height: 34)
                                    .background(isChosen ? Color.white : Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            // Pied de page : Réinitialiser + Fermer
            HStack {
                if customManager.hasOverride(for: appID) {
                    Button(role: .destructive) {
                        customManager.removeOverride(for: appID)
                        statusFeedback = "Icône d'origine restaurée."
                    } label: {
                        Label("Rétablir l'icône d'origine", systemImage: "arrow.counterclockwise")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.red.opacity(0.9))
                    }
                    .buttonStyle(.plain)
                }
                if let statusFeedback {
                    Text(statusFeedback)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.green)
                }
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Text("Terminé")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.16), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(22)
        .frame(width: 500)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(red: 0.10, green: 0.11, blue: 0.15).opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.20), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.55), radius: 30, y: 14)
    }

    private func chooseImageFromDisk() {
        let panel = NSOpenPanel()
        panel.title = "Choisir une icône pour \(appName)"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image, .icns, .png, .jpeg, .heic, .tiff]
        if panel.runModal() == .OK, let url = panel.url {
            if customManager.setCustomImage(from: url, for: appID) {
                statusFeedback = "Image personnalisée appliquée !"
            }
        }
    }
}

// MARK: - Moteur Haute Définition 512×512 Retina (HDAppIconEngine & CustomAppIconRenderer)

public struct IconQualityReport: Sendable {
    public let totalTested: Int
    public let highResCount: Int
    public let minimumDimension: Int
    public let averageDimension: Int
}

public enum CustomAppIconRenderer {
    /// Résolution physique Retina cible (512×512 px = 256×256 pt @2x)
    public static let retinaPixelSize: Int = 512
    public static let logicalPointSize: CGFloat = 256

    /// Génère une icône haute résolution 512×512 pour n'importe quelle application et n'importe quel style
    @MainActor
    public static func renderIcon(
        for path: String,
        bundleID: String?,
        name: String,
        style: IconAppearanceStyle,
        tintColor: Color = Color(red: 0.12, green: 0.56, blue: 1.0),
        pixelSize: CGFloat = 256
    ) -> NSImage? {
        // 1. Priorité absolue : Icône personnalisée définie par l'utilisateur pour cette application
        if let override = CustomIconManager.shared.overrides[path] {
            if let customRendered = renderUserOverride(override, size: retinaPixelSize) {
                return wrapCGImageAsRetinaNSImage(customRendered)
            }
        }

        // 2. Si l'utilisateur a choisi un style vectoriel ou unifié et que l'application fait partie de notre pack vectoriel (sauf en mode Original ou Automatique macOS)
        if style != .original && style != .system,
           let customKind = CustomAppIconKind.match(path: path, bundleID: bundleID, name: name) {
            let view = CustomAppIconView(kind: customKind, style: style, tintColor: tintColor, size: logicalPointSize)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2.0 // 256pt × 2.0 = 512×512 pixels physiques Retina !
            if let cgImage = renderer.cgImage {
                return wrapCGImageAsRetinaNSImage(cgImage)
            }
        }

        // 3. Pour toutes les applications (tierces ou en mode Original / Automatique / Sombre / Clair / Teinté / Monochrome / Transparent / Verre) :
        // Extraction haute résolution (1024×1024 ou 512×512) directement depuis Assets.car / .icns / IconServices,
        // normalisation géométrique sans double-squircle, et application du filtre de style en 512×512.
        let nsTint = NSColor(tintColor).usingColorSpace(.sRGB) ?? NSColor.systemBlue
        let tintRGB = (
            r: Double(nsTint.redComponent),
            g: Double(nsTint.greenComponent),
            b: Double(nsTint.blueComponent)
        )
        if let cgImage = IconRenderer.renderStyledHighResIcon(
            for: path,
            style: style,
            tintRGB: tintRGB
        ) {
            return wrapCGImageAsRetinaNSImage(cgImage)
        }
        return nil
    }

    @MainActor
    private static func renderUserOverride(_ override: CustomAppIconOverride, size: Int) -> CGImage? {
        if let filename = override.customImageFilename {
            let fileURL = CustomIconManager.shared.overrideImageURL(filename: filename)
            if let nsImage = NSImage(contentsOf: fileURL),
               let rawCG = IconRenderer.rasterizeNSImageHighRes(nsImage, targetSize: size) {
                return IconRenderer.normalizeAndStyleCGImage(
                    rawCG,
                    style: .original,
                    tintRGB: (0.08, 0.54, 0.98),
                    forceSquircleClip: true
                )
            }
        }
        if let symbol = override.symbolName {
            let bgColor = Self.colorFromHex(override.backgroundColorHex ?? "#0A84FF")
            let isLightBg = (override.backgroundColorHex?.uppercased() == "#F5F6FA" || override.backgroundColorHex?.uppercased() == "#FFFFFF")
            let view = ZStack {
                let inset = logicalPointSize * 0.09
                let bodySize = logicalPointSize - inset * 2
                let shape = RoundedRectangle(cornerRadius: bodySize * 0.225, style: .continuous)
                shape.fill(
                    LinearGradient(
                        colors: [bgColor, bgColor.opacity(0.78)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                Image(systemName: symbol)
                    .font(.system(size: bodySize * 0.46, weight: .semibold))
                    .foregroundStyle(isLightBg ? Color.black.opacity(0.85) : Color.white)
                    .shadow(color: .black.opacity(0.22), radius: 4, y: 2)
                shape.strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.55), Color.white.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
            }
            .frame(width: logicalPointSize - logicalPointSize * 0.18, height: logicalPointSize - logicalPointSize * 0.18)
            .shadow(color: .black.opacity(0.30), radius: 8, y: 4)
            .frame(width: logicalPointSize, height: logicalPointSize)

            let renderer = ImageRenderer(content: view)
            renderer.scale = 2.0
            return renderer.cgImage
        }
        return nil
    }

    public static func wrapCGImageAsRetinaNSImage(_ cgImage: CGImage) -> NSImage {
        let rep = NSBitmapImageRep(cgImage: cgImage)
        rep.size = NSSize(width: logicalPointSize, height: logicalPointSize)
        let image = NSImage(size: NSSize(width: logicalPointSize, height: logicalPointSize))
        image.addRepresentation(rep)
        return image
    }

    private static func colorFromHex(_ hex: String) -> Color {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }

    /// Auto-test de validation de la qualité et de la résolution des icônes (Section 9)
    @MainActor
    public static func validateCatalogIcons(paths: [String]) -> IconQualityReport {
        var highRes = 0
        var minDim = Int.max
        var sumDim = 0
        let sample = Array(paths.prefix(24))
        for path in sample {
            let img = IconCache.shared.icon(for: path)
            let maxRepW = img.representations.map(\.pixelsWide).max() ?? Int(img.size.width)
            if maxRepW >= 512 {
                highRes += 1
            }
            minDim = min(minDim, maxRepW)
            sumDim += maxRepW
        }
        let count = max(1, sample.count)
        return IconQualityReport(
            totalTested: sample.count,
            highResCount: highRes,
            minimumDimension: minDim == Int.max ? 0 : minDim,
            averageDimension: sumDim / count
        )
    }
}
