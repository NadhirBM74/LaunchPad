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
        loc("icon_style.\(rawValue).title")
    }

    public var subtitle: String {
        loc("icon_style.\(rawValue).desc")
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

    /// Indique si le style applique un rendu vitré / transparent sur les icônes (réservé à la licence Pro).
    nonisolated public var isTransparentGlassStyle: Bool {
        switch self {
        case .transparent, .clearDark, .frostedGlass, .clearLiquid:
            return true
        case .original, .dark, .light, .tinted, .monochrome, .classicApple, .system:
            return false
        }
    }

    /// Indique si le style d'icône nécessite une licence Pro active.
    nonisolated public var requiresPro: Bool {
        isTransparentGlassStyle || self == .tinted
    }

    /// Indique si ce thème utilise le rendu optique Liquid Glass « Cristal Pur » (sans transparence pour les comptes gratuits).
    nonisolated public func usesCrystalGlassBackdrop(isPro: Bool) -> Bool {
        switch self {
        case .transparent, .clearDark, .frostedGlass, .clearLiquid:
            return true
        case .dark, .light, .tinted, .monochrome, .classicApple:
            return isPro
        case .original, .system:
            return false
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
        case .home: return loc("app_sample.home")
        case .keynote: return "Keynote"
        case .weather: return loc("app_sample.weather")
        case .maps: return loc("app_sample.maps")
        case .appStore: return "App Store"
        case .calendar: return loc("widget.cat.calendar")
        case .phone: return "Phone"
        case .facetime: return "FaceTime"
        case .telegram: return "Telegram"
        case .messages: return "Messages"
        case .books: return "Books"
        case .safari: return "Safari"
        case .mail: return "Mail"
        case .music: return loc("app_sample.music")
        case .spotify: return "Spotify"
        case .finder: return "Finder"
        case .settings: return loc("app_sample.settings")
        case .notes: return loc("app_sample.notes")
        case .reminders: return loc("app_sample.reminders")
        case .clock: return loc("app_sample.clock")
        case .tv: return "TV"
        case .podcasts: return "Podcasts"
        case .calculator: return loc("app_sample.calculator")
        case .terminal: return "Terminal"
        case .xcode: return "Xcode"
        case .findMy: return loc("app_sample.findmy")
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

public struct CustomAppIconView: View, Equatable {
    public let kind: CustomAppIconKind
    public var style: IconAppearanceStyle = .dark
    public var tintColor: Color = Color(red: 0.12, green: 0.56, blue: 1.0)
    public var size: CGFloat = 128
    public var isPro: Bool = false
    public var glassIntensity: Double = CrystalGlassSpec.currentGlassIntensity

    private var usesCrystalPreview: Bool {
        style.usesCrystalGlassBackdrop(isPro: isPro || style.requiresPro)
    }

    public init(
        kind: CustomAppIconKind,
        style: IconAppearanceStyle = .dark,
        tintColor: Color = Color(red: 0.12, green: 0.56, blue: 1.0),
        size: CGFloat = 128,
        isPro: Bool = false,
        glassIntensity: Double = CrystalGlassSpec.currentGlassIntensity
    ) {
        self.kind = kind
        self.style = style
        self.tintColor = tintColor
        self.size = size
        self.isPro = isPro
        self.glassIntensity = glassIntensity
    }

    public static func == (lhs: CustomAppIconView, rhs: CustomAppIconView) -> Bool {
        lhs.kind == rhs.kind
            && lhs.style == rhs.style
            && lhs.size == rhs.size
            && lhs.isPro == rhs.isPro
            && lhs.glassIntensity == rhs.glassIntensity
            && (lhs.style != .tinted || lhs.tintColor == rhs.tintColor)
    }

    private var inset: CGFloat { size * 0.09 }
    private var bodySize: CGFloat { size - inset * 2 }
    private var cornerRadius: CGFloat { bodySize * 0.228 }

    public var body: some View {
        let s = bodySize
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let crystalSpec: CrystalGlassSpec? = (usesCrystalPreview || style.isTransparentGlassStyle)
            ? CrystalGlassSpec.resolve(style: style, tintColor: tintColor, glassIntensity: glassIntensity)
            : nil

        ZStack {
            // 1. Fond Squircle selon le style (Dark, Light, Tinted, Clear Glass, Frosted Glass, Classic)
            squircleBackground(size: s, shape: shape, crystalSpec: crystalSpec)

            // 2. Contenu Vectoriel Spécifique à l'Application (aplati en texture Metal unique)
            iconGlyphContent(size: s)
                .frame(width: s, height: s)
                .saturation(style == .monochrome ? 0.0 : 1.0)
                .contrast(style == .monochrome ? 1.12 : 1.0)
                .drawingGroup()
                .clipShape(shape)

            // 3. Reflet Spéculaire de Verre & Bordure Lumineuse (selon le style)
            squircleGlassOverlay(size: s, shape: shape, crystalSpec: crystalSpec)
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
    private func squircleBackground(size s: CGFloat, shape: RoundedRectangle, crystalSpec: CrystalGlassSpec?) -> some View {
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
                .drawingGroup()
                .clipShape(shape)
        } else if usesCrystalPreview && style != .classicApple, let spec = crystalSpec {
            ZStack {
                CrystalGlassBackdrop(shape: shape, spec: spec)
                if style == .dark {
                    ambientGlowForDarkIcon(size: s)
                        .opacity(0.65)
                        .clipShape(shape)
                }
            }
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

            case .clearDark, .frostedGlass, .clearLiquid, .transparent:
                if let spec = crystalSpec {
                    CrystalGlassBackdrop(shape: shape, spec: spec)
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
    private func squircleGlassOverlay(size s: CGFloat, shape: RoundedRectangle, crystalSpec: CrystalGlassSpec?) -> some View {
        if usesCrystalPreview {
            CrystalGlassBackdrop.specularRim(
                shape: shape,
                spec: crystalSpec ?? CrystalGlassSpec.resolve(style: style, tintColor: tintColor),
                lineWidth: max(0.95, s * 0.0155)
            )
        } else {
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

    private nonisolated static let sharedDirectoryURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("LaunchPad/custom_icons", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    private nonisolated static let sharedMetadataURL: URL = {
        sharedDirectoryURL.appendingPathComponent("overrides.json")
    }()

    private let directoryURL: URL
    private let metadataURL: URL
    private let ioQueue = DispatchQueue(label: "launchpad.customicons.io", qos: .utility)

    private init() {
        self.directoryURL = Self.sharedDirectoryURL
        self.metadataURL = Self.sharedMetadataURL
        load()
    }

    public func hasOverride(for appID: String) -> Bool {
        overrides[appID] != nil
    }

    nonisolated private static func persistNormalizedCustomImage(from sourceURL: URL, to directoryURL: URL) -> String? {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }

        let ext = sourceURL.pathExtension.isEmpty ? "png" : sourceURL.pathExtension.lowercased()
        if ext != "icns",
           let imgSource = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) {
            let props = CGImageSourceCopyPropertiesAtIndex(imgSource, 0, nil) as? [CFString: Any]
            let pw = (props?[kCGImagePropertyPixelWidth] as? Int) ?? 0
            let ph = (props?[kCGImagePropertyPixelHeight] as? Int) ?? 0
            if max(pw, ph) > 512 {
                let opts: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 512,
                    kCGImageSourceCreateThumbnailWithTransform: true
                ]
                if let thumb = CGImageSourceCreateThumbnailAtIndex(imgSource, 0, opts as CFDictionary),
                   let pngData = NSBitmapImageRep(cgImage: thumb).representation(using: .png, properties: [:]) {
                    let safeName = UUID().uuidString + ".png"
                    let destURL = directoryURL.appendingPathComponent(safeName)
                    do {
                        try pngData.write(to: destURL, options: .atomic)
                        return safeName
                    } catch {
                        return nil
                    }
                }
            }
        }

        let safeName = UUID().uuidString + "." + ext
        let destURL = directoryURL.appendingPathComponent(safeName)
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            return safeName
        } catch {
            return nil
        }
    }

    public func setCustomImageAsync(from sourceURL: URL, for appID: String) async -> Bool {
        let dirURL = directoryURL
        let savedName = await Task.detached(priority: .userInitiated) {
            Self.persistNormalizedCustomImage(from: sourceURL, to: dirURL)
        }.value
        guard let safeName = savedName else { return false }
        if let old = overrides[appID]?.customImageFilename {
            let oldURL = directoryURL.appendingPathComponent(old)
            ioQueue.async { try? FileManager.default.removeItem(at: oldURL) }
        }
        overrides[appID] = CustomAppIconOverride(appID: appID, customImageFilename: safeName)
        save()
        IconCache.shared.invalidate([appID])
        NotificationCenter.default.post(name: .launchpadCustomIconDidChange, object: appID)
        return true
    }

    public func setCustomImage(from sourceURL: URL, for appID: String) -> Bool {
        guard let safeName = Self.persistNormalizedCustomImage(from: sourceURL, to: directoryURL) else {
            return false
        }
        if let old = overrides[appID]?.customImageFilename {
            let oldURL = directoryURL.appendingPathComponent(old)
            ioQueue.async { try? FileManager.default.removeItem(at: oldURL) }
        }
        overrides[appID] = CustomAppIconOverride(appID: appID, customImageFilename: safeName)
        save()
        IconCache.shared.invalidate([appID])
        NotificationCenter.default.post(name: .launchpadCustomIconDidChange, object: appID)
        return true
    }

    public func setCustomSymbol(symbol: String, colorHex: String, for appID: String) {
        if let old = overrides[appID]?.customImageFilename {
            let oldURL = directoryURL.appendingPathComponent(old)
            ioQueue.async { try? FileManager.default.removeItem(at: oldURL) }
        }
        overrides[appID] = CustomAppIconOverride(
            appID: appID,
            customImageFilename: nil,
            symbolName: symbol,
            backgroundColorHex: colorHex
        )
        save()
        IconCache.shared.invalidate([appID])
        NotificationCenter.default.post(name: .launchpadCustomIconDidChange, object: appID)
    }

    public func removeOverride(for appID: String) {
        if let old = overrides[appID]?.customImageFilename {
            let oldURL = directoryURL.appendingPathComponent(old)
            ioQueue.async { try? FileManager.default.removeItem(at: oldURL) }
        }
        overrides.removeValue(forKey: appID)
        save()
        IconCache.shared.invalidate([appID])
        NotificationCenter.default.post(name: .launchpadCustomIconDidChange, object: appID)
    }

    public func removeAllOverrides() {
        let oldFiles = overrides.values.compactMap(\.customImageFilename)
        let affectedIDs = Array(overrides.keys)
        let dirURL = directoryURL
        if !oldFiles.isEmpty {
            ioQueue.async {
                for file in oldFiles {
                    try? FileManager.default.removeItem(at: dirURL.appendingPathComponent(file))
                }
            }
        }
        overrides.removeAll()
        save()
        IconCache.shared.invalidate(affectedIDs)
        NotificationCenter.default.post(name: .launchpadCustomIconDidChange, object: affectedIDs)
    }

    nonisolated public static func overrideImageURL(filename: String) -> URL {
        sharedDirectoryURL.appendingPathComponent(filename)
    }

    private func load() {
        guard let data = try? Data(contentsOf: metadataURL),
              let decoded = try? JSONDecoder().decode([String: CustomAppIconOverride].self, from: data) else {
            return
        }
        self.overrides = decoded
    }

    private func save() {
        let snapshot = overrides
        let targetURL = metadataURL
        ioQueue.async {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: targetURL, options: .atomic)
        }
    }
}

// MARK: - Fenêtre de Personnalisation Simple d'une Icône d'Application

public struct AppCustomIconPickerSheet: View {
    public let appID: String
    public let appName: String
    @Binding public var isPresented: Bool

    @ObservedObject private var customManager = CustomIconManager.shared
    @ObservedObject private var locManager = LocalizationManager.shared
    @State private var selectedSymbol: String = "star.fill"
    @State private var selectedColorHex: String = "#0A84FF"
    @State private var statusFeedback: String? = nil
    @State private var previewImage: NSImage? = nil

    private let popularSymbols: [String] = [
        "star.fill", "bolt.fill", "sparkles", "terminal.fill", "paintbrush.fill",
        "music.note", "gamecontroller.fill", "camera.fill", "video.fill", "envelope.fill",
        "safari.fill", "folder.fill", "doc.text.fill", "cpu.fill", "globe",
        "bubble.left.and.bubble.right.fill", "book.fill", "hammer.fill", "heart.fill", "shield.fill"
    ]

    private static let colorPalette: [(hex: String, labelKey: String, color: Color)] = [
        ("#0A84FF", "custom_icon.color.blue", Color(red: 0.04, green: 0.52, blue: 1.0)),
        ("#BF5AF2", "custom_icon.color.purple", Color(red: 0.75, green: 0.35, blue: 0.95)),
        ("#FF9F0A", "custom_icon.color.orange", Color(red: 1.0, green: 0.62, blue: 0.04)),
        ("#30D158", "custom_icon.color.green", Color(red: 0.19, green: 0.82, blue: 0.35)),
        ("#FF2D55", "custom_icon.color.pink", Color(red: 1.0, green: 0.18, blue: 0.33)),
        ("#22D3EE", "custom_icon.color.cyan", Color(red: 0.13, green: 0.83, blue: 0.93)),
        ("#181920", "custom_icon.color.obsidian", Color(red: 0.10, green: 0.10, blue: 0.14)),
        ("#F5F6FA", "custom_icon.color.pure_white", Color(red: 0.95, green: 0.96, blue: 0.98))
    ]

    public init(appID: String, appName: String, isPresented: Binding<Bool>) {
        self.appID = appID
        self.appName = appName
        self._isPresented = isPresented
    }

    @AppStorage(PrefKey.backgroundStyle) private var backgroundStyle: BackgroundStyle = .liquidGlass

    public var body: some View {
        VelvetAuraModalContainer(cornerRadius: 22) { aura in
            VStack(alignment: .leading, spacing: 16) {
                // En-tête unifié 4C avec pilule ESC (aucun bouton Fermer)
                HStack(spacing: 12) {
                    LiveAppIconView(image: previewImage ?? IconCache.shared.icon(for: appID), size: 54)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc("icon_picker.title", appName))
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(aura.primaryText)
                            .lineLimit(1)
                        Text(loc("icon_picker.subtitle"))
                            .font(.system(size: 12))
                            .foregroundStyle(aura.secondaryText)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 8)

                    VelvetAuraEscapePill()
                }

                Rectangle()
                    .fill(aura.divider)
                    .frame(height: 1)

                // Option 1 : Importer une image sur mesure (carte Velvet 4C)
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(loc("icon_picker.step1"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(aura.primaryText)
                        Text(loc("icon_picker.formats"))
                            .font(.system(size: 11.5))
                            .foregroundStyle(aura.secondaryText)
                    }
                    Spacer()
                    Button {
                        chooseImageFromDisk()
                    } label: {
                        Label(loc("icon_picker.choose_image"), systemImage: "photo.badge.plus")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(aura.accentGradient, in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.24), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                .padding(14)
                .background(VelvetAuraCardBackground(theme: backgroundStyle, cornerRadius: 14))
                .overlay(VelvetAuraCardOverlay(theme: backgroundStyle, cornerRadius: 14))

                // Option 2 : Créer une icône avec symbole et couleur d'arrière-plan (carte Velvet 4C)
                VStack(alignment: .leading, spacing: 11) {
                    Text(loc("icon_picker.step2"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(aura.primaryText)

                    HStack(spacing: 8) {
                        ForEach(Self.colorPalette, id: \.hex) { entry in
                            let isSelected = selectedColorHex == entry.hex
                            let label = loc(entry.labelKey)
                            Button {
                                selectedColorHex = entry.hex
                            } label: {
                                Circle()
                                    .fill(entry.color)
                                    .frame(width: 24, height: 24)
                                    .overlay(
                                        Circle().strokeBorder(isSelected ? aura.primaryText : aura.pillBorder, lineWidth: isSelected ? 2.5 : 1)
                                    )
                                    .scaleEffect(isSelected ? 1.12 : 1.0)
                            }
                            .buttonStyle(.plain)
                            .help(label)
                            .accessibilityLabel(loc("icon_picker.color_a11y", label))
                        }
                        Spacer()
                        Button {
                            customManager.setCustomSymbol(symbol: selectedSymbol, colorHex: selectedColorHex, for: appID)
                            previewImage = IconCache.shared.icon(for: appID)
                            statusFeedback = loc("icon_picker.applied_symbol")
                        } label: {
                            Text(loc("icon_picker.apply_symbol"))
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 7)
                                .background(aura.accentGradient, in: Capsule())
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.9))
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
                                        .foregroundStyle(isChosen ? .white : aura.primaryText.opacity(0.85))
                                        .frame(width: 34, height: 34)
                                        .background(
                                            isChosen ? AnyShapeStyle(aura.accentGradient) : AnyShapeStyle(aura.pillFill),
                                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                                .strokeBorder(isChosen ? aura.accent : aura.pillBorder, lineWidth: isChosen ? 1.2 : 0.8)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(14)
                .background(VelvetAuraCardBackground(theme: backgroundStyle, cornerRadius: 14))
                .overlay(VelvetAuraCardOverlay(theme: backgroundStyle, cornerRadius: 14))

                // Pied de page : Réinitialiser + Feedback (fermeture uniquement par Échap)
                if customManager.hasOverride(for: appID) || statusFeedback != nil {
                    HStack {
                        if customManager.hasOverride(for: appID) {
                            Button(role: .destructive) {
                                customManager.removeOverride(for: appID)
                                previewImage = IconCache.shared.icon(for: appID)
                                statusFeedback = loc("icon_picker.restored")
                            } label: {
                                Label(loc("menu.restore_icon"), systemImage: "arrow.counterclockwise")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.red.opacity(0.92))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.red.opacity(0.12), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                        if let statusFeedback {
                            HStack(spacing: 5) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 12))
                                Text(statusFeedback)
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundStyle(.green)
                        }
                    }
                }
            }
            .padding(22)
            .frame(width: 530)
        }
        .onAppear { previewImage = IconCache.shared.icon(for: appID) }
        .onChange(of: customManager.overrides[appID]) { _, _ in
            previewImage = IconCache.shared.icon(for: appID)
        }
    }

    private func chooseImageFromDisk() {
        let panel = NSOpenPanel()
        panel.title = loc("icon_picker.panel_title", appName)
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image, .icns, .png, .jpeg, .heic, .tiff]
        panel.level = .modalPanel
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                if await customManager.setCustomImageAsync(from: url, for: appID) {
                    previewImage = IconCache.shared.icon(for: appID)
                    statusFeedback = loc("icon_picker.applied_image")
                }
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
    nonisolated public static let retinaPixelSize: Int = 512
    nonisolated public static let logicalPointSize: CGFloat = 256
    nonisolated private static let sRGBColorSpace = CGColorSpace(name: CGColorSpace.sRGB)

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

        // 2. Conservation intégrale des vrais logos Apple & applications tierces en 512×512 Retina :
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

    nonisolated private static func makeContinuousSquirclePath(in rect: CGRect, cornerRatio: CGFloat = 0.225) -> CGPath {
        let path = CGMutablePath()
        let w = rect.width
        let h = rect.height
        let minDim = min(w, h)
        let r = minDim * cornerRatio
        let rawC = r * 1.52866494
        let c = min(minDim * 0.5, rawC)
        let s = rawC > 0 ? (c / rawC) : 1.0
        let k1 = r * 1.0884900 * s
        let k2 = r * 0.8684070 * s
        let k3 = r * 0.6314940 * s
        let k4 = r * 0.0749114 * s
        let k5 = r * 0.3728240 * s
        let k6 = r * 0.1690600 * s

        let minX = rect.minX, maxX = rect.maxX
        let minY = rect.minY, maxY = rect.maxY

        path.move(to: CGPoint(x: maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: maxX, y: maxY - c))
        path.addCurve(to: CGPoint(x: maxX - k4, y: maxY - k3), control1: CGPoint(x: maxX, y: maxY - k1), control2: CGPoint(x: maxX, y: maxY - k2))
        path.addCurve(to: CGPoint(x: maxX - k3, y: maxY - k4), control1: CGPoint(x: maxX - k6, y: maxY - k5), control2: CGPoint(x: maxX - k5, y: maxY - k6))
        path.addCurve(to: CGPoint(x: maxX - c, y: maxY), control1: CGPoint(x: maxX - k2, y: maxY), control2: CGPoint(x: maxX - k1, y: maxY))

        path.addLine(to: CGPoint(x: minX + c, y: maxY))
        path.addCurve(to: CGPoint(x: minX + k3, y: maxY - k4), control1: CGPoint(x: minX + k1, y: maxY), control2: CGPoint(x: minX + k2, y: maxY))
        path.addCurve(to: CGPoint(x: minX + k4, y: maxY - k3), control1: CGPoint(x: minX + k5, y: maxY - k6), control2: CGPoint(x: minX + k6, y: maxY - k5))
        path.addCurve(to: CGPoint(x: minX, y: maxY - c), control1: CGPoint(x: minX, y: maxY - k2), control2: CGPoint(x: minX, y: maxY - k1))

        path.addLine(to: CGPoint(x: minX, y: minY + c))
        path.addCurve(to: CGPoint(x: minX + k4, y: minY + k3), control1: CGPoint(x: minX, y: minY + k1), control2: CGPoint(x: minX, y: minY + k2))
        path.addCurve(to: CGPoint(x: minX + k3, y: minY + k4), control1: CGPoint(x: minX + k6, y: minY + k5), control2: CGPoint(x: minX + k5, y: minY + k6))
        path.addCurve(to: CGPoint(x: minX + c, y: minY), control1: CGPoint(x: minX + k2, y: minY), control2: CGPoint(x: minX + k1, y: minY))

        path.addLine(to: CGPoint(x: maxX - c, y: minY))
        path.addCurve(to: CGPoint(x: maxX - k3, y: minY + k4), control1: CGPoint(x: maxX - k1, y: minY), control2: CGPoint(x: maxX - k2, y: minY))
        path.addCurve(to: CGPoint(x: maxX - k4, y: minY + k3), control1: CGPoint(x: maxX - k5, y: minY + k6), control2: CGPoint(x: maxX - k6, y: minY + k5))
        path.addCurve(to: CGPoint(x: maxX, y: minY + c), control1: CGPoint(x: maxX, y: minY + k2), control2: CGPoint(x: maxX, y: minY + k1))
        path.closeSubpath()
        return path
    }

    nonisolated private static func rgbFromHex(_ hex: String) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        var value: UInt32 = 0
        var count = 0
        for scalar in hex.unicodeScalars {
            let v: UInt32
            switch scalar.value {
            case 48...57: v = scalar.value - 48
            case 65...70: v = scalar.value - 55
            case 97...102: v = scalar.value - 87
            default: continue
            }
            value = (value << 4) | v
            count += 1
        }
        guard count >= 6 else { return (0.04, 0.52, 1.0) }
        return (
            CGFloat((value >> 16) & 0xFF) / 255.0,
            CGFloat((value >> 8) & 0xFF) / 255.0,
            CGFloat(value & 0xFF) / 255.0
        )
    }

    nonisolated private static func renderUserOverride(_ override: CustomAppIconOverride, size: Int) -> CGImage? {
        if let filename = override.customImageFilename {
            let fileURL = CustomIconManager.overrideImageURL(filename: filename)
            if let src = CGImageSourceCreateWithURL(fileURL as CFURL, nil) {
                let opts: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: size,
                    kCGImageSourceCreateThumbnailWithTransform: true
                ]
                if let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) {
                    return IconRenderer.normalizeAndStyleCGImage(
                        thumb,
                        style: .original,
                        tintRGB: (0.08, 0.54, 0.98),
                        forceSquircleClip: true
                    )
                }
            }
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
            return renderSymbolSquircleCGImage(symbol: symbol, backgroundColorHex: override.backgroundColorHex ?? "#0A84FF", pixelDim: size)
        }
        return nil
    }

    /// Rendu CoreGraphics direct 512×512 sans dépendance `@MainActor` ni `ImageRenderer`.
    nonisolated private static func renderSymbolSquircleCGImage(
        symbol: String,
        backgroundColorHex: String,
        pixelDim: Int
    ) -> CGImage? {
        guard let cs = sRGBColorSpace,
              let ctx = CGContext(
                  data: nil,
                  width: pixelDim,
                  height: pixelDim,
                  bitsPerComponent: 8,
                  bytesPerRow: pixelDim * 4,
                  space: cs,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        ctx.interpolationQuality = .high

        let fSize = CGFloat(pixelDim)
        let inset = fSize * 0.09
        let bodyRect = CGRect(x: inset, y: inset, width: fSize - inset * 2, height: fSize - inset * 2)
        let squirclePath = makeContinuousSquirclePath(in: bodyRect, cornerRatio: 0.225)

        let rgb = rgbFromHex(backgroundColorHex)
        let cTop = CGColor(colorSpace: cs, components: [rgb.r, rgb.g, rgb.b, 1.0])!
        let cBot = CGColor(colorSpace: cs, components: [rgb.r * 0.78, rgb.g * 0.78, rgb.b * 0.78, 1.0])!

        // Ombre portée du squircle
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -fSize * 0.0156), blur: fSize * 0.03125, color: CGColor(gray: 0, alpha: 0.30))
        ctx.addPath(squirclePath)
        ctx.setFillColor(cTop)
        ctx.fillPath()
        ctx.restoreGState()

        // Dégradé principal dans le squircle
        ctx.saveGState()
        ctx.addPath(squirclePath)
        ctx.clip()
        if let bgGrad = CGGradient(colorsSpace: cs, colors: [cTop, cBot] as CFArray, locations: [0.0, 1.0]) {
            ctx.drawLinearGradient(
                bgGrad,
                start: CGPoint(x: bodyRect.minX, y: bodyRect.maxY),
                end: CGPoint(x: bodyRect.maxX, y: bodyRect.minY),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }

        // Symbole SF centré avec ombre douce
        let scale = fSize / logicalPointSize
        let ptSize = (bodyRect.width / scale) * 0.46
        if let symImg = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: ptSize, weight: .semibold)) {
            let symLogicalSize = symImg.size
            let targetW = max(1, symLogicalSize.width * scale)
            let targetH = max(1, symLogicalSize.height * scale)
            var proposed = NSRect(x: 0, y: 0, width: targetW, height: targetH)
            if let symCG = symImg.cgImage(forProposedRect: &proposed, context: nil, hints: nil) {
                let drawRect = CGRect(
                    x: (fSize - targetW) * 0.5,
                    y: (fSize - targetH) * 0.5,
                    width: targetW,
                    height: targetH
                )
                let upperHex = backgroundColorHex.uppercased()
                let isLightBg = (upperHex == "#F5F6FA" || upperHex == "#FFFFFF")
                let inkColor = isLightBg
                    ? CGColor(colorSpace: cs, components: [0, 0, 0, 0.85])!
                    : CGColor(colorSpace: cs, components: [1, 1, 1, 1])!

                ctx.saveGState()
                ctx.setShadow(offset: CGSize(width: 0, height: -2.0 * scale), blur: 4.0 * scale, color: CGColor(gray: 0, alpha: 0.22))
                ctx.beginTransparencyLayer(auxiliaryInfo: nil)
                ctx.clip(to: drawRect, mask: symCG)
                ctx.setFillColor(inkColor)
                ctx.fill(drawRect)
                ctx.endTransparencyLayer()
                ctx.restoreGState()
            }
        }
        ctx.restoreGState()

        // Bordure spéculaire diagonale
        ctx.saveGState()
        let borderWidth = 2.0 * scale
        ctx.addPath(squirclePath)
        ctx.setLineWidth(borderWidth)
        ctx.replacePathWithStrokedPath()
        ctx.clip()
        if let rimGrad = CGGradient(
            colorsSpace: cs,
            colors: [
                CGColor(colorSpace: cs, components: [1, 1, 1, 0.55])!,
                CGColor(colorSpace: cs, components: [1, 1, 1, 0.12])!
            ] as CFArray,
            locations: [0.0, 1.0]
        ) {
            ctx.drawLinearGradient(
                rimGrad,
                start: CGPoint(x: bodyRect.minX, y: bodyRect.maxY),
                end: CGPoint(x: bodyRect.maxX, y: bodyRect.minY),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }
        ctx.restoreGState()

        return ctx.makeImage()
    }

    nonisolated public static func wrapCGImageAsRetinaNSImage(_ cgImage: CGImage) -> NSImage {
        // Enveloppe zéro-copie : évite la duplication NSBitmapImageRep (~1 Mo/icône) tout en gardant la densité Retina 512×512 @2x.
        NSImage(cgImage: cgImage, size: NSSize(width: logicalPointSize, height: logicalPointSize))
    }

    /// Auto-test de validation de la qualité et de la résolution des icônes (Section 9)
    @MainActor
    public static func validateCatalogIcons(paths: [String]) -> IconQualityReport {
        var highRes = 0
        var minDim = Int.max
        var sumDim = 0
        let sample = Array(paths.prefix(24))
        for path in sample {
            let img = IconCache.shared.highResIconSync(for: path)
            let repW = img.representations.map(\.pixelsWide).max() ?? 0
            let cgW = img.cgImage(forProposedRect: nil, context: nil, hints: nil)?.width ?? 0
            let maxRepW = max(repW, max(cgW, Int(img.size.width)))
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
