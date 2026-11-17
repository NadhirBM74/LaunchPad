import SwiftUI
import EventKit
import Combine
import AppKit

// MARK: - Styles du Widget Calendrier (Fidèles aux Photos de Référence 6 & 2)

public enum CalendarWidgetStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case compactDate = "compactDate"         // 1. Photo de Référence 6 : "Fri" (Rouge) + "Jun" (Blanc) + Grand "12" sur fond bleu nuit
    case dotMatrix = "dotMatrix"             // 2. Photo de Référence 2 : Bandeau rouge + matrice de points + point rouge du jour
    case monthlyGrid = "monthlyGrid"         // 3. Calendrier mensuel complet avec navigation entre les mois
    case upcomingEvents = "upcomingEvents"   // 4. Date + Prochains événements en direct
    case weeklyView = "weeklyView"           // 5. Bandeau hebdomadaire 7 jours + événements
    case agenda = "agenda"                   // 6. Présentation agenda chronologique avec indicateur d'heure actuelle

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .compactDate: return "1. Date Compacte (Photo Réf. 6)"
        case .dotMatrix: return "2. Matrice de Points (Photo Réf. 2)"
        case .monthlyGrid: return "3. Calendrier Mensuel Interactif"
        case .upcomingEvents: return "4. Prochains Événements"
        case .weeklyView: return "5. Vue Hebdomadaire"
        case .agenda: return "6. Présentation Agenda"
        }
    }
}

// MARK: - Modèle et Service de Synchronisation avec le Calendrier macOS (EventKit)

public struct LaunchpadCalendarEvent: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let colorHex: String
    public let location: String?
    public let isAllDay: Bool

    public var isOngoing: Bool {
        let now = Date()
        return now >= startDate && now <= endDate
    }
}

@MainActor
public final class CalendarEventService: ObservableObject {
    public static let shared = CalendarEventService()

    @Published public private(set) var events: [LaunchpadCalendarEvent] = []
    @Published public private(set) var isAuthorized: Bool = false

    private let store = EKEventStore()

    private init() {
        refreshEvents()
    }

    public func refreshEvents() {
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .fullAccess {
            isAuthorized = true
            loadSystemEvents()
        } else {
            isAuthorized = false
            loadFallbackSchedule()
        }
    }

    public func requestAccessIfNeeded() {
        Task { @MainActor in
            do {
                let granted = try await store.requestFullAccessToEvents()
                self.isAuthorized = granted
                if granted {
                    self.loadSystemEvents()
                }
            } catch {
                self.isAuthorized = false
            }
        }
    }

    private func loadSystemEvents() {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        guard let end = cal.date(byAdding: .day, value: 14, to: start) else { return }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let ekEvents = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }

        if ekEvents.isEmpty {
            loadFallbackSchedule()
            return
        }

        self.events = ekEvents.prefix(12).map { ev in
            let hex: String = {
                if let cg = ev.calendar?.cgColor, let ns = NSColor(cgColor: cg)?.usingColorSpace(.sRGB) {
                    let r = Int(ns.redComponent * 255)
                    let g = Int(ns.greenComponent * 255)
                    let b = Int(ns.blueComponent * 255)
                    return String(format: "#%02X%02X%02X", r, g, b)
                }
                return "#FF3B30"
            }()
            return LaunchpadCalendarEvent(
                id: ev.eventIdentifier ?? UUID().uuidString,
                title: ev.title ?? "Événement",
                startDate: ev.startDate,
                endDate: ev.endDate,
                colorHex: hex,
                location: ev.location,
                isAllDay: ev.isAllDay
            )
        }
    }

    private func loadFallbackSchedule() {
        let cal = Calendar.current
        let now = Date()
        let startOfToday = cal.startOfDay(for: now)
        let currentHour = cal.component(.hour, from: now)

        let e1Start = cal.date(byAdding: .hour, value: max(9, currentHour), to: startOfToday) ?? now
        let e1End = cal.date(byAdding: .minute, value: 60, to: e1Start) ?? now

        let e2Start = cal.date(byAdding: .hour, value: max(11, currentHour + 2), to: startOfToday) ?? now
        let e2End = cal.date(byAdding: .minute, value: 45, to: e2Start) ?? now

        let e3Start = cal.date(byAdding: .hour, value: max(15, currentHour + 4), to: startOfToday) ?? now
        let e3End = cal.date(byAdding: .minute, value: 60, to: e3Start) ?? now

        self.events = [
            LaunchpadCalendarEvent(
                id: "ev-1",
                title: "Design Review & UI",
                startDate: e1Start,
                endDate: e1End,
                colorHex: "#FF2D55",
                location: "Studio Apple",
                isAllDay: false
            ),
            LaunchpadCalendarEvent(
                id: "ev-2",
                title: "Point Produit LaunchPad",
                startDate: e2Start,
                endDate: e2End,
                colorHex: "#0A84FF",
                location: "Visio",
                isAllDay: false
            ),
            LaunchpadCalendarEvent(
                id: "ev-3",
                title: "Session Code SwiftUI",
                startDate: e3Start,
                endDate: e3End,
                colorHex: "#30D158",
                location: "MacBook Pro",
                isAllDay: false
            )
        ]
    }
}

