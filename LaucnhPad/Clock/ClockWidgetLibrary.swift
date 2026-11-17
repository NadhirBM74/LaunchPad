import SwiftUI
import Combine
import AppKit

// MARK: - 15 Styles d'Horloges (Fidèles à la Photo de Référence 7 & Section 8)

public enum ClockWidgetStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case appleAnalog = "appleAnalog"           // 1. Photo de Référence 7 : Grands chiffres 12/3/6/9 floutés + aiguilles + pilule "Sat, Sep 12"
    case appleDigital = "appleDigital"         // 2. Horloge numérique minimaliste Apple
    case flipClock = "flipClock"               // 3. Horloge mécanique à volets (Flip Clock)
    case retroDigital = "retroDigital"         // 4. Horloge numérique vintage LCD / 7-segments
    case liquidGlass = "liquidGlass"           // 5. Horloge Liquid Glass avec transparence et profondeur
    case minimalWhite = "minimalWhite"         // 6. Chiffres sculptés sur fond clair minimaliste
    case darkPremium = "darkPremium"           // 7. Chronographe sombre sophistiqué
    case neonClock = "neonClock"               // 8. Chiffres lumineux néon
    case typographyClock = "typographyClock"   // 9. Typographie éditoriale superposée
    case circularClock = "circularClock"       // 10. Cadran circulaire concentrique moderne
    case gradientClock = "gradientClock"       // 11. Horloge aux couleurs dégradées vibrantes
    case worldClock = "worldClock"             // 12. Horloge mondiale multi-fuseaux horaires
    case weatherClock = "weatherClock"         // 13. Horloge associée à la météo en direct
    case calendarClock = "calendarClock"       // 14. Horloge associée à la date et au calendrier
    case fullscreenClock = "fullscreenClock"   // 15. Horloge plein écran façon StandBy

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .appleAnalog: return "1. Apple Analog Blurred (Photo Réf. 7)"
        case .appleDigital: return "2. Apple Digital Minimal"
        case .flipClock: return "3. Flip Clock (À volets)"
        case .retroDigital: return "4. Retro Digital Vintage"
        case .liquidGlass: return "5. Liquid Glass"
        case .minimalWhite: return "6. Minimal White"
        case .darkPremium: return "7. Dark Premium Chrono"
        case .neonClock: return "8. Neon Clock"
        case .typographyClock: return "9. Typography Editorial"
        case .circularClock: return "10. Circular Concentric"
        case .gradientClock: return "11. Gradient Clock"
        case .worldClock: return "12. World Clock (Fuseaux)"
        case .weatherClock: return "13. Weather Clock"
        case .calendarClock: return "14. Calendar Clock"
        case .fullscreenClock: return "15. Fullscreen StandBy"
        }
    }

    public var subtitle: String {
        switch self {
        case .appleAnalog: return "Grands chiffres 12, 3, 6, 9 floutés, aiguilles ajourées et pilule de date"
        case .appleDigital: return "Horloge numérique épurée avec salutation et date"
        case .flipClock: return "Volets mécaniques rétro avec charnière centrale"
        case .retroDigital: return "Afficheur numérique vintage à segments lumineux"
        case .liquidGlass: return "Transparence cristalline et biseau spéculaire Apple"
        case .minimalWhite: return "Esthétique claire immaculée et typographie fine"
        case .darkPremium: return "Cadran chronographe carbone et sous-cadran des secondes"
        case .neonClock: return "Tubes lumineux néon avec halo atmosphérique"
        case .typographyClock: return "Composition typographique empilée grand format"
        case .circularClock: return "Anneaux de progression concentriques heures/minutes/secondes"
        case .gradientClock: return "Dégradés chromatiques intenses et chiffres contrastés"
        case .worldClock: return "4 fuseaux horaires en direct avec indicateur jour/nuit"
        case .weatherClock: return "Heure précise combinée à la météo actuelle"
        case .calendarClock: return "Heure précise combinée au calendrier du mois"
        case .fullscreenClock: return "Chiffres géants plein cadre façon mode En veille"
        }
    }
}

// MARK: - Vue Principale de la Bibliothèque d'Horloges (15 Styles × Tous Formats)

struct PremiumClockWidgetView: View {
    let config: CustomWidgetConfig
    var targetSize: CGSize? = nil

    @ObservedObject private var widgetManager = WidgetManager.shared
    @State private var currentDate = Date()
    @State private var timer: AnyCancellable?

    private var accentColor: Color {
        switch config.clockAccentColor.lowercased() {
        case "red": return Color(red: 1.00, green: 0.16, blue: 0.12)
        case "orange": return Color(red: 1.00, green: 0.58, blue: 0.05)
        case "cyan": return Color(red: 0.15, green: 0.85, blue: 1.00)
        case "purple": return Color(red: 0.72, green: 0.42, blue: 1.00)
        case "green": return Color(red: 0.20, green: 0.88, blue: 0.45)
        case "gold": return Color(red: 1.00, green: 0.80, blue: 0.22)
        case "white": return Color.white
        default: return Color(red: 1.00, green: 0.16, blue: 0.12)
        }
    }

    private var fontDesign: Font.Design {
        switch config.clockFontDesign.lowercased() {
        case "serif": return .serif
        case "monospaced": return .monospaced
        case "default": return .default
        default: return .rounded
        }
    }

