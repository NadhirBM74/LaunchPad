import SwiftUI
import Combine

// MARK: - Bandeau supérieur de Widgets Pro

struct WidgetBannerView: View {
    let backgroundStyle: AppTheme
    @ObservedObject private var locManager = LocalizationManager.shared
    @ObservedObject private var stats = SystemStatsMonitor.shared

    @AppStorage(PrefKey.widgetBannerCollapsed) private var isCollapsed = false
    @AppStorage(PrefKey.widgetClockEnabled) private var clockEnabled = true
    @AppStorage(PrefKey.widgetSystemEnabled) private var systemEnabled = true
    @AppStorage(PrefKey.widgetQuickNoteEnabled) private var quickNoteEnabled = true
    @AppStorage(PrefKey.widgetQuickNoteText) private var quickNoteText = ""

    @State private var currentDate = Date()
    @State private var timer: AnyCancellable?

    var body: some View {
        Group {
            if isCollapsed {
                collapsedBar
            } else {
                expandedBanner
            }
        }
        .onAppear {
            stats.startMonitoring()
            if LaunchpadViewModel.isLaunchpadVisible {
                currentDate = Date()
                startClockTimer()
            }
        }
        .onDisappear {
            stats.stopMonitoring()
            timer?.cancel()
            timer = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .launchpadVisibilityDidChange)) { notif in
            let isVisible = (notif.object as? Bool) ?? false
            if isVisible {
                currentDate = Date()
                stats.startMonitoring()
                startClockTimer()
            } else {
                stats.stopMonitoring()
                timer?.cancel()
                timer = nil
            }
        }
    }

    // MARK: - Horloge en temps réel

    private func startClockTimer() {
        timer?.cancel()
        timer = Timer.publish(every: 15.0, tolerance: 3.0, on: .main, in: .common)
            .autoconnect()
            .sink { [self] date in
                if !Calendar.current.isDate(date, equalTo: self.currentDate, toGranularity: .minute) {
                    self.currentDate = date
                }
            }
    }

    // MARK: - Bandeau déplié

    private var expandedBanner: some View {
        HStack(spacing: 12) {
            if clockEnabled {
                clockCard
            }
            if systemEnabled {
                systemCard
            }
            if quickNoteEnabled {
                quickNoteCard
            }

            // Bouton pour replier
            collapseButton
        }
        .frame(maxWidth: 860)
        .padding(.horizontal, 8)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.96)),
            removal: .opacity.combined(with: .scale(scale: 0.96))
        ))
    }

    // MARK: - Version repliée (Pilule discrète)

    private var collapsedBar: some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                isCollapsed = false
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(red: 1.0, green: 0.84, blue: 0.4))
                Text(formattedShortTime)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                if stats.hasBattery {
                    Circle().fill(.white.opacity(0.25)).frame(width: 3, height: 3)
                    Image(systemName: stats.isCharging ? "battery.100.bolt" : "battery.100")
                        .font(.system(size: 11))
                        .foregroundStyle(stats.batteryPercent < 20 ? Color.red : Color.green.opacity(0.9))
                    Text("\(stats.batteryPercent)%")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.leading, 2)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(cardBackground(cornerRadius: 16))
            .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .help(loc("widgets.expand"))
        .transition(.opacity)
    }

    // MARK: - Bouton Réduire

    private var collapseButton: some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                isCollapsed = true
            }
        } label: {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 26, height: 26)
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.70))
            }
        }
        .buttonStyle(.plain)
        .help(loc("widgets.collapse"))
    }

    // MARK: - Widget 1: Horloge & Date

    private var clockCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color.orange.opacity(0.8), Color.pink.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 38, height: 38)
                    .shadow(color: Color.orange.opacity(0.35), radius: 6, y: 2)
                Image(systemName: greetingIcon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(formattedTime)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(greetingText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                }
                Text(formattedDate)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.white.opacity(0.60))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(cardBackground(cornerRadius: 18))
        .shadow(color: .black.opacity(0.20), radius: 10, y: 4)
    }

    // MARK: - Widget 2: Moniteur Système

    private var systemCard: some View {
        HStack(spacing: 14) {
            // CPU
            systemStatGauge(
                icon: "cpu",
                title: loc("widgets.cpu"),
                value: "\(stats.cpuPercent)%",
                progress: Double(stats.cpuPercent) / 100.0,
                color: Color(red: 0.22, green: 0.80, blue: 0.98)
            )

            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 1, height: 26)

            // RAM
            systemStatGauge(
                icon: "memorychip",
                title: loc("widgets.ram"),
                value: String(format: "%.1f Go", stats.ramUsedGB),
                progress: Double(stats.ramPercent) / 100.0,
                color: Color(red: 0.68, green: 0.58, blue: 1.0)
            )

            // Batterie (si présente)
            if stats.hasBattery {
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 1, height: 26)

                systemStatGauge(
                    icon: stats.isCharging ? "battery.100.bolt" : "battery.75",
                    title: stats.isCharging ? loc("widgets.battery_charging") : loc("widgets.battery"),
                    value: "\(stats.batteryPercent)%",
                    progress: Double(stats.batteryPercent) / 100.0,
                    color: stats.batteryPercent < 20
                        ? Color(red: 1.0, green: 0.35, blue: 0.35)
                        : Color(red: 0.30, green: 0.88, blue: 0.45)
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(cardBackground(cornerRadius: 18))
        .shadow(color: .black.opacity(0.20), radius: 10, y: 4)
    }

    private func systemStatGauge(icon: String, title: String, value: String, progress: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                Text(value)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            HStack(spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.14))
                        Capsule()
                            .fill(color)
                            .frame(width: max(4, geo.size.width * min(1.0, max(0.0, progress))))
                    }
                }
                .frame(width: 44, height: 4)

                Text(title)
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
    }

    // MARK: - Widget 3: Note Rapide

    private var quickNoteCard: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(red: 1.0, green: 0.82, blue: 0.38))

            ZStack(alignment: .leading) {
                if quickNoteText.isEmpty {
                    Text(loc("widgets.quicknote_placeholder"))
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.40))
                        .allowsHitTesting(false)
                }
                TextField("", text: $quickNoteText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .frame(minWidth: 90, maxWidth: 170)
            }

            if !quickNoteText.isEmpty {
                Button {
                    quickNoteText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.50))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(cardBackground(cornerRadius: 18))
        .shadow(color: .black.opacity(0.20), radius: 10, y: 4)
    }

    // MARK: - Style d'arrière-plan des cartes

    @ViewBuilder
    private func cardBackground(cornerRadius: CGFloat) -> some View {
        if backgroundStyle == .liquidGlass {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .liquidGlassCard(cornerRadius: cornerRadius, interactive: false)
        } else if backgroundStyle == .glass {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.20), lineWidth: 0.8)
                )
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.black.opacity(0.50))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.8)
                )
        }
    }

    // MARK: - Helpers Date & Heure

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter
    }()

    private static let cachedUserName: String = NSFullUserName()

    private var formattedTime: String {
        Self.timeFormatter.string(from: currentDate)
    }

    private var formattedShortTime: String {
        Self.timeFormatter.string(from: currentDate)
    }

    private var formattedDate: String {
        let locale = LocalizationManager.shared.effectiveLocale
        if Self.dateFormatter.locale != locale {
            Self.dateFormatter.locale = locale
        }
        return Self.dateFormatter.string(from: currentDate).capitalized
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: currentDate)
        let greeting: String
        if hour >= 5 && hour < 12 {
            greeting = loc("widgets.greeting_morning")
        } else if hour >= 12 && hour < 18 {
            greeting = loc("widgets.greeting_afternoon")
        } else {
            greeting = loc("widgets.greeting_evening")
        }
        let userName = Self.cachedUserName
        if !userName.isEmpty && userName != "root" {
            return "\(greeting), \(userName)"
        }
        return greeting
    }

    private var greetingIcon: String {
        let hour = Calendar.current.component(.hour, from: currentDate)
        if hour >= 6 && hour < 18 {
            return "sun.max.fill"
        } else if hour >= 18 && hour < 22 {
            return "sunset.fill"
        } else {
            return "moon.stars.fill"
        }
    }
}
