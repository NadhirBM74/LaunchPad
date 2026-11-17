import SwiftUI
import Combine
import AppKit

// MARK: - 18 Thèmes de Widgets Météo (Fidèles à la Photo de Référence 5 & Direction Artistique)

public enum WeatherWidgetTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case appleMinimal = "appleMinimal"               // 1. Photo 5 Col 1 : Noir profond + lueur cuivrée + icône fine + grand 69°
    case glassmorphism = "glassmorphism"             // 2. Transparences, flou et profondeur multi-plans
    case darkPremium = "darkPremium"                 // 3. Photo 5 Col 2 & 6 : Tableau de bord sombre + barres de température
    case lightMinimal = "lightMinimal"               // 4. Photo 5 Col 6 Bas : Blanc épuré + dôme horizon + soleil rouge-orangé
    case gradient = "gradient"                       // 5. Photo 5 Col 4 Haut (Rose) & Col 3 Bas (Bleu) : +69° + soleil 3D + heures
    case weatherIllustrated = "weatherIllustrated"   // 6. Photo 5 Col 4 Bas & Col 8 Bas : Carte bicolore Jaune/Noir
    case dynamicSky = "dynamicSky"                   // 7. Photo 5 Col 5 Bas & Col 7 Haut : Ciel crépusculaire + colline + soleil
    case editorial = "editorial"                     // 8. Photo 5 Col 5 Haut, Col 7 Bas, Col 8 Haut : "69° now in New York feels 69°"
    case neon = "neon"                               // 9. Accents lumineux néon et ambiance nocturne
    case liquidGlass = "liquidGlass"                 // 10. Superposition Liquid Glass Apple
    case dashboard = "dashboard"                     // 11. Station météo complète organisée proprement
    case compact = "compact"                         // 12. Informations essentielles haute lisibilité
    case analogWeather = "analogWeather"             // 13. Instruments météorologiques analogiques à cadrans
    case nature = "nature"                           // 14. Paysages naturels et reliefs de montagnes
    case aurora = "aurora"                           // 15. Aurores boréales émeraude et violette
    case monochrome = "monochrome"                   // 16. Design suisse entièrement monochrome
    case retro = "retro"                             // 17. Appareil météo vintage à cristaux liquides
    case dynamicIsland = "dynamicIsland"             // 18. Présentation capsule interactive Dynamic Island

    public var id: String { rawValue }

    public var title: String {
        loc("weather.theme.\(rawValue).title")
    }

    public var subtitle: String {
        loc("weather.theme.\(rawValue).desc")
    }
}

// MARK: - Modèle de Données Météo Enrichies (Synchronisé avec CustomWidgetConfig)

struct RichWeatherData {
    let city: String
    let temp: Int
    let feelsLike: Int
    let high: Int
    let low: Int
    let condition: String
    let conditionDisplay: String
    let unit: String
    let humidity: Int
    let windSpeed: String
    let precipProb: Int
    let uvIndex: Int
    let sunrise: String
    let sunset: String
    let hourly: [(time: String, temp: Int, symbol: String)]
    let daily: [(day: String, symbol: String, low: Int, high: Int, barStart: CGFloat, barEnd: CGFloat)]

    static func from(config: CustomWidgetConfig) -> RichWeatherData {
        let live = WeatherService.shared.snapshot
        let t = live?.temp ?? config.weatherTemp
        let feelsLike = live?.feelsLike ?? config.weatherFeelsLike
        let high = live?.high ?? (t + 4)
        let low = live?.low ?? (t - 4)
        let cond = live?.condition ?? config.weatherCondition
        let unit = live?.unit ?? config.weatherUnit
        let resolvedCity: String = {
            if let liveCity = live?.city, !liveCity.isEmpty { return liveCity }
            let svcCity = WeatherService.shared.activeCity
            if !svcCity.isEmpty { return svcCity }
            return config.weatherCity.isEmpty ? loc("weather.city_default") : config.weatherCity
        }()

        let condDisplay: String = {
            switch cond.lowercased() {
            case "sunny": return loc("widget.weather.cond.sunny")
            case "clear": return loc("widget.weather.cond.clear")
            case "cloudy": return loc("widget.weather.cond.cloudy")
            case "rainy": return loc("widget.weather.cond.drizzle")
            case "snowy": return loc("widget.weather.cond.snow")
            case "stormy": return loc("widget.weather.cond.storm")
            default: return loc("widget.weather.cond.drizzle")
            }
        }()

        let hourly: [(String, Int, String)] = {
            if let liveHourly = live?.hourly, !liveHourly.isEmpty {
                return liveHourly.map { ($0.time, $0.temp, $0.symbol) }
            }
            return [
                ("19:00", t + 1, "cloud"),
                ("22:00", t, "cloud"),
                ("02:00", t - 2, "wind"),
                ("06:00", t - 1, "wind"),
                ("10:00", t + 2, "sun.max")
            ]
        }()

        let dayFmt = DateFormatter()
        dayFmt.locale = Locale(identifier: LocalizationManager.activeLanguageCode)
        dayFmt.dateFormat = "EEE"
        let isoFmt = DateFormatter()
        isoFmt.locale = Locale(identifier: "en_US_POSIX")
        isoFmt.dateFormat = "yyyy-MM-dd"
        let cal = Calendar.current
        let now = Date()
        func localizedWeekday(offset: Int, isoDate: String? = nil) -> String {
            let d: Date
            if let isoDate, let parsed = isoFmt.date(from: isoDate) {
                d = parsed
            } else {
                d = cal.date(byAdding: .day, value: offset, to: now) ?? now
            }
            return dayFmt.string(from: d).replacingOccurrences(of: ".", with: "").capitalized
        }

        let daily: [(String, String, Int, Int, CGFloat, CGFloat)] = {
            if let liveDaily = live?.daily, !liveDaily.isEmpty {
                let weekMin = Double(liveDaily.map(\.low).min() ?? low)
                let weekMax = Double(liveDaily.map(\.high).max() ?? high)
                let span = max(1.0, weekMax - weekMin)
                return liveDaily.enumerated().map { idx, d in
                    let start = CGFloat(max(0.0, min(0.85, (Double(d.low) - weekMin) / span)))
                    let end = CGFloat(max(Double(start) + 0.12, min(1.0, (Double(d.high) - weekMin) / span)))
                    return (localizedWeekday(offset: idx, isoDate: d.isoDate), d.symbol, d.low, d.high, start, end)
                }
            }
            return [
                (localizedWeekday(offset: 0), "cloud.rain", low, high, 0.15, 0.92),
                (localizedWeekday(offset: 1), "cloud.rain", low - 1, high - 1, 0.10, 0.68),
                (localizedWeekday(offset: 2), "sun.max", low - 2, high + 1, 0.05, 0.72),
                (localizedWeekday(offset: 3), "sun.max", low - 1, high + 2, 0.08, 0.74),
                (localizedWeekday(offset: 4), "cloud.sun", low - 1, high - 1, 0.10, 0.48),
                (localizedWeekday(offset: 5), "cloud.sun", low - 2, high, 0.06, 0.72),
                (localizedWeekday(offset: 6), "sun.max", low, high + 1, 0.14, 0.68)
            ]
        }()

        let windVal = live?.windSpeedValue ?? (unit == "C" ? 11 : 7)
        let windStr = unit == "C" ? "\(windVal) km/h" : "\(windVal) mph"

        return RichWeatherData(
            city: resolvedCity,
            temp: t,
            feelsLike: feelsLike,
            high: high,
            low: low,
            condition: cond,
            conditionDisplay: condDisplay,
            unit: unit,
            humidity: live?.humidity ?? 72,
            windSpeed: windStr,
            precipProb: live?.precipProb ?? 15,
            uvIndex: live?.uvIndex ?? 2,
            sunrise: live?.sunrise ?? "07:45",
            sunset: live?.sunset ?? "17:30",
            hourly: hourly,
            daily: daily
        )
    }