    var body: some View {
        let w = targetSize?.width ?? config.size.width
        let h = targetSize?.height ?? config.size.height
        let cornerRadius = widgetManager.cornerRadius

        GeometryReader { geo in
            let availW = geo.size.width
            let availH = geo.size.height

            ZStack {
                clockStyleContent(w: availW, h: availH)
            }
            .frame(width: availW, height: availH)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(config.clockStyle == .minimalWhite ? 0.85 : 0.30),
                                Color.white.opacity(0.08),
                                Color.white.opacity(0.18)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.0
                    )
            )
            .shadow(color: .black.opacity(0.34), radius: 14, x: 0, y: 7)
        }
        .frame(width: w, height: h)
        .onAppear {
            currentDate = Date()
            startTimer()
        }
        .onDisappear {
            stopTimer()
        }
        .onReceive(NotificationCenter.default.publisher(for: .launchpadVisibilityDidChange)) { notif in
            let visible = (notif.object as? Bool) ?? false
            if visible {
                currentDate = Date()
                startTimer()
            } else {
                stopTimer()
            }
        }
    }

    private func startTimer() {
        timer?.cancel()
        let needsEverySecond = config.clockShowSeconds || config.clockStyle == .appleAnalog || config.clockStyle == .darkPremium || config.clockStyle == .circularClock
        let interval: TimeInterval = needsEverySecond ? 1.0 : 10.0
        timer = Timer.publish(every: interval, tolerance: 0.2, on: .main, in: .common)
            .autoconnect()
            .sink { date in
                self.currentDate = date
            }
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    @ViewBuilder
    private func clockStyleContent(w: CGFloat, h: CGFloat) -> some View {
        switch config.clockStyle {
        case .appleAnalog:
            style1AppleAnalogReference(w: w, h: h)
        case .appleDigital:
            style2AppleDigital(w: w, h: h)
        case .flipClock:
            style3FlipClock(w: w, h: h)
        case .retroDigital:
            style4RetroDigital(w: w, h: h)
        case .liquidGlass:
            style5LiquidGlass(w: w, h: h)
        case .minimalWhite:
            style6MinimalWhite(w: w, h: h)
        case .darkPremium:
            style7DarkPremiumChrono(w: w, h: h)
        case .neonClock:
            style8NeonClock(w: w, h: h)
        case .typographyClock:
            style9TypographyClock(w: w, h: h)
        case .circularClock:
            style10CircularClock(w: w, h: h)
        case .gradientClock:
            style11GradientClock(w: w, h: h)
        case .worldClock:
            style12WorldClock(w: w, h: h)
        case .weatherClock:
            style13WeatherClock(w: w, h: h)
        case .calendarClock:
            style14CalendarClock(w: w, h: h)
        case .fullscreenClock:
            style15FullscreenClock(w: w, h: h)
        }
    }

    // MARK: - 1. Apple Analog Blurred Numerals (Adaptatif Carré, Horizontal, Vertical)

    private func style1AppleAnalogReference(w: CGFloat, h: CGFloat) -> some View {
        let isTall = h > w * 1.15
        let isWide = w > h * 1.35
        let cal = Calendar.current
        let hour = cal.component(.hour, from: currentDate) % 12
        let minute = cal.component(.minute, from: currentDate)
        let second = cal.component(.second, from: currentDate)

        let hourAngle = Double(hour) * 30.0 + Double(minute) * 0.5
        let minuteAngle = Double(minute) * 6.0 + Double(second) * 0.1
        let secondAngle = Double(second) * 6.0

        return ZStack {
            Color(red: 0.02, green: 0.02, blue: 0.03)

            if isTall {
                let dialDim = min(w - 16, h * 0.52)
                VStack(spacing: 10) {
                    Spacer(minLength: 4)
                    analogReferenceDial(size: dialDim, hourAngle: hourAngle, minuteAngle: minuteAngle, secondAngle: secondAngle, showPill: false)
                    Spacer(minLength: 2)
                    VStack(spacing: 4) {
                        Text(shortDigitalTimeString)
                            .font(.system(size: min(w * 0.24, 34), weight: .bold, design: fontDesign))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                        if config.clockShowDate {
                            Text(referencePillDateString.uppercased())
                                .font(.system(size: min(w * 0.085, 11.5), weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color(red: 0.20, green: 0.20, blue: 0.22).opacity(0.92)))
                        }
                    }
                    Spacer(minLength: 6)
                }
                .padding(10)
            } else if isWide {
                let dialDim = min(h - 14, w * 0.48)
                HStack(spacing: 12) {
                    analogReferenceDial(size: dialDim, hourAngle: hourAngle, minuteAngle: minuteAngle, secondAngle: secondAngle, showPill: false)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(digitalTimeString)
                            .font(.system(size: min(h * 0.28, 36), weight: .bold, design: fontDesign))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                            .minimumScaleFactor(0.65)
                            .lineLimit(1)
                        if config.clockShowDate {
                            Text(fullDateString)
                                .font(.system(size: min(h * 0.11, 13), weight: .medium, design: fontDesign))
                                .foregroundStyle(.white.opacity(0.68))
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 14)
            } else {
                analogReferenceDial(size: min(w, h), hourAngle: hourAngle, minuteAngle: minuteAngle, secondAngle: secondAngle, showPill: config.clockShowDate)
            }
        }
    }

    @ViewBuilder
    private func analogReferenceDial(size minDim: CGFloat, hourAngle: Double, minuteAngle: Double, secondAngle: Double, showPill: Bool) -> some View {
        let numeralSize = minDim * 0.44
        ZStack {
            ZStack {
                Text("12")
                    .font(.system(size: numeralSize, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .position(x: minDim / 2, y: minDim * 0.14)
                Text("3")
                    .font(.system(size: numeralSize, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .position(x: minDim - minDim * 0.12, y: minDim / 2)
                Text("6")
                    .font(.system(size: numeralSize, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .position(x: minDim / 2, y: minDim - minDim * 0.12)
                Text("9")
                    .font(.system(size: numeralSize, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .position(x: minDim * 0.12, y: minDim / 2)
            }
            .blur(radius: max(2.0, minDim * 0.022))

            if showPill {
                Text(referencePillDateString)
                    .font(.system(size: max(8.5, minDim * 0.068), weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, minDim * 0.065)
                    .padding(.vertical, minDim * 0.026)
                    .background(Capsule().fill(Color(red: 0.20, green: 0.20, blue: 0.22).opacity(0.92)))
                    .position(x: minDim / 2, y: minDim * 0.63)
            }

            ZStack {
                ZStack {
                    Capsule().fill(Color.white).frame(width: minDim * 0.068, height: minDim * 0.38)
                    Capsule().fill(Color.black).frame(width: minDim * 0.026, height: minDim * 0.20).offset(y: -minDim * 0.05)
                }
                .offset(y: -minDim * 0.15)
                .rotationEffect(.degrees(minuteAngle))
                .shadow(color: .black.opacity(0.55), radius: 3, y: 1.5)

                ZStack {
                    Capsule().fill(Color.white).frame(width: minDim * 0.072, height: minDim * 0.27)
                    Capsule().fill(accentColor).frame(width: minDim * 0.032, height: minDim * 0.12).offset(y: -minDim * 0.04)
                }
                .offset(y: -minDim * 0.09)
                .rotationEffect(.degrees(hourAngle))
                .shadow(color: .black.opacity(0.55), radius: 3, y: 1.5)

                if config.clockShowSeconds {
                    Capsule()
                        .fill(accentColor)
                        .frame(width: max(1.5, minDim * 0.013), height: minDim * 0.48)
                        .offset(y: -minDim * 0.16)
                        .rotationEffect(.degrees(secondAngle))
                    Circle().fill(accentColor).frame(width: minDim * 0.045, height: minDim * 0.045)
                } else {
                    Circle().fill(Color.white).frame(width: minDim * 0.042, height: minDim * 0.042)
                }
            }
            .position(x: minDim / 2, y: minDim / 2)
        }
        .frame(width: minDim, height: minDim)
    }

    // MARK: - 2. Apple Digital Minimal

    private func style2AppleDigital(w: CGFloat, h: CGFloat) -> some View {
        let isTall = h > w * 1.15
        let isCompact = (h < 165 || w < 165) && !isTall
        let cal = Calendar.current
        let rawH = cal.component(.hour, from: currentDate)
        let dispH = config.clockFormat24h ? rawH : ((rawH % 12 == 0) ? 12 : (rawH % 12))
        let dispM = cal.component(.minute, from: currentDate)
        let dispS = cal.component(.second, from: currentDate)

        return ZStack {
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.09, blue: 0.14), Color(red: 0.04, green: 0.04, blue: 0.07)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Circle().fill(accentColor).frame(width: 6, height: 6)
                    Text(greetingTitle)
                        .font(.system(size: isCompact ? 9.5 : 11, weight: .semibold, design: fontDesign))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(Color.white.opacity(0.08), in: Capsule())

                Spacer(minLength: 4)

                if isTall {
                    VStack(alignment: .leading, spacing: -min(w * 0.06, 8)) {
                        Text(String(format: "%02d", dispH))
                            .font(.system(size: min(w * 0.44, 64), weight: .bold, design: fontDesign))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                        Text(String(format: "%02d", dispM))
                            .font(.system(size: min(w * 0.44, 64), weight: .semibold, design: fontDesign))
                            .foregroundStyle(accentColor)
                            .monospacedDigit()
                    }
                    if config.clockShowSeconds {
                        Text(String(format: ":%02d", dispS))
                            .font(.system(size: min(w * 0.13, 18), weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.65))
                            .padding(.top, 4)
                    }
                } else {
                    Text(digitalTimeString)
                        .font(.system(size: isCompact ? 34 : 46, weight: .bold, design: fontDesign))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .minimumScaleFactor(0.55)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if config.clockShowDate {
                    Text(fullDateString)
                        .font(.system(size: isCompact ? 10 : 12, weight: .medium, design: fontDesign))
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .padding(isCompact ? 11 : 16)
        }
    }

    // MARK: - 3. Flip Clock (Chiffres à volets mécaniques)

    private func style3FlipClock(w: CGFloat, h: CGFloat) -> some View {
        let cal = Calendar.current
        let rawH = cal.component(.hour, from: currentDate)
        let dispH = config.clockFormat24h ? rawH : ((rawH % 12 == 0) ? 12 : (rawH % 12))
        let dispM = cal.component(.minute, from: currentDate)
        let dispS = cal.component(.second, from: currentDate)
        let isTall = h > w * 1.15
        let isWide = w > h * 1.35
        let showSec = (isWide || (isTall && h > 340)) && config.clockShowSeconds

        return ZStack {
            Color(red: 0.07, green: 0.07, blue: 0.08)

            VStack(spacing: isTall ? 8 : 8) {
                if isTall {
                    let rowCount: CGFloat = showSec ? 3.0 : 2.0
                    let tileH = min((h - 62 - CGFloat(rowCount - 1) * 8) / rowCount, 108)
                    VStack(spacing: 8) {
                        flipTile(value: String(format: "%02d", dispH), label: "HR", tileH: tileH)
                        flipTile(value: String(format: "%02d", dispM), label: "MIN", tileH: tileH)
                        if showSec {
                            flipTile(value: String(format: "%02d", dispS), label: "SEC", tileH: tileH)
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        flipTile(value: String(format: "%02d", dispH), label: "HR", h: h)
                        flipTile(value: String(format: "%02d", dispM), label: "MIN", h: h)
                        if showSec {
                            flipTile(value: String(format: "%02d", dispS), label: "SEC", h: h)
                        }
                    }
                }

                if config.clockShowDate {
                    Text(referencePillDateString.uppercased())
                        .font(.system(size: isTall ? 10 : 9, weight: .bold, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(accentColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .padding(w < 170 ? 10 : 12)
        }
    }

    private func flipTile(value: String, label: String, h: CGFloat = 150, tileH overrideH: CGFloat? = nil) -> some View {
        let tileH = overrideH ?? min(h * 0.62, 92)
        return ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.18), Color(white: 0.12)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
                )

            Text(value)
                .font(.system(size: tileH * 0.56, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .minimumScaleFactor(0.65)

            Rectangle()
                .fill(Color.black.opacity(0.75))
                .frame(height: 1.8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: tileH)
        .shadow(color: .black.opacity(0.45), radius: 4, y: 2)
    }

    // MARK: - 4. Retro Digital Vintage

    private func style4RetroDigital(w: CGFloat, h: CGFloat) -> some View {
        let isTall = h > w * 1.15
        let isCompact = (h < 165 || w < 165) && !isTall
        let lcdGreen = Color(red: 0.48, green: 0.96, blue: 0.58)
        let cal = Calendar.current
        let rawH = cal.component(.hour, from: currentDate)
        let dispH = config.clockFormat24h ? rawH : ((rawH % 12 == 0) ? 12 : (rawH % 12))
        let dispM = cal.component(.minute, from: currentDate)
        let dispS = cal.component(.second, from: currentDate)

        return ZStack {
            Color(red: 0.12, green: 0.13, blue: 0.15)

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.06, green: 0.12, blue: 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(lcdGreen.opacity(0.35), lineWidth: 1.5)
                )
                .padding(8)

            VStack(spacing: 4) {
                HStack {
                    Text("CASIO // QUARTZ")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    Spacer()
                    Text(config.clockFormat24h ? "24H" : "PM")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(lcdGreen.opacity(0.65))

                Spacer()

                if isTall {
                    VStack(spacing: 2) {
                        Text(String(format: "%02d", dispH))
                            .font(.system(size: min(w * 0.36, 52), weight: .black, design: .monospaced))
                            .foregroundStyle(lcdGreen)
                            .shadow(color: lcdGreen.opacity(0.55), radius: 6)
                        Text(String(format: "%02d", dispM))
                            .font(.system(size: min(w * 0.36, 52), weight: .black, design: .monospaced))
                            .foregroundStyle(lcdGreen.opacity(0.88))
                            .shadow(color: lcdGreen.opacity(0.45), radius: 5)
                        if config.clockShowSeconds {
                            Text(String(format: ":%02d SEC", dispS))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(lcdGreen.opacity(0.75))
                                .padding(.top, 2)
                        }
                    }
                } else {
                    ZStack {
                        Text(config.clockShowSeconds ? "88:88:88" : "88:88")
                            .font(.system(size: isCompact ? 26 : 36, weight: .black, design: .monospaced))
                            .foregroundStyle(lcdGreen.opacity(0.08))
                            .minimumScaleFactor(0.55)
                            .lineLimit(1)
                        Text(digitalTimeString)
                            .font(.system(size: isCompact ? 26 : 36, weight: .black, design: .monospaced))
                            .foregroundStyle(lcdGreen)
                            .shadow(color: lcdGreen.opacity(0.55), radius: 6)
                            .minimumScaleFactor(0.55)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if config.clockShowDate {
                    Text(referencePillDateString.uppercased())
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(lcdGreen.opacity(0.85))
                        .lineLimit(1)
                }
            }
            .padding(16)
        }
    }

    // MARK: - 5. Liquid Glass Clock

    private func style5LiquidGlass(w: CGFloat, h: CGFloat) -> some View {
        let isTall = h > w * 1.15
        let isCompact = (h < 165 || w < 165) && !isTall
        let cal = Calendar.current
        let rawH = cal.component(.hour, from: currentDate)
        let dispH = config.clockFormat24h ? rawH : ((rawH % 12 == 0) ? 12 : (rawH % 12))
        let dispM = cal.component(.minute, from: currentDate)

        return ZStack {
            LinearGradient(
                colors: [
                    Color.white.opacity(0.24),
                    accentColor.opacity(0.22),
                    Color.white.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .background(.ultraThinMaterial)

            Circle()
                .fill(accentColor.opacity(0.35))
                .frame(width: min(w, h) * 0.65, height: min(w, h) * 0.65)
                .blur(radius: 22)

            VStack(spacing: isTall ? 10 : 4) {
                if isTall {
                    VStack(spacing: -6) {
                        Text(String(format: "%02d", dispH))
                        Text(String(format: "%02d", dispM))
                    }
                    .font(.system(size: min(w * 0.42, 62), weight: .heavy, design: fontDesign))
                    .foregroundStyle(LinearGradient(colors: [.white, .white.opacity(0.82)], startPoint: .top, endPoint: .bottom))
                    .monospacedDigit()
                    .shadow(color: .black.opacity(0.22), radius: 6, y: 3)
                } else {
                    Text(digitalTimeString)
                        .font(.system(size: isCompact ? 34 : 46, weight: .heavy, design: fontDesign))
                        .foregroundStyle(LinearGradient(colors: [.white, .white.opacity(0.80)], startPoint: .top, endPoint: .bottom))
                        .monospacedDigit()
                        .minimumScaleFactor(0.55)
                        .lineLimit(1)
                        .shadow(color: .black.opacity(0.22), radius: 6, y: 3)
                }

                if config.clockShowDate {
                    Text(referencePillDateString)
                        .font(.system(size: isCompact ? 10 : 12, weight: .semibold, design: fontDesign))
                        .foregroundStyle(.white.opacity(0.88))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.16), in: Capsule())
                }
            }
            .padding(12)
        }
    }

    // MARK: - 6. Minimal White

    private func style6MinimalWhite(w: CGFloat, h: CGFloat) -> some View {
        let isTall = h > w * 1.15
        let isCompact = (h < 165 || w < 165) && !isTall
        let cal = Calendar.current
        let rawH = cal.component(.hour, from: currentDate)
        let dispH = config.clockFormat24h ? rawH : ((rawH % 12 == 0) ? 12 : (rawH % 12))
        let dispM = cal.component(.minute, from: currentDate)

        return ZStack {
            LinearGradient(
                colors: [Color.white, Color(red: 0.94, green: 0.95, blue: 0.97)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: isTall ? 10 : 4) {
                if config.clockShowDate {
                    Text(referencePillDateString.uppercased())
                        .font(.system(size: isCompact ? 8.5 : 10, weight: .bold, design: fontDesign))
                        .tracking(1.2)
                        .foregroundStyle(accentColor)
                        .lineLimit(1)
                }

                if isTall {
                    VStack(spacing: -8) {
                        Text(String(format: "%02d", dispH))
                            .foregroundStyle(Color(white: 0.08))
                        Text(String(format: "%02d", dispM))
                            .foregroundStyle(accentColor)
                    }
                    .font(.system(size: min(w * 0.44, 64), weight: .bold, design: fontDesign))
                    .monospacedDigit()
                } else {
                    Text(digitalTimeString)
                        .font(.system(size: isCompact ? 36 : 48, weight: .bold, design: fontDesign))
                        .foregroundStyle(Color(white: 0.08))
                        .monospacedDigit()
                        .minimumScaleFactor(0.55)
                        .lineLimit(1)
                }
            }
            .padding(12)
        }
    }

    // MARK: - 7. Dark Premium Chronograph

    private func style7DarkPremiumChrono(w: CGFloat, h: CGFloat) -> some View {
        let isTall = h > w * 1.15
        let dialSize = isTall ? min(w * 0.84, h * 0.50) : min(w, h) * 0.84
        return ZStack {
            RadialGradient(
                colors: [Color(red: 0.13, green: 0.14, blue: 0.17), Color(red: 0.04, green: 0.04, blue: 0.06)],
                center: .center,
                startRadius: 4,
                endRadius: max(w, h) * 0.65
            )

            if isTall {
                VStack(spacing: 12) {
                    Spacer(minLength: 4)
                    AnalogClockFace(date: currentDate, size: dialSize)
                    Spacer(minLength: 2)
                    VStack(spacing: 3) {
                        Text(digitalTimeString)
                            .font(.system(size: min(w * 0.22, 30), weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                        if config.clockShowDate {
                            Text(fullDateString)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.62))
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                }
                .padding(10)
            } else {
                AnalogClockFace(date: currentDate, size: dialSize)
            }
        }
    }

    // MARK: - 8. Neon Clock

    private func style8NeonClock(w: CGFloat, h: CGFloat) -> some View {
        let isTall = h > w * 1.15
        let isCompact = (h < 165 || w < 165) && !isTall
        let cal = Calendar.current
        let rawH = cal.component(.hour, from: currentDate)
        let dispH = config.clockFormat24h ? rawH : ((rawH % 12 == 0) ? 12 : (rawH % 12))
        let dispM = cal.component(.minute, from: currentDate)

        return ZStack {
            Color(red: 0.03, green: 0.02, blue: 0.07)

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(accentColor.opacity(0.65), lineWidth: 1.5)
                .shadow(color: accentColor, radius: 8)
                .padding(8)

            VStack(spacing: isTall ? 10 : 4) {
                if isTall {
                    VStack(spacing: -6) {
                        Text(String(format: "%02d", dispH))
                        Text(String(format: "%02d", dispM))
                    }
                    .font(.system(size: min(w * 0.42, 60), weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: accentColor, radius: 10)
                    .shadow(color: accentColor.opacity(0.8), radius: 20)
                    .monospacedDigit()
                } else {
                    Text(digitalTimeString)
                        .font(.system(size: isCompact ? 32 : 44, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: accentColor, radius: 10)
                        .shadow(color: accentColor.opacity(0.8), radius: 20)
                        .monospacedDigit()
                        .minimumScaleFactor(0.55)
                        .lineLimit(1)
                }

                if config.clockShowDate {
                    Text(referencePillDateString.uppercased())
                        .font(.system(size: isCompact ? 8.5 : 10, weight: .bold, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(accentColor)
                        .shadow(color: accentColor.opacity(0.8), radius: 6)
                        .lineLimit(1)
                }
            }
            .padding(14)
        }
    }

    // MARK: - 9. Typography Editorial Clock

    private func style9TypographyClock(w: CGFloat, h: CGFloat) -> some View {
        let cal = Calendar.current
        let rawH = cal.component(.hour, from: currentDate)
        let dispH = config.clockFormat24h ? rawH : ((rawH % 12 == 0) ? 12 : (rawH % 12))
        let dispM = cal.component(.minute, from: currentDate)
        let isTall = h > w * 1.15
        let isCompactSide = w < 185 && !isTall
        let numSize = isTall ? min(w * 0.42, h * 0.24) : min(w, h) * (isCompactSide ? 0.36 : 0.42)

        return ZStack {
            Color(red: 0.05, green: 0.06, blue: 0.09)

            if isTall {
                VStack(spacing: 12) {
                    Spacer(minLength: 4)
                    VStack(spacing: -numSize * 0.16) {
                        Text(String(format: "%02d", dispH))
                            .font(.system(size: numSize, weight: .black, design: fontDesign))
                            .foregroundStyle(.white)
                        Text(String(format: "%02d", dispM))
                            .font(.system(size: numSize, weight: .thin, design: fontDesign))
                            .foregroundStyle(accentColor)
                    }
                    if config.clockShowDate {
                        HStack(spacing: 6) {
                            Text(shortWeekday(for: currentDate).uppercased())
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundStyle(accentColor)
                            Text("\(Calendar.current.component(.day, from: currentDate))")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.white)
                            Text(shortMonth(for: currentDate).uppercased())
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.65))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.08), in: Capsule())
                    }
                    Spacer(minLength: 4)
                }
                .padding(12)
            } else {
                HStack(spacing: isCompactSide ? 8 : 12) {
                    VStack(alignment: .leading, spacing: -numSize * 0.16) {
                        Text(String(format: "%02d", dispH))
                            .font(.system(size: numSize, weight: .black, design: fontDesign))
                            .foregroundStyle(.white)
                        Text(String(format: "%02d", dispM))
                            .font(.system(size: numSize, weight: .thin, design: fontDesign))
                            .foregroundStyle(accentColor)
                    }

                    if config.clockShowDate {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(shortWeekday(for: currentDate).uppercased())
                                .font(.system(size: isCompactSide ? 9 : 11, weight: .heavy))
                                .foregroundStyle(accentColor)
                            Text("\(Calendar.current.component(.day, from: currentDate))")
                                .font(.system(size: isCompactSide ? 18 : 22, weight: .bold))
                                .foregroundStyle(.white)
                            Text(shortMonth(for: currentDate).uppercased())
                                .font(.system(size: isCompactSide ? 8.5 : 10, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    }
                }
                .padding(10)
            }
        }
    }

    // MARK: - 10. Circular Concentric Clock

    private func style10CircularClock(w: CGFloat, h: CGFloat) -> some View {
        let cal = Calendar.current
        let hour = Double(cal.component(.hour, from: currentDate) % 12) / 12.0
        let minute = Double(cal.component(.minute, from: currentDate)) / 60.0
        let second = Double(cal.component(.second, from: currentDate)) / 60.0
        let ringBox = min(w, h) * 0.80

        return ZStack {
            Color(red: 0.05, green: 0.06, blue: 0.10)

            ZStack {
                // Anneau Heures
                Circle().stroke(Color.white.opacity(0.10), lineWidth: 6)
                    .frame(width: ringBox, height: ringBox)
                Circle().trim(from: 0, to: max(0.03, hour))
                    .stroke(accentColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: ringBox, height: ringBox)
                    .rotationEffect(.degrees(-90))

                // Anneau Minutes
                Circle().stroke(Color.white.opacity(0.10), lineWidth: 5)
                    .frame(width: ringBox * 0.78, height: ringBox * 0.78)
                Circle().trim(from: 0, to: max(0.03, minute))
                    .stroke(Color.cyan, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: ringBox * 0.78, height: ringBox * 0.78)
                    .rotationEffect(.degrees(-90))

                // Anneau Secondes
                if config.clockShowSeconds {
                    Circle().stroke(Color.white.opacity(0.10), lineWidth: 3.5)
                        .frame(width: ringBox * 0.58, height: ringBox * 0.58)
                    Circle().trim(from: 0, to: max(0.03, second))
                        .stroke(Color.yellow, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                        .frame(width: ringBox * 0.58, height: ringBox * 0.58)
                        .rotationEffect(.degrees(-90))
                }

                Text(shortDigitalTimeString)
                    .font(.system(size: ringBox * 0.18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
        }
    }

    // MARK: - 11. Gradient Clock

    private func style11GradientClock(w: CGFloat, h: CGFloat) -> some View {
        let isTall = h > w * 1.15
        let isCompact = (h < 165 || w < 165) && !isTall
        let cal = Calendar.current
        let rawH = cal.component(.hour, from: currentDate)
        let dispH = config.clockFormat24h ? rawH : ((rawH % 12 == 0) ? 12 : (rawH % 12))
        let dispM = cal.component(.minute, from: currentDate)

        return ZStack {
            LinearGradient(
                colors: [
                    accentColor,
                    Color(red: 0.38, green: 0.18, blue: 0.92),
                    Color(red: 0.08, green: 0.56, blue: 0.98)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: isTall ? 10 : 4) {
                if isTall {
                    VStack(spacing: -6) {
                        Text(String(format: "%02d", dispH))
                        Text(String(format: "%02d", dispM))
                    }
                    .font(.system(size: min(w * 0.42, 62), weight: .black, design: fontDesign))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                } else {
                    Text(digitalTimeString)
                        .font(.system(size: isCompact ? 34 : 46, weight: .black, design: fontDesign))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .minimumScaleFactor(0.55)
                        .lineLimit(1)
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                }

                if config.clockShowDate {
                    Text(referencePillDateString)
                        .font(.system(size: isCompact ? 10 : 12, weight: .bold, design: fontDesign))
                        .foregroundStyle(.white.opacity(0.90))
                        .lineLimit(1)
                }
            }
            .padding(12)
        }
    }

    // MARK: - 12. World Clock (Horloge Mondiale Multi-Fuseaux)

    private func style12WorldClock(w: CGFloat, h: CGFloat) -> some View {
        let isTall = h > w * 1.15
        let isCompact = (h < 165 || w < 165) && !isTall
        let zones = config.clockTimezones.isEmpty
            ? ["Europe/Paris", "America/New_York", "Asia/Tokyo", "Europe/London", "America/Los_Angeles", "Australia/Sydney"]
            : config.clockTimezones
        let maxCount = isTall ? (h > 350 ? 6 : 5) : (isCompact ? 3 : 4)

        return ZStack {
            Color(red: 0.06, green: 0.07, blue: 0.11)

            VStack(spacing: isTall ? 8 : (isCompact ? 4 : 6)) {
                if isTall {
                    HStack {
                        Text(shortDigitalTimeString)
                            .font(.system(size: min(w * 0.18, 24), weight: .bold, design: fontDesign))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                        Spacer()
                        Text("FUSEAUX")
                            .font(.system(size: 8.5, weight: .heavy))
                            .tracking(0.8)
                            .foregroundStyle(accentColor)
                    }
                    .padding(.horizontal, 4)
                }

                ForEach(Array(zones.prefix(maxCount).enumerated()), id: \.offset) { _, tzID in
                    let info = worldClockInfo(for: tzID)
                    HStack {
                        HStack(spacing: 5) {
                            Image(systemName: info.isDaylight ? "sun.max.fill" : "moon.fill")
                                .font(.system(size: isCompact ? 8.5 : 10))
                                .foregroundStyle(info.isDaylight ? Color.yellow : Color.indigo)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(info.city)
                                    .font(.system(size: isCompact ? 9.5 : 11, weight: .bold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Text(info.offsetLabel)
                                    .font(.system(size: 7.5, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.50))
                            }
                        }
                        Spacer(minLength: 4)
                        Text(info.timeString)
                            .font(.system(size: isCompact ? 11 : 13.5, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, isCompact ? 3.5 : 5)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                if isTall { Spacer(minLength: 0) }
            }
            .padding(isCompact ? 8 : 12)
        }
    }

    // MARK: - 13. Weather Clock (Horloge associée à la météo)

    private func style13WeatherClock(w: CGFloat, h: CGFloat) -> some View {
        let isTall = h > w * 1.15
        let isCompact = (h < 165 || w < 165) && !isTall
        let weather = RichWeatherData.from(config: config)
        let cal = Calendar.current
        let rawH = cal.component(.hour, from: currentDate)
        let dispH = config.clockFormat24h ? rawH : ((rawH % 12 == 0) ? 12 : (rawH % 12))
        let dispM = cal.component(.minute, from: currentDate)

        return ZStack {
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.12, blue: 0.22), Color(red: 0.04, green: 0.06, blue: 0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: isTall ? 8 : 4) {
                HStack {
                    Label(weather.city, systemImage: "location.fill")
                        .font(.system(size: isCompact ? 9 : 11, weight: .bold))
                        .foregroundStyle(.cyan)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    HStack(spacing: 4) {
                        Image(systemName: weather.filledSymbol)
                            .symbolRenderingMode(.multicolor)
                        Text("\(weather.temp)°")
                            .font(.system(size: isCompact ? 11.5 : 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }

                Spacer()

                if isTall {
                    VStack(alignment: .leading, spacing: -6) {
                        Text(String(format: "%02d", dispH))
                            .foregroundStyle(.white)
                        Text(String(format: "%02d", dispM))
                            .foregroundStyle(.cyan)
                    }
                    .font(.system(size: min(w * 0.40, 56), weight: .bold, design: fontDesign))
                    .monospacedDigit()

                    HStack(spacing: 8) {
                        Text("↑\(weather.high)° ↓\(weather.low)°")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.75))
                        Spacer()
                        Text("\(weather.humidity)%")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.cyan)
                    }
                } else {
                    Text(digitalTimeString)
                        .font(.system(size: isCompact ? 28 : 40, weight: .bold, design: fontDesign))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .minimumScaleFactor(0.55)
                        .lineLimit(1)
                }

                Spacer()

                if config.clockShowDate {
                    Text("\(referencePillDateString) • \(weather.conditionDisplay)")
                        .font(.system(size: isCompact ? 9 : 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(1)
                }
            }
            .padding(isCompact ? 10 : 15)
        }
    }

    // MARK: - 14. Calendar Clock (Horloge associée à la date et au calendrier)

    private func style14CalendarClock(w: CGFloat, h: CGFloat) -> some View {
        let isTall = h > w * 1.15
        let isCompact = (h < 165 || w < 165) && !isTall
        let cal = Calendar.current
        let rawH = cal.component(.hour, from: currentDate)
        let dispH = config.clockFormat24h ? rawH : ((rawH % 12 == 0) ? 12 : (rawH % 12))
        let dispM = cal.component(.minute, from: currentDate)

        return ZStack {
            Color(red: 0.06, green: 0.08, blue: 0.13)

            VStack(alignment: .leading, spacing: isTall ? 8 : 4) {
                HStack {
                    HStack(spacing: 4) {
                        Text(shortWeekday(for: currentDate))
                            .foregroundStyle(Color(red: 1.0, green: 0.18, blue: 0.16))
                        Text("\(Calendar.current.component(.day, from: currentDate)) \(shortMonth(for: currentDate))")
                            .foregroundStyle(.white)
                    }
                    .font(.system(size: isCompact ? 10.5 : 13, weight: .bold))
                    .lineLimit(1)

                    Spacer()

                    Image(systemName: "calendar")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(red: 1.0, green: 0.18, blue: 0.16))
                }

                Spacer()

                if isTall {
                    VStack(alignment: .leading, spacing: -6) {
                        Text(String(format: "%02d", dispH))
                            .foregroundStyle(.white)
                        Text(String(format: "%02d", dispM))
                            .foregroundStyle(Color(red: 1.0, green: 0.25, blue: 0.22))
                    }
                    .font(.system(size: min(w * 0.40, 56), weight: .bold, design: fontDesign))
                    .monospacedDigit()

                    Spacer()

                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(CalendarEventService.shared.events.prefix(3)) { ev in
                            HStack(spacing: 5) {
                                Circle().fill(Color.green).frame(width: 5, height: 5)
                                Text(ev.title)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.82))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                    }
                } else {
                    Text(digitalTimeString)
                        .font(.system(size: isCompact ? 28 : 40, weight: .bold, design: fontDesign))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .minimumScaleFactor(0.55)
                        .lineLimit(1)

                    if let nextEvent = CalendarEventService.shared.events.first {
                        HStack(spacing: 5) {
                            Circle().fill(Color.green).frame(width: 5, height: 5)
                            Text(nextEvent.title)
                                .font(.system(size: isCompact ? 8.5 : 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.75))
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(isCompact ? 10 : 15)
        }
    }

    // MARK: - 15. Fullscreen StandBy Clock

    private func style15FullscreenClock(w: CGFloat, h: CGFloat) -> some View {
        let isTall = h > w * 1.15
        let cal = Calendar.current
        let rawH = cal.component(.hour, from: currentDate)
        let dispH = config.clockFormat24h ? rawH : ((rawH % 12 == 0) ? 12 : (rawH % 12))
        let dispM = cal.component(.minute, from: currentDate)

        return ZStack {
            Color.black

            VStack(spacing: isTall ? 4 : 0) {
                if isTall {
                    VStack(spacing: -min(w * 0.08, 12)) {
                        Text(String(format: "%02d", dispH))
                        Text(String(format: "%02d", dispM))
                    }
                    .font(.system(size: min(w * 0.56, h * 0.34), weight: .heavy, design: fontDesign))
                    .foregroundStyle(LinearGradient(colors: [accentColor, Color.white], startPoint: .top, endPoint: .bottom))
                    .monospacedDigit()
                } else {
                    Text(shortDigitalTimeString)
                        .font(.system(size: min(w * 0.42, h * 0.68), weight: .heavy, design: fontDesign))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [accentColor, Color.white],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }

                if config.clockShowDate {
                    Text(referencePillDateString.uppercased())
                        .font(.system(size: max(9, min(w, h) * 0.075), weight: .bold, design: .rounded))
                        .tracking(1.6)
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }
            }
            .padding(8)
        }
    }

    // MARK: - Helpers de Formatage Horaire & Fuseaux

    private static let fmt24: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
    private static let fmt24Sec: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()
    private static let fmt12: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm"; return f
    }()
    private static let fmt12Sec: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm:ss"; return f
    }()
    private static let pillDateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM"
        return f
    }()
    private static let fullDateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private var activeAppLocale: Locale {
        Locale(identifier: LocalizationManager.activeLanguageCode == "fr" ? "fr_FR" : "en_US")
    }

    private var shortDigitalTimeString: String {
        (config.clockFormat24h ? Self.fmt24 : Self.fmt12).string(from: currentDate)
    }

    private var digitalTimeString: String {
        if config.clockShowSeconds {
            return (config.clockFormat24h ? Self.fmt24Sec : Self.fmt12Sec).string(from: currentDate)
        }
        return shortDigitalTimeString
    }

    private var referencePillDateString: String {
        Self.pillDateFmt.locale = activeAppLocale
        return Self.pillDateFmt.string(from: currentDate).replacingOccurrences(of: ".", with: "").capitalized
    }

    private var fullDateString: String {
        Self.fullDateFmt.locale = activeAppLocale
        return Self.fullDateFmt.string(from: currentDate).capitalized
    }

    private var greetingTitle: String {
        let h = Calendar.current.component(.hour, from: currentDate)
        if h < 12 { return loc("widgets.greeting_morning") }
        if h < 18 { return loc("widgets.greeting_afternoon") }
        return loc("widgets.greeting_evening")
    }

    private func shortWeekday(for date: Date) -> String {
        let f = DateFormatter()
        f.locale = activeAppLocale
        f.dateFormat = "EEE"
        return f.string(from: date).replacingOccurrences(of: ".", with: "").capitalized
    }

    private func shortMonth(for date: Date) -> String {
        let f = DateFormatter()
        f.locale = activeAppLocale
        f.dateFormat = "MMM"
        return f.string(from: date).replacingOccurrences(of: ".", with: "").capitalized
    }

    private func worldClockInfo(for tzID: String) -> (city: String, timeString: String, offsetLabel: String, isDaylight: Bool) {
        let tz = TimeZone(identifier: tzID) ?? .current
        let city = tzID.components(separatedBy: "/").last?.replacingOccurrences(of: "_", with: " ") ?? tzID
        let f = DateFormatter()
        f.timeZone = tz
        f.dateFormat = config.clockFormat24h ? "HH:mm" : "h:mm a"
        let timeStr = f.string(from: currentDate)

        var cal = Calendar.current
        cal.timeZone = tz
        let hour = cal.component(.hour, from: currentDate)
        let isDay = (hour >= 6 && hour < 19)

        let diffHours = (tz.secondsFromGMT(for: currentDate) - TimeZone.current.secondsFromGMT(for: currentDate)) / 3600
        let offsetLabel = diffHours == 0 ? "Local" : (diffHours > 0 ? "+\(diffHours)H" : "\(diffHours)H")

        return (city, timeStr, offsetLabel, isDay)
    }
}