// MARK: - Vue Principale du Widget Calendrier

struct PremiumCalendarWidgetView: View {
    let config: CustomWidgetConfig
    var targetSize: CGSize? = nil

    @ObservedObject private var widgetManager = WidgetManager.shared
    @ObservedObject private var calendarService = CalendarEventService.shared
    @State private var currentDate = Date()
    @State private var displayedMonthOffset: Int = 0
    @State private var selectedDayOffset: Int = 0

    var body: some View {
        let w = targetSize?.width ?? config.size.width
        let h = targetSize?.height ?? config.size.height
        let cornerRadius = widgetManager.cornerRadius

        GeometryReader { geo in
            let availW = geo.size.width
            let availH = geo.size.height

            ZStack {
                switch config.calendarStyle {
                case .compactDate:
                    compactDateReferenceView(w: availW, h: availH)
                case .dotMatrix:
                    dotMatrixReferenceView(w: availW, h: availH)
                case .monthlyGrid:
                    monthlyGridView(w: availW, h: availH)
                case .upcomingEvents:
                    upcomingEventsView(w: availW, h: availH)
                case .weeklyView:
                    weeklyCalendarView(w: availW, h: availH)
                case .agenda:
                    agendaTimelineView(w: availW, h: availH)
                }
            }
            .frame(width: availW, height: availH)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.35),
                                Color.white.opacity(0.10),
                                Color.white.opacity(0.20)
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
            calendarService.refreshEvents()
        }
    }

    // MARK: - 1. Compact Date (Reproduction 1:1 de la Photo de Référence 6 : "Fri Jun" + "12")

    private func compactDateReferenceView(w: CGFloat, h: CGFloat) -> some View {
        let isWide = w > h * 1.35

        return ZStack {
            // Fond bleu nuit profond satiné exactement comme sur la Photo de Référence 6
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.11, blue: 0.18),
                    Color(red: 0.05, green: 0.07, blue: 0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Reflet supérieur subtil
            RadialGradient(
                colors: [Color.white.opacity(0.07), Color.clear],
                center: .top,
                startRadius: 2,
                endRadius: max(w, h) * 0.65
            )

            if isWide {
                // Version Moyenne (2×1) : Date compacte Référence 6 à gauche + Événements du jour à droite
                HStack(spacing: 16) {
                    VStack(spacing: 2) {
                        HStack(spacing: 6) {
                            Text(shortWeekdayString(for: currentDate))
                                .font(.system(size: min(h * 0.17, 22), weight: .bold))
                                .foregroundStyle(Color(red: 1.00, green: 0.16, blue: 0.14))
                            Text(shortMonthString(for: currentDate))
                                .font(.system(size: min(h * 0.17, 22), weight: .bold))
                                .foregroundStyle(.white)
                        }
                        Text(dayNumberString(for: currentDate))
                            .font(.system(size: min(h * 0.56, 76), weight: .bold))
                            .foregroundStyle(.white)
                            .tracking(-1.5)
                    }
                    .frame(width: min(w * 0.42, 130))

                    Rectangle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 1, height: h * 0.68)

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(calendarService.events.prefix(3)) { ev in
                            eventCompactRow(ev)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 16)
            } else {
                // Version Carrée / Verticale : Reproduction exacte de la Photo de Référence 6
                let headerFontSize = min(w, h) * 0.165
                let dayFontSize = min(w, h) * 0.56

                VStack(spacing: min(w, h) * 0.02) {
                    Spacer(minLength: 4)

                    HStack(spacing: headerFontSize * 0.28) {
                        Text(shortWeekdayString(for: currentDate))
                            .font(.system(size: headerFontSize, weight: .bold))
                            .foregroundStyle(Color(red: 1.00, green: 0.15, blue: 0.12))

                        Text(shortMonthString(for: currentDate))
                            .font(.system(size: headerFontSize, weight: .bold))
                            .foregroundStyle(.white)
                    }

                    Text(dayNumberString(for: currentDate))
                        .font(.system(size: dayFontSize, weight: .bold))
                        .foregroundStyle(.white)
                        .tracking(-2.0)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)

                    Spacer(minLength: 4)
                }
                .padding(10)
            }
        }
    }

    // MARK: - 2. Dot Matrix Calendar (Reproduction 1:1 de la Photo de Référence 2)

    private func dotMatrixReferenceView(w: CGFloat, h: CGFloat) -> some View {
        let cal = Calendar.current
        let todayDay = cal.component(.day, from: currentDate)
        let activeDotIndex = (todayDay - 1) % 21
        let dotSpacingX = w * 0.088
        let dotSpacingY = h * 0.115
        let dotSize = min(w, h) * 0.048

        return ZStack(alignment: .top) {
            // Corps pierre chaude comme sur la Photo 2
            LinearGradient(
                colors: [
                    Color(red: 0.60, green: 0.57, blue: 0.55),
                    Color(red: 0.51, green: 0.48, blue: 0.46)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Bandeau supérieur rouge carmin vif
            HStack {
                Text(shortWeekdayString(for: currentDate).uppercased())
                    .font(.system(size: min(w, h) * 0.085, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.92))
                Spacer()
                Text("\(shortMonthString(for: currentDate).uppercased()) \(dayNumberString(for: currentDate))")
                    .font(.system(size: min(w, h) * 0.085, weight: .heavy))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, w * 0.10)
            .frame(height: h * 0.26)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 1.00, green: 0.14, blue: 0.28),
                        Color(red: 0.96, green: 0.10, blue: 0.22)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            // Grille matricielle 7 × 3 avec le point du jour en rouge lumineux
            VStack(spacing: dotSpacingY) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: dotSpacingX) {
                        ForEach(0..<7, id: \.self) { col in
                            let idx = row * 7 + col
                            let isEdgeBlank = (row == 0 && col < 2) || (row == 2 && col > 4)
                            if isEdgeBlank {
                                Circle()
                                    .fill(Color.clear)
                                    .frame(width: dotSize, height: dotSize)
                            } else if idx == activeDotIndex || (row == 1 && col == 4) {
                                Circle()
                                    .fill(Color(red: 1.00, green: 0.16, blue: 0.16))
                                    .frame(width: dotSize * 1.65, height: dotSize * 1.65)
                                    .shadow(color: Color.red.opacity(0.65), radius: 4)
                            } else {
                                Circle()
                                    .fill(Color(red: 0.13, green: 0.12, blue: 0.11))
                                    .frame(width: dotSize, height: dotSize)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .offset(y: h * 0.12)
        }
    }

    // MARK: - 3. Calendrier Mensuel Interactif (Navigation entre les mois + Grille alignée)

    private func monthlyGridView(w: CGFloat, h: CGFloat) -> some View {
        let cal = Calendar.current
        let targetMonthDate = cal.date(byAdding: .month, value: displayedMonthOffset, to: currentDate) ?? currentDate
        let days = generateMonthGrid(for: targetMonthDate)
        let isCompact = h < 165

        return ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.10, blue: 0.16),
                    Color(red: 0.05, green: 0.06, blue: 0.10)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: isCompact ? 3 : 6) {
                // En-tête avec navigation < Mois Année >
                HStack {
                    Button {
                        withAnimation(AppleDesignSystem.Springs.snappy) {
                            displayedMonthOffset = 0
                        }
                    } label: {
                        Text(monthYearTitle(for: targetMonthDate))
                            .font(.system(size: isCompact ? 10.5 : 12.5, weight: .bold))
                            .foregroundStyle(displayedMonthOffset == 0 ? Color(red: 1.0, green: 0.24, blue: 0.20) : .white)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    HStack(spacing: 6) {
                        Button {
                            withAnimation(AppleDesignSystem.Springs.snappy) {
                                displayedMonthOffset -= 1
                            }
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: isCompact ? 8.5 : 10, weight: .bold))
                                .foregroundStyle(.white.opacity(0.75))
                                .frame(width: 18, height: 18)
                                .background(Color.white.opacity(0.08), in: Circle())
                        }
                        .buttonStyle(.plain)

                        Button {
                            withAnimation(AppleDesignSystem.Springs.snappy) {
                                displayedMonthOffset += 1
                            }
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: isCompact ? 8.5 : 10, weight: .bold))
                                .foregroundStyle(.white.opacity(0.75))
                                .frame(width: 18, height: 18)
                                .background(Color.white.opacity(0.08), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Jours de la semaine (L M M J V S D)
                let symbols = ["L", "M", "M", "J", "V", "S", "D"]
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { idx in
                        Text(symbols[idx])
                            .font(.system(size: isCompact ? 7.5 : 8.5, weight: .bold))
                            .foregroundStyle(idx >= 5 ? .white.opacity(0.40) : .white.opacity(0.60))
                            .frame(maxWidth: .infinity)
                    }
                }

                // Grille des jours
                let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
                LazyVGrid(columns: columns, spacing: isCompact ? 1.5 : 3) {
                    ForEach(Array(days.enumerated()), id: \.offset) { _, dayItem in
                        if let dayNum = dayItem.day {
                            let isToday = dayItem.isToday
                            ZStack {
                                if isToday {
                                    Circle()
                                        .fill(Color(red: 1.00, green: 0.18, blue: 0.16))
                                        .frame(width: isCompact ? 15 : 19, height: isCompact ? 15 : 19)
                                }
                                VStack(spacing: 0.5) {
                                    Text("\(dayNum)")
                                        .font(.system(size: isCompact ? 8.5 : 10, weight: isToday ? .bold : .medium, design: .rounded))
                                        .foregroundStyle(isToday ? .white : (dayItem.hasEvent ? .white : .white.opacity(0.78)))
                                    if dayItem.hasEvent && !isToday && !isCompact {
                                        Circle()
                                            .fill(Color.cyan)
                                            .frame(width: 3, height: 3)
                                    }
                                }
                            }
                            .frame(height: isCompact ? 15 : 19)
                        } else {
                            Color.clear.frame(height: isCompact ? 15 : 19)
                        }
                    }
                }
            }
            .padding(isCompact ? 9 : 13)
        }
    }

    // MARK: - 4. Prochains Événements

    private func upcomingEventsView(w: CGFloat, h: CGFloat) -> some View {
        let isCompact = h < 165
        return ZStack {
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.10, blue: 0.16), Color(red: 0.04, green: 0.05, blue: 0.09)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: isCompact ? 5 : 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(shortWeekdayString(for: currentDate).uppercased())
                        .font(.system(size: isCompact ? 11 : 13, weight: .heavy))
                        .foregroundStyle(Color(red: 1.0, green: 0.20, blue: 0.18))
                    Text("\(dayNumberString(for: currentDate)) \(shortMonthString(for: currentDate))")
                        .font(.system(size: isCompact ? 11 : 13, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("\(calendarService.events.count) évén.")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.08), in: Capsule())
                }

                Divider().background(Color.white.opacity(0.12))

                VStack(alignment: .leading, spacing: isCompact ? 4 : 6) {
                    ForEach(calendarService.events.prefix(isCompact ? 2 : 4)) { ev in
                        eventCompactRow(ev)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(isCompact ? 10 : 14)
        }
    }

    // MARK: - 5. Vue Hebdomadaire (7 Jours + Événements)

    private func weeklyCalendarView(w: CGFloat, h: CGFloat) -> some View {
        let isCompact = h < 165
        let cal = Calendar.current
        let weekDays: [(offset: Int, letter: String, num: String, isToday: Bool)] = (-1...5).map { offset in
            let d = cal.date(byAdding: .day, value: offset, to: currentDate) ?? currentDate
            let letter = String(shortWeekdayString(for: d).prefix(1)).uppercased()
            let num = dayNumberString(for: d)
            return (offset, letter, num, offset == 0)
        }

        return ZStack {
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.10, blue: 0.16), Color(red: 0.04, green: 0.06, blue: 0.10)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: isCompact ? 6 : 10) {
                // Bandeau des 7 jours
                HStack(spacing: 3) {
                    ForEach(weekDays, id: \.offset) { item in
                        let isSelected = (selectedDayOffset == item.offset)
                        Button {
                            withAnimation(AppleDesignSystem.Springs.snappy) {
                                selectedDayOffset = item.offset
                            }
                        } label: {
                            VStack(spacing: 2) {
                                Text(item.letter)
                                    .font(.system(size: isCompact ? 7.5 : 8.5, weight: .bold))
                                    .foregroundStyle(isSelected ? .white : .white.opacity(0.50))
                                Text(item.num)
                                    .font(.system(size: isCompact ? 9.5 : 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .frame(width: isCompact ? 18 : 22, height: isCompact ? 18 : 22)
                                    .background(
                                        Circle()
                                            .fill(
                                                item.isToday
                                                    ? Color(red: 1.0, green: 0.18, blue: 0.16)
                                                    : (isSelected ? Color.white.opacity(0.22) : Color.clear)
                                            )
                                    )
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    ForEach(calendarService.events.prefix(isCompact ? 2 : 3)) { ev in
                        eventCompactRow(ev)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(isCompact ? 10 : 14)
        }
    }

    // MARK: - 6. Présentation Agenda Chronologique

    private func agendaTimelineView(w: CGFloat, h: CGFloat) -> some View {
        let isCompact = h < 165
        return ZStack {
            Color(red: 0.06, green: 0.08, blue: 0.12)

            VStack(alignment: .leading, spacing: isCompact ? 5 : 8) {
                HStack {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color(red: 1.0, green: 0.18, blue: 0.16))
                            .frame(width: 7, height: 7)
                        Text("AGENDA DU JOUR")
                            .font(.system(size: isCompact ? 9 : 10, weight: .heavy))
                            .tracking(0.8)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    Spacer()
                    Text("\(shortWeekdayString(for: currentDate)) \(dayNumberString(for: currentDate))")
                        .font(.system(size: isCompact ? 9.5 : 11, weight: .bold))
                        .foregroundStyle(Color(red: 1.0, green: 0.25, blue: 0.22))
                }

                // Ligne rouge d'heure actuelle ("Maintenant")
                HStack(spacing: 6) {
                    Text(Self.timeFmt.string(from: currentDate))
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.red)
                    Circle().fill(Color.red).frame(width: 5, height: 5)
                    Rectangle().fill(Color.red.opacity(0.65)).frame(height: 1)
                }

                VStack(alignment: .leading, spacing: isCompact ? 4 : 6) {
                    ForEach(calendarService.events.prefix(isCompact ? 2 : 3)) { ev in
                        eventCompactRow(ev)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(isCompact ? 10 : 14)
        }
    }

    // MARK: - Ligne d'Événement Réutilisable

    private func eventCompactRow(_ ev: LaunchpadCalendarEvent) -> some View {
        let barColor = Color(nsColor: NSColor(hexString: ev.colorHex) ?? .systemRed)
        return HStack(spacing: 7) {
            Capsule()
                .fill(barColor)
                .frame(width: 3, height: 24)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(ev.title)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if ev.isOngoing {
                        Text("EN COURS")
                            .font(.system(size: 6.5, weight: .black))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.green, in: Capsule())
                    }
                }
                Text("\(Self.timeFmt.string(from: ev.startDate)) – \(Self.timeFmt.string(from: ev.endDate))")
                    .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Formatage des Dates

    private static let weekdayFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE"
        return f
    }()

    private static let monthFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM"
        return f
    }()

    private static let monthYearFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private func shortWeekdayString(for date: Date) -> String {
        Self.weekdayFmt.string(from: date)
    }

    private func shortMonthString(for date: Date) -> String {
        Self.monthFmt.string(from: date)
    }

    private func dayNumberString(for date: Date) -> String {
        "\(Calendar.current.component(.day, from: date))"
    }

    private func monthYearTitle(for date: Date) -> String {
        Self.monthYearFmt.locale = LocalizationManager.shared.effectiveLocale
        return Self.monthYearFmt.string(from: date).capitalized
    }

    private struct MonthDayCell {
        let day: Int?
        let isToday: Bool
        let hasEvent: Bool
    }

    private func generateMonthGrid(for monthDate: Date) -> [MonthDayCell] {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: monthDate)
        guard let firstOfMonth = cal.date(from: comps),
              let range = cal.range(of: .day, in: .month, for: firstOfMonth) else { return [] }

        let weekday = cal.component(.weekday, from: firstOfMonth)
        // Lundi = 0 ... Dimanche = 6
        let leadingEmpty = (weekday + 5) % 7
        let todayComps = cal.dateComponents([.year, .month, .day], from: currentDate)

        var cells: [MonthDayCell] = Array(repeating: MonthDayCell(day: nil, isToday: false, hasEvent: false), count: leadingEmpty)
        for d in range {
            let isToday = (comps.year == todayComps.year && comps.month == todayComps.month && d == todayComps.day)
            let hasEvent = (d % 5 == 0 || isToday)
            cells.append(MonthDayCell(day: d, isToday: isToday, hasEvent: hasEvent))
        }
        return cells
    }
}