    var outlineSymbol: String {
        switch condition.lowercased() {
        case "sunny", "clear": return "sun.max"
        case "rainy": return "cloud.drizzle"
        case "snowy": return "cloud.snow"
        case "stormy": return "cloud.bolt.rain"
        default: return "cloud.drizzle"
        }
    }

    var filledSymbol: String {
        switch condition.lowercased() {
        case "sunny", "clear": return "sun.max.fill"
        case "rainy": return "cloud.rain.fill"
        case "snowy": return "cloud.snow.fill"
        case "stormy": return "cloud.bolt.rain.fill"
        default: return "cloud.rain.fill"
        }
    }
}

// MARK: - Vue Principale de la Bibliothèque Météo (18 Thèmes × 4 Formats)

struct PremiumWeatherWidgetView: View {
    let config: CustomWidgetConfig
    var targetSize: CGSize? = nil
    var isPreview: Bool = false

    @ObservedObject private var widgetManager = WidgetManager.shared
    @ObservedObject private var locManager = LocalizationManager.shared
    @ObservedObject private var weatherService = WeatherService.shared
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage(PrefKey.reduceMotion) private var userReduceMotion = false
    @State private var animateWeather = false

    private var reduceMotion: Bool { userReduceMotion || systemReduceMotion }
    private var shouldAnimateWeather: Bool {
        !reduceMotion && !isPreview && LaunchpadViewModel.isLaunchpadVisible && config.weatherTheme == .lightMinimal
    }
    private var data: RichWeatherData { RichWeatherData.from(config: config) }

    var body: some View {
        let w = targetSize?.width ?? config.size.width
        let h = targetSize?.height ?? config.size.height
        let cornerRadius = widgetManager.cornerRadius

        GeometryReader { geo in
            let availW = geo.size.width
            let availH = geo.size.height

            ZStack {
                themeContent(width: availW, height: availH)

                // Animation atmosphérique subtile selon les conditions météo
                if !reduceMotion {
                    weatherAmbientParticles(width: availW, height: availH)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: availW, height: availH)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(borderGradientForTheme, lineWidth: 1.0)
            )
            .shadow(color: .black.opacity(0.32), radius: 14, x: 0, y: 7)
        }
        .frame(width: w, height: h)
        .onAppear {
            syncWeatherAnimation(visible: LaunchpadViewModel.isLaunchpadVisible)
            weatherService.refreshIfNeeded(requestLocationPermission: !isPreview && LaunchpadViewModel.isLaunchpadVisible)
        }
        .onDisappear {
            animateWeather = false
        }
        .onChange(of: reduceMotion) { _, _ in
            syncWeatherAnimation(visible: LaunchpadViewModel.isLaunchpadVisible)
        }
        .onChange(of: config.weatherTheme) { _, _ in
            syncWeatherAnimation(visible: LaunchpadViewModel.isLaunchpadVisible)
        }
        .onReceive(NotificationCenter.default.publisher(for: .launchpadVisibilityDidChange)) { notif in
            guard let visible = notif.object as? Bool else { return }
            syncWeatherAnimation(visible: visible)
            if visible && !isPreview {
                weatherService.refreshIfNeeded(requestLocationPermission: true)
            }
        }
    }

    private func syncWeatherAnimation(visible: Bool) {
        if !reduceMotion && !isPreview && visible && config.weatherTheme == .lightMinimal {
            guard !animateWeather else { return }
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
                animateWeather = true
            }
        } else if animateWeather {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                animateWeather = false
            }
        }
    }

    private var borderGradientForTheme: LinearGradient {
        switch config.weatherTheme {
        case .lightMinimal:
            return LinearGradient(colors: [Color.black.opacity(0.08), Color.black.opacity(0.04)], startPoint: .top, endPoint: .bottom)
        case .neon:
            return LinearGradient(colors: [Color.cyan.opacity(0.85), Color.purple.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .monochrome:
            return LinearGradient(colors: [Color.white.opacity(0.9), Color.white.opacity(0.4)], startPoint: .top, endPoint: .bottom)
        default:
            return LinearGradient(colors: [Color.white.opacity(0.28), Color.white.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    @ViewBuilder
    private func themeContent(width w: CGFloat, height h: CGFloat) -> some View {
        switch config.weatherTheme {
        case .appleMinimal:
            theme1AppleMinimal(w: w, h: h)
        case .glassmorphism:
            theme2Glassmorphism(w: w, h: h)
        case .darkPremium:
            theme3DarkPremium(w: w, h: h)
        case .lightMinimal:
            theme4LightMinimal(w: w, h: h)
        case .gradient:
            theme5GradientPastel(w: w, h: h)
        case .weatherIllustrated:
            theme6WeatherIllustratedSplit(w: w, h: h)
        case .dynamicSky:
            theme7DynamicSky(w: w, h: h)
        case .editorial:
            theme8EditorialTypography(w: w, h: h)
        case .neon:
            theme9NeonNocturne(w: w, h: h)
        case .liquidGlass:
            theme10LiquidGlass(w: w, h: h)
        case .dashboard:
            theme11DashboardPro(w: w, h: h)
        case .compact:
            theme12CompactEssential(w: w, h: h)
        case .analogWeather:
            theme13AnalogInstrument(w: w, h: h)
        case .nature:
            theme14NatureLandscape(w: w, h: h)
        case .aurora:
            theme15AuroraBorealis(w: w, h: h)
        case .monochrome:
            theme16MonochromeSwiss(w: w, h: h)
        case .retro:
            theme17RetroStation(w: w, h: h)
        case .dynamicIsland:
            theme18DynamicIsland(w: w, h: h)
        }
    }

    // MARK: - Fond Sombre avec Rayon Cuivré/Bleu (Photo de Référence 5 Col 1, 2, 3, 5, 6)

    private func darkObsidianStreakBackground(w: CGFloat, h: CGFloat) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.08, blue: 0.13),
                    Color(red: 0.03, green: 0.04, blue: 0.07)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Halo bleu nuit subtil à gauche
            RadialGradient(
                colors: [Color(red: 0.14, green: 0.28, blue: 0.52).opacity(0.35), Color.clear],
                center: .leading,
                startRadius: 5,
                endRadius: max(w, h) * 0.65
            )

            // Rayon diagonal ambre/cuivre caractéristique de la Photo 5
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: Color(red: 0.78, green: 0.44, blue: 0.18).opacity(0.32), location: 0.48),
                    .init(color: Color(red: 0.95, green: 0.62, blue: 0.28).opacity(0.45), location: 0.52),
                    .init(color: .clear, location: 0.72)
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
        }
    }

    // MARK: - Thème 1 : Apple Minimal (Photo 5 Col 1 Haut/Bas & Col 3 Haut)

    private func theme1AppleMinimal(w: CGFloat, h: CGFloat) -> some View {
        let isTall = h > w * 1.15
        let isCompact = (h < 165 || w < 190) && !isTall
        let isWide = w > h * 1.25
        let pad: CGFloat = isCompact ? 11 : (isTall && w < 200 ? 12 : 16)

        return ZStack {
            darkObsidianStreakBackground(w: w, h: h)

            VStack(alignment: .leading, spacing: 0) {
                if isWide {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(data.city)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text(data.conditionDisplay)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(.white.opacity(0.65))
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: data.outlineSymbol)
                            .font(.system(size: 26, weight: .light))
                            .foregroundStyle(.white)
                    }
                } else {
                    VStack(alignment: .leading, spacing: isCompact ? 4 : 8) {
                        HStack {
                            Spacer()
                            Image(systemName: data.outlineSymbol)
                                .font(.system(size: isCompact ? 20 : 25, weight: .light))
                                .foregroundStyle(.white)
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text(data.city)
                                .font(.system(size: isCompact ? 12 : 15, weight: .medium))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text(data.conditionDisplay)
                                .font(.system(size: isCompact ? 10 : 12.5, weight: .regular))
                                .foregroundStyle(.white.opacity(0.65))
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: 4)

                Text("\(data.temp)°")
                    .font(.system(size: isCompact ? 38 : (isTall ? 46 : 54), weight: .regular, design: .default))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text("↑\(data.high)°")
                    Text("↓\(data.low)°")
                }
                .font(.system(size: isCompact ? 10 : 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))

                if isTall {
                    Divider().background(Color.white.opacity(0.14)).padding(.vertical, 8)
                    VStack(spacing: 5) {
                        ForEach(Array(data.daily.prefix(3).enumerated()), id: \.offset) { _, d in
                            HStack(spacing: 6) {
                                Text(d.day)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.72))
                                    .frame(width: 28, alignment: .leading)
                                Image(systemName: d.symbol)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.white.opacity(0.9))
                                Spacer()
                                Text("\(d.low)° / \(d.high)°")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .monospacedDigit()
                            }
                        }
                    }
                }
            }
            .padding(pad)
        }
    }

    // MARK: - Thème 2 : Glassmorphism

    private func theme2Glassmorphism(w: CGFloat, h: CGFloat) -> some View {
        let isTall = h > w * 1.15
        let isCompact = (h < 165 || w < 190) && !isTall
        return ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.22, green: 0.34, blue: 0.62).opacity(0.75),
                    Color(red: 0.12, green: 0.18, blue: 0.38).opacity(0.85)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color.orange.opacity(0.45))
                .frame(width: w * 0.55, height: w * 0.55)
                .blur(radius: 24)
                .offset(x: w * 0.25, y: -h * 0.22)

            VStack(alignment: .leading, spacing: isCompact ? 4 : 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(data.city)
                            .font(.system(size: isCompact ? 12 : 14.5, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(data.conditionDisplay)
                            .font(.system(size: isCompact ? 9.5 : 11.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                    }
                    Spacer()
                    GlowingSunCloudBadge(size: isCompact ? 26 : 36)
                }

                Spacer(minLength: 2)

                Text("\(data.temp)°")
                    .font(.system(size: isCompact ? 34 : (isTall ? 44 : 48), weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                if isTall {
                    VStack(spacing: 4) {
                        ForEach(Array(data.hourly.prefix(3).enumerated()), id: \.offset) { _, hItem in
                            HStack {
                                Text(hItem.time)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.75))
                                Spacer()
                                Image(systemName: hItem.symbol)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.white)
                                Text("\(hItem.temp)°")
                                    .font(.system(size: 10.5, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .padding(8)
                    .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                HStack(spacing: 5) {
                    glassMetricPill(icon: "drop.fill", text: "\(data.humidity)%", color: .cyan)
                    glassMetricPill(icon: "wind", text: data.windSpeed, color: .mint)
                }
            }
            .padding(isCompact ? 10 : 14)
        }
    }

    // MARK: - Thème 3 : Dark Premium Forecast

    private func theme3DarkPremium(w: CGFloat, h: CGFloat) -> some View {
        let isTall = h > w * 1.15 || h > 220
        let isCompact = h < 165 || w < 210
        let isNarrow = w < 210
        let rowCount = isTall ? 5 : 4

        return ZStack {
            darkObsidianStreakBackground(w: w, h: h)

            VStack(alignment: .leading, spacing: isCompact ? 4 : 7) {
                HStack(alignment: .center) {
                    HStack(spacing: 4) {
                        Image(systemName: data.filledSymbol)
                            .font(.system(size: isCompact ? 12 : 16))
                            .symbolRenderingMode(.multicolor)
                        Text("\(data.temp)°")
                            .font(.system(size: isCompact ? 15.5 : 20, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 0.5) {
                        Text(data.city)
                            .font(.system(size: isCompact ? 9 : 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(loc("weather.hi_lo", data.high, data.low))
                            .font(.system(size: isCompact ? 7.5 : 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.58))
                            .lineLimit(1)
                    }
                }

                if isTall {
                    HStack(spacing: 4) {
                        Label(data.sunset, systemImage: "sunset.fill")
                            .font(.system(size: isNarrow ? 7.5 : 8.5, weight: .medium))
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                        Rectangle()
                            .fill(LinearGradient(colors: [.orange.opacity(0.5), .yellow.opacity(0.5)], startPoint: .leading, endPoint: .trailing))
                            .frame(height: 1.5)
                        Label(data.sunrise, systemImage: "sunrise.fill")
                            .font(.system(size: isNarrow ? 7.5 : 8.5, weight: .medium))
                            .foregroundStyle(.yellow)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 2)

                    if isNarrow {
                        HStack(spacing: 4) {
                            darkMetricPill(icon: "drop.fill", text: "\(data.humidity)%", color: .cyan)
                            darkMetricPill(icon: "umbrella.fill", text: "\(data.precipProb)%", color: .blue)
                        }
                    } else {
                        HStack(spacing: 4) {
                            darkMetricPill(icon: "drop.fill", text: "\(data.humidity)%", color: .cyan)
                            darkMetricPill(icon: "wind", text: data.windSpeed, color: .white.opacity(0.8))
                            darkMetricPill(icon: "umbrella.fill", text: "\(data.precipProb)%", color: .blue)
                        }
                    }
                }

                Spacer(minLength: 1)

                VStack(spacing: isCompact ? 4 : 5.5) {
                    ForEach(Array(data.daily.prefix(rowCount).enumerated()), id: \.offset) { _, d in
                        dailyTemperatureBarRow(
                            day: d.day,
                            symbol: d.symbol,
                            low: d.low,
                            high: d.high,
                            barStart: d.barStart,
                            barEnd: d.barEnd,
                            isCompact: isCompact || isNarrow
                        )
                    }
                }
            }
            .padding(isCompact ? 9 : 14)
        }
    }

    // MARK: - Thème 4 : Light Minimal Horizon

    private func theme4LightMinimal(w: CGFloat, h: CGFloat) -> some View {
        let isTall = h > w * 1.15
        let isCompact = (h < 165 || w < 190) && !isTall
        return ZStack {
            Color(red: 0.96, green: 0.97, blue: 0.99)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 1.00, green: 0.25, blue: 0.04),
                            Color(red: 1.00, green: 0.55, blue: 0.20),
                            Color(red: 1.00, green: 0.75, blue: 0.55).opacity(0.2)
                        ],
                        center: .center,
                        startRadius: 2,
                        endRadius: min(w, h) * 0.24
                    )
                )
                .frame(width: min(w, h) * 0.42, height: min(w, h) * 0.42)
                .offset(x: w * 0.22, y: h * (isTall ? 0.14 : 0.04) + (animateWeather ? -3 : 3))

            HorizonDomeShape()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.95),
                            Color(red: 0.93, green: 0.95, blue: 0.98)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: .black.opacity(0.05), radius: 6, y: -2)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(data.city)
                            .font(.system(size: isCompact ? 12 : 14, weight: .semibold))
                            .foregroundStyle(Color(white: 0.12))
                            .lineLimit(1)
                        Text(data.conditionDisplay)
                            .font(.system(size: isCompact ? 9.5 : 11, weight: .regular))
                            .foregroundStyle(Color(white: 0.45))
                            .lineLimit(1)
                    }
                    Spacer()
                    Text("\(data.temp)°")
                        .font(.system(size: isCompact ? 14 : (isTall ? 24 : 16), weight: .bold))
                        .foregroundStyle(Color(white: 0.12))
                }
                if isTall {
                    Text("↑\(data.high)°  ↓\(data.low)° • \(loc("widget.weather.feels")) \(data.feelsLike)°")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color(white: 0.35))
                        .lineLimit(1)
                }
                Spacer()
                if isTall {
                    HStack(spacing: 0) {
                        ForEach(Array(data.hourly.prefix(3).enumerated()), id: \.offset) { idx, hItem in
                            if idx > 0 { Spacer(minLength: 2) }
                            VStack(spacing: 2) {
                                Text(hItem.time)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(Color(white: 0.40))
                                Image(systemName: hItem.symbol)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color(white: 0.18))
                                Text("\(hItem.temp)°")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color(white: 0.12))
                            }
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
            .padding(isCompact ? 11 : 16)
        }
    }

    // MARK: - Thème 5 : Gradient Pastel & Sky

    private func theme5GradientPastel(w: CGFloat, h: CGFloat) -> some View {
        let isWide = w > h * 1.25
        let isTall = h > w * 1.15
        let isCompact = (h < 165 || w < 180) && !isWide && !isTall
        let hourCount = isWide ? 5 : 3

        return ZStack {
            if isWide {
                LinearGradient(
                    colors: [
                        Color(red: 0.40, green: 0.56, blue: 0.70),
                        Color(red: 0.34, green: 0.49, blue: 0.64)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.97, green: 0.78, blue: 1.00),
                        Color(red: 0.95, green: 0.72, blue: 0.99)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }

            let fgColor = isWide ? Color.white : Color(white: 0.08)
            let subColor = isWide ? Color.white.opacity(0.75) : Color(white: 0.25)

            VStack(alignment: .leading, spacing: isTall ? 8 : 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("+\(data.temp)°")
                            .font(.system(size: isCompact ? 26 : 36, weight: .bold))
                            .foregroundStyle(fgColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Text(loc("weather.hi_lo", data.high, data.low))
                            .font(.system(size: isCompact ? 8.5 : 10.5, weight: .medium))
                            .foregroundStyle(subColor)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(red: 1.00, green: 0.80, blue: 0.15),
                                    Color(red: 1.00, green: 0.52, blue: 0.00)
                                ],
                                center: UnitPoint(x: 0.35, y: 0.35),
                                startRadius: 2,
                                endRadius: isCompact ? 16 : 24
                            )
                        )
                        .frame(width: isCompact ? 32 : 42, height: isCompact ? 32 : 42)
                        .shadow(color: Color.orange.opacity(0.55), radius: 8)
                }

                if isTall {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(data.city) • \(data.conditionDisplay)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(fgColor)
                            .lineLimit(1)
                        VStack(spacing: 4) {
                            ForEach(Array(data.daily.prefix(3).enumerated()), id: \.offset) { _, d in
                                HStack {
                                    Text(d.day)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(subColor)
                                        .frame(width: 28, alignment: .leading)
                                    Image(systemName: d.symbol)
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(fgColor)
                                    Spacer()
                                    Text("\(d.low)° / \(d.high)°")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(fgColor)
                                }
                            }
                        }
                        .padding(8)
                        .background(Color.white.opacity(0.28), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .padding(.top, 4)
                }

                Spacer(minLength: 4)

                HStack(spacing: 0) {
                    ForEach(Array(data.hourly.prefix(hourCount).enumerated()), id: \.offset) { idx, hItem in
                        if idx > 0 { Spacer(minLength: 2) }
                        VStack(spacing: isCompact ? 1.5 : 3) {
                            Image(systemName: hItem.symbol)
                                .font(.system(size: isCompact ? 10 : 12.5, weight: .regular))
                                .foregroundStyle(fgColor.opacity(0.85))
                            Text(hItem.time)
                                .font(.system(size: isCompact ? 8 : 9.5, weight: .bold))
                                .foregroundStyle(fgColor)
                            Text("+\(hItem.temp)°")
                                .font(.system(size: isCompact ? 7.5 : 9, weight: .medium))
                                .foregroundStyle(subColor)
                        }
                    }
                }
            }
            .padding(isCompact ? 10 : 14)
        }
    }

    // MARK: - Thème 6 : Weather Illustrated Split Card (Photo 5 Col 4 Bas & Col 8 Bas : Carte Jaune + Fond Sombre)

    private func theme6WeatherIllustratedSplit(w: CGFloat, h: CGFloat) -> some View {
        let isTall = h > 210
        let isCompact = h < 165

        return ZStack {
            Color(red: 0.05, green: 0.07, blue: 0.12)

            VStack(spacing: isCompact ? 6 : 10) {
                // Carte supérieure jaune solaire (Photo 5 Col 4 Bas & Col 8 Bas)
                ZStack {
                    RoundedRectangle(cornerRadius: isCompact ? 14 : 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 1.00, green: 0.92, blue: 0.52),
                                    Color(red: 0.98, green: 0.86, blue: 0.42)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    VStack(alignment: .leading, spacing: isCompact ? 2 : 6) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 4) {
                                    Image(systemName: data.outlineSymbol)
                                        .font(.system(size: isCompact ? 10 : 12, weight: .semibold))
                                    Text(data.conditionDisplay)
                                        .font(.system(size: isCompact ? 10 : 12, weight: .semibold))
                                }
                                .foregroundStyle(Color(white: 0.12))

                                Text("+\(data.temp)°")
                                    .font(.system(size: isCompact ? 24 : 32, weight: .bold))
                                    .foregroundStyle(Color(white: 0.06))

                                Text(data.city)
                                    .font(.system(size: isCompact ? 9.5 : 11.5, weight: .semibold))
                                    .foregroundStyle(Color(white: 0.18))
                            }
                            Spacer()
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [Color(red: 1.0, green: 0.78, blue: 0.10), Color(red: 0.98, green: 0.48, blue: 0.0)],
                                        center: .center,
                                        startRadius: 2,
                                        endRadius: 20
                                    )
                                )
                                .frame(width: isCompact ? 28 : 38, height: isCompact ? 28 : 38)
                                .shadow(color: .orange.opacity(0.5), radius: 6)
                        }
                    }
                    .padding(isCompact ? 9 : 12)
                }
                .frame(height: isTall ? h * 0.40 : h * 0.56)

                // Partie inférieure sombre : Métriques + Prévisions (Photo 5 Col 4 Bas)
                if isTall {
                    VStack(spacing: 8) {
                        VStack(spacing: 4) {
                            HStack {
                                Text(loc("widget.weather.feels").capitalized)
                                    .foregroundStyle(.white.opacity(0.70))
                                Spacer()
                                Text("+\(data.feelsLike)° 🌡")
                                    .foregroundStyle(.white)
                            }
                            HStack {
                                Text(loc("widget.weather.humidity"))
                                    .foregroundStyle(.white.opacity(0.70))
                                Spacer()
                                Text("\(data.humidity)% 💧")
                                    .foregroundStyle(.white)
                            }
                        }
                        .font(.system(size: 10.5, weight: .semibold))
                        .padding(.horizontal, 6)

                        Spacer(minLength: 0)

                        HStack(spacing: 0) {
                            ForEach(Array(data.daily.prefix(4).enumerated()), id: \.offset) { idx, d in
                                if idx > 0 { Spacer(minLength: 2) }
                                VStack(spacing: 5) {
                                    Text(idx == 0 ? loc("widget.clock.today") : d.day)
                                        .font(.system(size: 9.5, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.65))
                                    Image(systemName: d.symbol)
                                        .font(.system(size: 13))
                                        .foregroundStyle(.white)
                                    Text("+\(d.high)°")
                                        .font(.system(size: 9.5, weight: .bold))
                                        .foregroundStyle(.white)
                                    Text("+\(d.low)°")
                                        .font(.system(size: 8.5))
                                        .foregroundStyle(.white.opacity(0.50))
                                }
                            }
                        }
                        .padding(.horizontal, 4)
                        .padding(.bottom, 4)
                    }
                } else {
                    HStack {
                        Label("\(loc("widget.weather.feels").capitalized) +\(data.feelsLike)°", systemImage: "thermometer.medium")
                        Spacer()
                        Label("\(data.humidity)%", systemImage: "drop.fill")
                    }
                    .font(.system(size: isCompact ? 9 : 10.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 6)
                }
            }
            .padding(6)
        }
    }

    // MARK: - Thème 7 : Dynamic Sky Horizon (Photo 5 Col 5 Bas Crépuscule & Col 7 Haut Nuit)

    private func theme7DynamicSky(w: CGFloat, h: CGFloat) -> some View {
        let isWide = w > h * 1.25
        let isTall = h > w * 1.15
        let isCompact = (h < 165 || w < 190) && !isTall

        return ZStack {
            if isWide {
                Color(red: 0.08, green: 0.09, blue: 0.11)
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.53, green: 0.43, blue: 0.68),
                        Color(red: 0.96, green: 0.46, blue: 0.32)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 1.00, green: 0.36, blue: 0.06),
                            Color(red: 0.92, green: 0.14, blue: 0.02)
                        ],
                        center: .center,
                        startRadius: 2,
                        endRadius: min(w, h) * 0.20
                    )
                )
                .frame(width: min(w, h) * 0.36, height: min(w, h) * 0.36)
                .shadow(color: Color(red: 1.0, green: 0.25, blue: 0.05).opacity(0.6), radius: 12)
                .offset(x: w * 0.20, y: h * (isTall ? 0.14 : 0.04))

            HorizonDomeShape()
                .fill(
                    isWide
                        ? LinearGradient(colors: [Color(white: 0.22), Color(white: 0.16)], startPoint: .top, endPoint: .bottom)
                        : LinearGradient(colors: [Color(red: 0.52, green: 0.31, blue: 0.14), Color(red: 0.38, green: 0.22, blue: 0.08)], startPoint: .top, endPoint: .bottom)
                )
                .overlay(
                    HorizonDomeShape()
                        .stroke(Color.white.opacity(0.22), lineWidth: 0.8)
                )

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(data.city)
                            .font(.system(size: isCompact ? 12 : 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(data.conditionDisplay)
                            .font(.system(size: isCompact ? 9.5 : 11, weight: .regular))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                    }
                    Spacer()
                    Text("\(data.temp)°")
                        .font(.system(size: isCompact ? 14 : (isTall ? 24 : 16), weight: .bold))
                        .foregroundStyle(.white)
                }
                if isTall {
                    Text("↑\(data.high)°  ↓\(data.low)° • \(loc("widget.weather.feels")) \(data.feelsLike)°")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
                Spacer()
                if isTall {
                    HStack(spacing: 0) {
                        ForEach(Array(data.hourly.prefix(3).enumerated()), id: \.offset) { idx, hItem in
                            if idx > 0 { Spacer(minLength: 2) }
                            VStack(spacing: 2) {
                                Text(hItem.time)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.72))
                                Image(systemName: hItem.symbol)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white)
                                Text("\(hItem.temp)°")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
            .padding(isCompact ? 11 : 16)
        }
    }

    // MARK: - Thème 8 : Editorial Typography (Photo 5 Col 5 Haut, Col 7 Bas, Col 8 Haut)
    // "69° now in New York feels 69° 🌧 Drizzle"

    private func theme8EditorialTypography(w: CGFloat, h: CGFloat) -> some View {
        let isTall = h > w * 1.18
        let isWide = w > h * 1.25
        let isCompact = h < 165 && !isWide
        let fontSize: CGFloat = isTall ? min(w * 0.20, 30) : (isWide ? min(h * 0.23, 28) : (isCompact ? 18 : 22))

        return ZStack(alignment: .topLeading) {
            darkObsidianStreakBackground(w: w, h: h)

            VStack(alignment: .leading, spacing: isTall ? 4 : 2) {
                if isTall {
                    HStack(spacing: 6) {
                        Text("\(data.temp)°")
                            .foregroundStyle(.white)
                        Text(loc("widget.weather.now").lowercased())
                            .foregroundStyle(.white.opacity(0.46))
                    }
                    HStack(spacing: 6) {
                        Text(loc("widget.weather.in"))
                            .foregroundStyle(.white.opacity(0.46))
                        Text(data.city.components(separatedBy: " ").first ?? data.city)
                            .foregroundStyle(.white)
                    }
                    if data.city.components(separatedBy: " ").count > 1 {
                        Text(data.city.components(separatedBy: " ").dropFirst().joined(separator: " "))
                            .foregroundStyle(.white)
                    }
                    Text(loc("widget.weather.feels"))
                        .foregroundStyle(.white.opacity(0.46))
                    HStack(spacing: 8) {
                        Text("\(data.feelsLike)°")
                            .foregroundStyle(.white)
                        Image(systemName: data.outlineSymbol)
                            .font(.system(size: fontSize * 0.82, weight: .regular))
                            .foregroundStyle(.white)
                    }
                    Text(data.conditionDisplay)
                        .foregroundStyle(.white)
                } else {
                    HStack(spacing: 5) {
                        Text("\(data.temp)°")
                            .foregroundStyle(.white)
                        Text(loc("weather.now_in"))
                            .foregroundStyle(.white.opacity(0.46))
                    }
                    HStack(spacing: 5) {
                        Text(data.city)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if isWide {
                            Text(loc("widget.weather.feels"))
                                .foregroundStyle(.white.opacity(0.46))
                        }
                    }
                    if !isWide {
                        HStack(spacing: 5) {
                            Text(loc("widget.weather.feels"))
                                .foregroundStyle(.white.opacity(0.46))
                            Text("\(data.feelsLike)°")
                                .foregroundStyle(.white)
                        }
                    }
                    HStack(spacing: 6) {
                        if isWide {
                            Text("\(data.feelsLike)°")
                                .foregroundStyle(.white)
                        }
                        Image(systemName: data.outlineSymbol)
                            .font(.system(size: fontSize * 0.80, weight: .regular))
                            .foregroundStyle(.white)
                        Text(data.conditionDisplay)
                            .foregroundStyle(.white)
                    }
                }
            }
            .font(.system(size: fontSize, weight: .semibold))
            .minimumScaleFactor(0.65)
            .padding(isCompact ? 11 : 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    // MARK: - Thème 9 : Neon Nocturne

    private func theme9NeonNocturne(w: CGFloat, h: CGFloat) -> some View {
        let isTall = h > w * 1.15
        let isCompact = (h < 165 || w < 190) && !isTall
        return ZStack {
            Color(red: 0.03, green: 0.02, blue: 0.08)
            RadialGradient(
                colors: [Color.cyan.opacity(0.28), Color.purple.opacity(0.22), Color.clear],
                center: .topTrailing,
                startRadius: 4,
                endRadius: max(w, h) * 0.75
            )

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(data.city.uppercased())
                        .font(.system(size: isCompact ? 10 : 12, weight: .heavy, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(Color.cyan)
                        .lineLimit(1)
                        .shadow(color: .cyan.opacity(0.8), radius: 6)
                    Spacer()
                    Image(systemName: data.outlineSymbol)
                        .font(.system(size: isCompact ? 17 : 22, weight: .semibold))
                        .foregroundStyle(Color(red: 1.0, green: 0.25, blue: 0.85))
                        .shadow(color: Color.pink.opacity(0.9), radius: 8)
                }

                Spacer()

                Text("\(data.temp)°")
                    .font(.system(size: isCompact ? 36 : 48, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: Color.cyan.opacity(0.85), radius: 10)

                if isTall {
                    VStack(spacing: 4) {
                        ForEach(Array(data.hourly.prefix(3).enumerated()), id: \.offset) { _, hItem in
                            HStack {
                                Text(hItem.time)
                                    .foregroundStyle(Color.cyan.opacity(0.8))
                                Spacer()
                                Image(systemName: hItem.symbol)
                                    .foregroundStyle(.white)
                                Text("\(hItem.temp)°")
                                    .foregroundStyle(Color(red: 1.0, green: 0.35, blue: 0.88))
                            }
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                        }
                    }
                    .padding(8)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                HStack {
                    Text(data.conditionDisplay.uppercased())
                        .font(.system(size: isCompact ? 9 : 10.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(red: 1.0, green: 0.35, blue: 0.88))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(loc("weather.hi_lo", data.high, data.low))
                        .font(.system(size: isCompact ? 8.5 : 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.cyan.opacity(0.85))
                        .lineLimit(1)
                }
            }
            .padding(isCompact ? 10 : 15)
        }
    }

    // MARK: - Thème 10 : Liquid Glass

    private func theme10LiquidGlass(w: CGFloat, h: CGFloat) -> some View {
        let isTall = h > w * 1.15
        let isCompact = (h < 165 || w < 190) && !isTall
        return ZStack {
            LinearGradient(
                colors: [
                    Color.white.opacity(0.22),
                    Color(red: 0.35, green: 0.55, blue: 1.0).opacity(0.18),
                    Color.white.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .background(.ultraThinMaterial)

            VStack(alignment: .leading, spacing: isCompact ? 4 : 8) {
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 9.5, weight: .bold))
                        Text(data.city)
                            .font(.system(size: isCompact ? 11.5 : 13.5, weight: .bold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.16), in: Capsule())

                    Spacer()

                    GlowingSunCloudBadge(size: isCompact ? 26 : 34)
                }

                Spacer()

                HStack(alignment: .firstTextBaseline) {
                    Text("\(data.temp)°")
                        .font(.system(size: isCompact ? 34 : 46, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(data.conditionDisplay)
                            .font(.system(size: isCompact ? 10.5 : 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text("↑\(data.high)° ↓\(data.low)°")
                            .font(.system(size: isCompact ? 9 : 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }

                if isTall {
                    VStack(spacing: 5) {
                        ForEach(Array(data.daily.prefix(3).enumerated()), id: \.offset) { _, d in
                            HStack {
                                Text(d.day)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.75))
                                Spacer()
                                Image(systemName: d.symbol)
                                    .foregroundStyle(.white)
                                Text("\(d.low)° / \(d.high)°")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .padding(9)
                    .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(isCompact ? 10 : 15)
        }
    }

    // MARK: - Thème 11 : Dashboard Pro

    private func theme11DashboardPro(w: CGFloat, h: CGFloat) -> some View {
        let isTall = h > w * 1.15
        let isCompact = (h < 165 || w < 190) && !isTall
        return ZStack {
            LinearGradient(
                colors: [Color(red: 0.09, green: 0.12, blue: 0.18), Color(red: 0.05, green: 0.07, blue: 0.11)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: isCompact ? 5 : 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(data.city)
                            .font(.system(size: isCompact ? 11.5 : 14, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text("\(data.conditionDisplay) • \(data.feelsLike)°")
                            .font(.system(size: isCompact ? 8.5 : 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1)
                    }
                    Spacer()
                    Text("\(data.temp)°")
                        .font(.system(size: isCompact ? 22 : 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }

                HStack(spacing: 6) {
                    miniDashboardCell(icon: "drop.fill", label: loc("weather.humidity_upper"), val: "\(data.humidity)%", color: .cyan, compact: isCompact || w < 190)
                    miniDashboardCell(icon: "wind", label: loc("weather.wind_upper"), val: data.windSpeed, color: .mint, compact: isCompact || w < 190)
                }
                HStack(spacing: 6) {
                    miniDashboardCell(icon: "sun.max.fill", label: "UV", val: "\(data.uvIndex) \(loc("weather.uv_mod_short"))", color: .yellow, compact: isCompact || w < 190)
                    miniDashboardCell(icon: "umbrella.fill", label: loc("weather.rain_upper"), val: "\(data.precipProb)%", color: .blue, compact: isCompact || w < 190)
                }

                if isTall {
                    Spacer(minLength: 2)
                    VStack(spacing: 4) {
                        ForEach(Array(data.daily.prefix(3).enumerated()), id: \.offset) { _, d in
                            HStack {
                                Text(d.day)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.70))
                                Spacer()
                                Image(systemName: d.symbol)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.white)
                                Text("\(d.low)° / \(d.high)°")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .padding(8)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(isCompact ? 9 : 13)
        }
    }

    // MARK: - Thème 12 : Compact Essential

    private func theme12CompactEssential(w: CGFloat, h: CGFloat) -> some View {
        let isTall = h > w * 1.15
        let isCompact = (h < 165 || w < 190) && !isTall
        return ZStack {
            LinearGradient(
                colors: [Color(red: 0.12, green: 0.14, blue: 0.20), Color(red: 0.06, green: 0.07, blue: 0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: isCompact ? 4 : 8) {
                HStack {
                    Text(data.city)
                        .font(.system(size: isCompact ? 11.5 : 13.5, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: data.filledSymbol)
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: isCompact ? 14 : 18))
                }

                Spacer(minLength: 0)

                Text("\(data.temp)°")
                    .font(.system(size: isCompact ? 40 : 54, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)

                if isTall {
                    VStack(spacing: 4) {
                        ForEach(Array(data.hourly.prefix(3).enumerated()), id: \.offset) { _, hItem in
                            HStack {
                                Text(hItem.time).foregroundStyle(.white.opacity(0.68))
                                Spacer()
                                Image(systemName: hItem.symbol).foregroundStyle(.white)
                                Text("\(hItem.temp)°").foregroundStyle(.white).fontWeight(.bold)
                            }
                            .font(.system(size: 10))
                        }
                    }
                    .padding(8)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                Spacer(minLength: 0)

                HStack(spacing: 4) {
                    Text(data.conditionDisplay)
                        .font(.system(size: isCompact ? 9 : 11, weight: .semibold))
                        .foregroundStyle(.black)
                        .lineLimit(1)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Color.white, in: Capsule())
                    Spacer(minLength: 2)
                    Text(loc("weather.hi_lo", data.high, data.low))
                        .font(.system(size: isCompact ? 8.5 : 10.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }
            }
            .padding(isCompact ? 10 : 14)
        }
    }

    // MARK: - Thème 13 : Analog Weather Instrument

    private func theme13AnalogInstrument(w: CGFloat, h: CGFloat) -> some View {
        let isTall = h > w * 1.15
        let dialSize = isTall ? min(w * 0.80, h * 0.48) : min(w, h) * 0.78
        return ZStack {
            Color(red: 0.08, green: 0.09, blue: 0.11)

            VStack(spacing: isTall ? 12 : 0) {
                if isTall { Spacer(minLength: 4) }

                ZStack {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 2)
                        .frame(width: dialSize, height: dialSize)

                    ForEach(0..<24, id: \.self) { i in
                        Rectangle()
                            .fill(i % 4 == 0 ? Color.orange : Color.white.opacity(0.32))
                            .frame(width: 1.5, height: i % 4 == 0 ? 7 : 4)
                            .offset(y: -dialSize / 2 + 5)
                            .rotationEffect(.degrees(Double(i) * 15))
                    }

                    Circle()
                        .trim(from: 0.15, to: 0.72)
                        .stroke(
                            AngularGradient(colors: [.cyan, .green, .yellow, .orange, .red], center: .center),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .frame(width: dialSize * 0.80, height: dialSize * 0.80)
                        .rotationEffect(.degrees(90))

                    VStack(spacing: 1) {
                        Text(data.city.uppercased())
                            .font(.system(size: max(7, dialSize * 0.075), weight: .bold))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                        Text("\(data.temp)°")
                            .font(.system(size: dialSize * 0.28, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("\(data.humidity)% RH")
                            .font(.system(size: max(7.5, dialSize * 0.085), weight: .semibold, design: .monospaced))
                            .foregroundStyle(.orange)
                    }
                }

                if isTall {
                    VStack(spacing: 5) {
                        HStack {
                            Text(data.conditionDisplay)
                                .foregroundStyle(.white)
                            Spacer()
                            Text("↑\(data.high)° ↓\(data.low)°")
                                .foregroundStyle(.orange)
                        }
                        .font(.system(size: 10.5, weight: .semibold))
                        HStack {
                            Text("\(loc("weather.wind_prefix")) \(data.windSpeed)")
                            Spacer()
                            Text("\(loc("weather.rain_label")) \(data.precipProb)%")
                        }
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.68))
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(.horizontal, 10)
                    Spacer(minLength: 4)
                }
            }
        }
    }

    // MARK: - Thème 14 : Nature Landscape

    private func theme14NatureLandscape(w: CGFloat, h: CGFloat) -> some View {
        let isTall = h > w * 1.15
        let isCompact = (h < 165 || w < 190) && !isTall
        return ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.16, green: 0.34, blue: 0.44),
                    Color(red: 0.42, green: 0.62, blue: 0.64),
                    Color(red: 0.88, green: 0.68, blue: 0.48)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            Circle()
                .fill(Color(red: 1.0, green: 0.90, blue: 0.65).opacity(0.85))
                .frame(width: min(w, h) * 0.28, height: min(w, h) * 0.28)
                .offset(x: w * 0.18, y: -h * (isTall ? 0.04 : 0.10))

            VStack {
                Spacer()
                MountainRangeShape()
                    .fill(Color(red: 0.12, green: 0.24, blue: 0.30))
                    .frame(height: h * (isTall ? 0.36 : 0.42))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(data.city)
                        .font(.system(size: isCompact ? 11.5 : 14, weight: .bold))
                        .lineLimit(1)
                    Spacer()
                    Text(data.conditionDisplay)
                        .font(.system(size: isCompact ? 9.5 : 12, weight: .medium))
                        .opacity(0.85)
                        .lineLimit(1)
                }
                Text("\(data.temp)°")
                    .font(.system(size: isCompact ? 32 : 44, weight: .bold, design: .rounded))
                Spacer()
                if isTall {
                    VStack(spacing: 4) {
                        ForEach(Array(data.hourly.prefix(3).enumerated()), id: \.offset) { _, hItem in
                            HStack {
                                Text(hItem.time).opacity(0.82)
                                Spacer()
                                Image(systemName: hItem.symbol)
                                Text("\(hItem.temp)°").fontWeight(.bold)
                            }
                            .font(.system(size: 10))
                        }
                    }
                    .padding(8)
                    .background(Color.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                Text("↑\(data.high)° ↓\(data.low)° • \(loc("weather.wind_prefix")) \(data.windSpeed)")
                    .font(.system(size: isCompact ? 8.5 : 10.5, weight: .medium))
                    .opacity(0.85)
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(isCompact ? 10 : 15)
        }
    }

    // MARK: - Thème 15 : Aurora Borealis

    private func theme15AuroraBorealis(w: CGFloat, h: CGFloat) -> some View {
        let isTall = h > w * 1.15
        let isCompact = (h < 165 || w < 190) && !isTall
        return ZStack {
            Color(red: 0.02, green: 0.05, blue: 0.10)

            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.92, blue: 0.62).opacity(0.48),
                    Color(red: 0.14, green: 0.62, blue: 0.96).opacity(0.36),
                    Color(red: 0.62, green: 0.24, blue: 0.96).opacity(0.32),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blur(radius: 10)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(data.city)
                        .font(.system(size: isCompact ? 12 : 15, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "sparkles")
                        .foregroundStyle(Color(red: 0.25, green: 0.96, blue: 0.72))
                }
                Text(data.conditionDisplay)
                    .font(.system(size: isCompact ? 10 : 12, weight: .medium))
                    .foregroundStyle(Color(red: 0.45, green: 0.96, blue: 0.80))
                    .lineLimit(1)

                Spacer()

                Text("\(data.temp)°")
                    .font(.system(size: isCompact ? 36 : 48, weight: .light, design: .rounded))
                    .foregroundStyle(.white)

                if isTall {
                    VStack(spacing: 4) {
                        ForEach(Array(data.daily.prefix(3).enumerated()), id: \.offset) { _, d in
                            HStack {
                                Text(d.day).foregroundStyle(.white.opacity(0.75))
                                Spacer()
                                Image(systemName: d.symbol).foregroundStyle(Color(red: 0.45, green: 0.96, blue: 0.80))
                                Text("\(d.low)° / \(d.high)°").foregroundStyle(.white).fontWeight(.semibold)
                            }
                            .font(.system(size: 10))
                        }
                    }
                    .padding(8)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                Text("\(loc("weather.hi_lo", data.high, data.low)) • \(data.humidity)%")
                    .font(.system(size: isCompact ? 9 : 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.70))
                    .lineLimit(1)
            }
            .padding(isCompact ? 10 : 15)
        }
    }

    // MARK: - Thème 16 : Monochrome Swiss

    private func theme16MonochromeSwiss(w: CGFloat, h: CGFloat) -> some View {
        let isTall = h > w * 1.15
        let isCompact = (h < 165 || w < 190) && !isTall
        return ZStack {
            Color.black

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(data.city.uppercased())
                        .font(.system(size: isCompact ? 9.5 : 12, weight: .heavy))
                        .tracking(1.5)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: data.outlineSymbol)
                        .font(.system(size: isCompact ? 14 : 18, weight: .bold))
                }
                .padding(.bottom, 6)

                Rectangle().fill(Color.white).frame(height: 1.5)

                Spacer()

                Text("\(data.temp)°")
                    .font(.system(size: isCompact ? 40 : 54, weight: .black))
                    .tracking(-1.5)

                if isTall {
                    VStack(spacing: 4) {
                        ForEach(Array(data.hourly.prefix(3).enumerated()), id: \.offset) { _, hItem in
                            HStack {
                                Text(hItem.time)
                                Spacer()
                                Text("\(hItem.temp)°")
                            }
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .opacity(0.82)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Spacer()

                Rectangle().fill(Color.white.opacity(0.35)).frame(height: 1)
                    .padding(.bottom, 5)

                HStack {
                    Text(data.conditionDisplay.uppercased())
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text("\(data.low)°/\(data.high)°")
                        .lineLimit(1)
                }
                .font(.system(size: isCompact ? 8.5 : 10.5, weight: .bold, design: .monospaced))
            }
            .foregroundStyle(.white)
            .padding(isCompact ? 10 : 15)
        }
    }

    // MARK: - Thème 17 : Retro Weather Station

    private func theme17RetroStation(w: CGFloat, h: CGFloat) -> some View {
        let isTall = h > w * 1.15
        let isCompact = (h < 165 || w < 190) && !isTall
        let lcdAmber = Color(red: 1.0, green: 0.72, blue: 0.18)

        return ZStack {
            Color(red: 0.14, green: 0.13, blue: 0.12)

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.08, green: 0.09, blue: 0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(lcdAmber.opacity(0.35), lineWidth: 1.5)
                )
                .padding(8)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("WX-80 // \(data.city.uppercased())")
                        .font(.system(size: isCompact ? 8 : 10, weight: .bold, design: .monospaced))
                        .lineLimit(1)
                    Spacer()
                    Circle().fill(lcdAmber).frame(width: 6, height: 6)
                }

                Spacer()

                HStack(alignment: .lastTextBaseline) {
                    Text("\(data.temp)°\(data.unit)")
                        .font(.system(size: isCompact ? 30 : 42, weight: .bold, design: .monospaced))
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: data.outlineSymbol)
                        .font(.system(size: isCompact ? 18 : 24, weight: .bold))
                }

                if isTall {
                    VStack(alignment: .leading, spacing: 4) {
                        Rectangle().fill(lcdAmber.opacity(0.28)).frame(height: 1)
                        ForEach(Array(data.hourly.prefix(3).enumerated()), id: \.offset) { _, hItem in
                            HStack {
                                Text(hItem.time)
                                Spacer()
                                Text("\(hItem.temp)°\(data.unit)")
                            }
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        }
                        Rectangle().fill(lcdAmber.opacity(0.28)).frame(height: 1)
                    }
                    .padding(.vertical, 4)
                }

                Spacer()

                HStack {
                    Text("RH:\(data.humidity)%")
                    Spacer()
                    Text(loc("weather.hi_lo", data.high, data.low))
                }
                .font(.system(size: isCompact ? 8 : 10, weight: .bold, design: .monospaced))
                .opacity(0.80)
            }
            .foregroundStyle(lcdAmber)
            .padding(isCompact ? 14 : 18)
        }
    }

    // MARK: - Thème 18 : Dynamic Island Style

    private func theme18DynamicIsland(w: CGFloat, h: CGFloat) -> some View {
        let isTall = h > w * 1.15
        let isCompact = (h < 165 || w < 190) && !isTall
        return ZStack {
            Color.black

            VStack(spacing: isCompact ? 6 : 10) {
                HStack(spacing: 6) {
                    Image(systemName: data.filledSymbol)
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: isCompact ? 11.5 : 14))
                    Text(data.city)
                        .font(.system(size: isCompact ? 10 : 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    Text("\(data.temp)°")
                        .font(.system(size: isCompact ? 11 : 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(red: 0.35, green: 0.86, blue: 1.0))
                }
                .padding(.horizontal, isCompact ? 9 : 12)
                .padding(.vertical, 6)
                .background(Color(white: 0.13), in: Capsule())

                Spacer(minLength: 0)

                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(data.conditionDisplay)
                            .font(.system(size: isCompact ? 15 : 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text("\(loc("widget.weather.feels").capitalized) \(data.feelsLike)° • \(loc("weather.rain_label")) \(data.precipProb)%")
                            .font(.system(size: isCompact ? 8.5 : 10.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.58))
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .padding(.horizontal, 4)

                if isTall {
                    VStack(spacing: 5) {
                        ForEach(Array(data.daily.prefix(3).enumerated()), id: \.offset) { _, d in
                            HStack {
                                Text(d.day)
                                    .foregroundStyle(.white.opacity(0.75))
                                Spacer()
                                Image(systemName: d.symbol)
                                    .symbolRenderingMode(.multicolor)
                                Text("\(d.low)° / \(d.high)°")
                                    .foregroundStyle(.white)
                                    .fontWeight(.bold)
                            }
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                        }
                    }
                    .padding(8)
                    .background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                HStack(spacing: 6) {
                    Text("\(data.low)°")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.cyan)
                    Capsule()
                        .fill(LinearGradient(colors: [.cyan, .green, .yellow, .orange], startPoint: .leading, endPoint: .trailing))
                        .frame(height: 5)
                    Text("\(data.high)°")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.orange)
                }
                .padding(.horizontal, 4)
            }
            .padding(isCompact ? 9 : 14)
        }
    }

    // MARK: - Sous-composants Météo Réutilisables

    private func dailyTemperatureBarRow(
        day: String,
        symbol: String,
        low: Int,
        high: Int,
        barStart: CGFloat,
        barEnd: CGFloat,
        isCompact: Bool
    ) -> some View {
        HStack(spacing: isCompact ? 3.5 : 8) {
            Text(day)
                .font(.system(size: isCompact ? 9 : 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.88))
                .frame(width: isCompact ? 23 : 32, alignment: .leading)
                .lineLimit(1)

            Image(systemName: symbol)
                .font(.system(size: isCompact ? 9 : 11))
                .foregroundStyle(.white.opacity(0.80))
                .frame(width: isCompact ? 12 : 14)

            Text("\(low)°")
                .font(.system(size: isCompact ? 9 : 10.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .monospacedDigit()
                .frame(width: isCompact ? 19 : 22, alignment: .trailing)

            GeometryReader { barGeo in
                let bw = barGeo.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.14))
                        .frame(height: 3.5)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.98, green: 0.82, blue: 0.20),
                                    Color(red: 1.00, green: 0.42, blue: 0.12)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(8, bw * (barEnd - barStart)), height: 3.5)
                        .offset(x: bw * barStart)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 8)

            Text("\(high)°")
                .font(.system(size: isCompact ? 9 : 10.5, weight: .semibold))
                .foregroundStyle(.white)
                .monospacedDigit()
                .frame(width: isCompact ? 19 : 22, alignment: .trailing)
        }
    }

    private func darkMetricPill(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(color)
            Text(text)
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3.5)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.08), in: Capsule())
    }

    private func glassMetricPill(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 3.5) {
            Image(systemName: icon)
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(color)
            Text(text)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.14), in: Capsule())
    }

    private func miniDashboardCell(icon: String, label: String, val: String, color: Color, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: compact ? 8 : 9, weight: .bold))
                    .foregroundStyle(color)
                Text(label)
                    .font(.system(size: compact ? 7.5 : 8.5, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Text(val)
                .font(.system(size: compact ? 10.5 : 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(compact ? 6 : 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func weatherAmbientParticles(width w: CGFloat, height h: CGFloat) -> some View {
        if data.condition.lowercased() == "rainy" {
            // Fines gouttes de pluie obliques discrètes
            Canvas { context, size in
                for i in 0..<8 {
                    let x = size.width * CGFloat((Double(i) * 0.13 + 0.08).truncatingRemainder(dividingBy: 1.0))
                    let y = size.height * CGFloat((Double(i) * 0.17 + 0.12).truncatingRemainder(dividingBy: 0.85))
                    var drop = Path()
                    drop.move(to: CGPoint(x: x, y: y))
                    drop.addLine(to: CGPoint(x: x - 3, y: y + 9))
                    context.stroke(drop, with: .color(Color.white.opacity(0.14)), lineWidth: 1)
                }
            }
            .drawingGroup()
        }
    }
}

private struct GlowingSunCloudBadge: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.65, height: size * 0.65)
                .offset(x: size * 0.14, y: -size * 0.12)
                .shadow(color: .orange.opacity(0.5), radius: 5)
            Image(systemName: "cloud.fill")
                .resizable()
                .scaledToFit()
                .frame(width: size * 0.82, height: size * 0.56)
                .foregroundStyle(
                    LinearGradient(colors: [.white, Color(white: 0.84)], startPoint: .top, endPoint: .bottom)
                )
                .offset(x: -size * 0.05, y: size * 0.08)
                .shadow(color: .black.opacity(0.2), radius: 3, y: 1.5)
        }
        .frame(width: size, height: size)
    }
}

private struct HorizonDomeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: -w * 0.1, y: h * 0.72))
        path.addQuadCurve(
            to: CGPoint(x: w * 1.1, y: h * 0.78),
            control: CGPoint(x: w * 0.45, y: h * 0.40)
        )
        path.addLine(to: CGPoint(x: w * 1.1, y: h))
        path.addLine(to: CGPoint(x: -w * 0.1, y: h))
        path.closeSubpath()
        return path
    }
}

private struct MountainRangeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: 0, y: h))
        path.addLine(to: CGPoint(x: 0, y: h * 0.55))
        path.addLine(to: CGPoint(x: w * 0.28, y: h * 0.15))
        path.addLine(to: CGPoint(x: w * 0.52, y: h * 0.50))
        path.addLine(to: CGPoint(x: w * 0.76, y: h * 0.08))
        path.addLine(to: CGPoint(x: w, y: h * 0.45))
        path.addLine(to: CGPoint(x: w, y: h))
        path.closeSubpath()
        return path
    }
}
