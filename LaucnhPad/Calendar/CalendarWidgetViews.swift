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
        loc("calendar.style.\(rawValue).title")
    }
}

// MARK: - Modèle et Service de Synchronisation avec le Calendrier macOS (EventKit)

nonisolated public struct LaunchpadCalendarEvent: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let colorHex: String
    public let color: Color
    public let location: String?
    public let isAllDay: Bool

    public init(
        id: String,
        title: String,
        startDate: Date,
        endDate: Date,
        colorHex: String,
        location: String?,
        isAllDay: Bool
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.colorHex = colorHex
        self.color = Color(nsColor: NSColor(hexString: colorHex) ?? .systemRed)
        self.location = location
        self.isAllDay = isAllDay
    }

    public var isOngoing: Bool {
        isOngoing(at: Date())
    }

    public func isOngoing(at referenceDate: Date) -> Bool {
        referenceDate >= startDate && referenceDate <= endDate
    }
}

@MainActor
public final class CalendarEventService: ObservableObject {
    public static let shared = CalendarEventService()

    @Published public private(set) var events: [LaunchpadCalendarEvent] = []
    @Published public private(set) var isAuthorized: Bool = false

    private let store = EKEventStore()
    private var lastFetchUptime: TimeInterval = 0
    private var fetchTask: Task<Void, Never>?

    private init() {
        loadFallbackSchedule()
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("LaunchpadLanguageDidChange"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isAuthorized else { return }
                self.loadFallbackSchedule()
            }
        }
        Task { @MainActor [weak self] in
            self?.refreshEvents(force: true)
        }
    }

    public func refreshEvents(force: Bool = false) {
        let now = ProcessInfo.processInfo.systemUptime
        if !force && (now - lastFetchUptime) < 3.0 {
            return
        }
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .fullAccess {
            isAuthorized = true
            lastFetchUptime = now
            loadSystemEvents()
        } else {
            isAuthorized = false
            lastFetchUptime = now
            if events.isEmpty { loadFallbackSchedule() }
        }
    }

    public func requestAccessIfNeeded() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let granted = try await self.store.requestFullAccessToEvents()
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
        fetchTask?.cancel()
        fetchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let cal = Calendar.current
            let start = cal.startOfDay(for: Date())
            guard let end = cal.date(byAdding: .day, value: 14, to: start) else { return }
            let eventStore = self.store
            let loaded = await Task.detached(priority: .utility) { () -> [LaunchpadCalendarEvent] in
                let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
                let ekEvents = eventStore.events(matching: predicate).sorted { $0.startDate < $1.startDate }
                return ekEvents.prefix(12).map { ev in
                    let hex: String = {
                        if let cg = ev.calendar?.cgColor, let ns = NSColor(cgColor: cg)?.usingColorSpace(.sRGB) {
                            let r = Int(ns.redComponent * 255)
                            let g = Int(ns.greenComponent * 255)
                            let b = Int(ns.blueComponent * 255)
                            return String(format: "#%02X%02X%02X", r, g, b)
                        }
                        return "#FF3B30"
                    }()
                    let baseID = ev.eventIdentifier ?? UUID().uuidString
                    let uniqueID = "\(baseID)_\(Int(ev.startDate.timeIntervalSince1970))"
                    return LaunchpadCalendarEvent(
                        id: uniqueID,
                        title: ev.title ?? loc("calendar.event_default"),
                        startDate: ev.startDate,
                        endDate: ev.endDate,
                        colorHex: hex,
                        location: ev.location,
                        isAllDay: ev.isAllDay
                    )
                }
            }.value

            guard !Task.isCancelled else { return }
            if loaded.isEmpty {
                self.loadFallbackSchedule()
            } else if self.events != loaded {
                self.events = loaded
            }
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
                title: loc("calendar.demo.design_review"),
                startDate: e1Start,
                endDate: e1End,
                colorHex: "#FF2D55",
                location: loc("calendar.demo.studio"),
                isAllDay: false
            ),
            LaunchpadCalendarEvent(
                id: "ev-2",
                title: loc("calendar.demo.product_sync"),
                startDate: e2Start,
                endDate: e2End,
                colorHex: "#0A84FF",
                location: loc("calendar.demo.video_call"),
                isAllDay: false
            ),
            LaunchpadCalendarEvent(
                id: "ev-3",
                title: loc("calendar.demo.swiftui_session"),
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
    var isPreview: Bool = false

    @ObservedObject private var widgetManager = WidgetManager.shared
    @ObservedObject private var calendarService = CalendarEventService.shared
    @ObservedObject private var locManager = LocalizationManager.shared
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
            if !isPreview {
                calendarService.refreshEvents()
            }
        }
    }

    // MARK: - 1. Compact Date (Reproduction 1:1 de la Photo de Référence 6 : "Fri Jun" + "12")

    private func compactDateReferenceView(w: CGFloat, h: CGFloat) -> some View {
        let isWide = w > h * 1.35
        let isTall = h > w * 1.15
        let isLargeSquare = w >= 210 && h >= 210

        return ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.11, blue: 0.18),
                    Color(red: 0.05, green: 0.07, blue: 0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [Color.white.opacity(0.07), Color.clear],
                center: .top,
                startRadius: 2,
                endRadius: max(w, h) * 0.65
            )

            if isWide {
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
            } else if isTall || isLargeSquare {
                let headerSize: CGFloat = min(w * 0.115, 19)
                let daySize: CGFloat = min(w * 0.34, h * 0.24)
                let eventLimit = isTall ? (w < 190 ? 3 : 4) : 3

                VStack(alignment: .leading, spacing: isTall ? 10 : 8) {
                    VStack(spacing: 2) {
                        HStack(spacing: 6) {
                            Text(shortWeekdayString(for: currentDate).uppercased())
                                .font(.system(size: headerSize, weight: .bold))
                                .foregroundStyle(Color(red: 1.00, green: 0.16, blue: 0.14))
                            Text(shortMonthString(for: currentDate).uppercased())
                                .font(.system(size: headerSize, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        Text(dayNumberString(for: currentDate))
                            .font(.system(size: daySize, weight: .bold))
                            .foregroundStyle(.white)
                            .tracking(-1.5)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)

                    Rectangle()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 1)

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(calendarService.events.prefix(eventLimit)) { ev in
                            eventCompactRow(ev)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(w < 190 ? 11 : 16)
            } else {
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
        let isTall = h > w * 1.15
        let effectiveH = isTall ? min(w * 1.05, h * 0.48) : h
        let dotSpacingX = w * 0.088
        let dotSpacingY = isTall ? min(dotSpacingX * 1.15, effectiveH * 0.13) : effectiveH * 0.115
        let dotSize = min(w, effectiveH) * 0.048
        let bannerH = isTall ? min(h * 0.16, 46) : h * 0.26

        return ZStack(alignment: .top) {
            LinearGradient(
                colors: [
                    Color(red: 0.60, green: 0.57, blue: 0.55),
                    Color(red: 0.51, green: 0.48, blue: 0.46)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 0) {
                HStack {
                    Text(shortWeekdayString(for: currentDate).uppercased())
                        .font(.system(size: min(w, effectiveH) * 0.085, weight: .heavy))
                        .foregroundStyle(.white.opacity(0.92))
                    Spacer()
                    Text("\(shortMonthString(for: currentDate).uppercased()) \(dayNumberString(for: currentDate))")
                        .font(.system(size: min(w, effectiveH) * 0.085, weight: .heavy))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, w * 0.10)
                .frame(height: bannerH)
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
                .padding(.top, isTall ? 14 : 0)
                .frame(maxHeight: isTall ? nil : .infinity)

                if isTall {
                    Spacer(minLength: 10)

                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(calendarService.events.prefix(w < 190 ? 3 : 4)) { ev in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color(red: 1.00, green: 0.16, blue: 0.16))
                                    .frame(width: 5, height: 5)
                                Text(ev.title)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Color(red: 0.10, green: 0.09, blue: 0.08))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                Text(Self.timeFmt.string(from: ev.startDate))
                                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Color(red: 0.18, green: 0.16, blue: 0.15).opacity(0.72))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.28), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 12)
                }
            }
        }
    }

    // MARK: - 3. Calendrier Mensuel Interactif (Navigation entre les mois + Grille alignée)

    private func monthlyGridView(w: CGFloat, h: CGFloat) -> some View {
        let cal = Calendar.current
        let targetMonthDate = cal.date(byAdding: .month, value: displayedMonthOffset, to: currentDate) ?? currentDate
        let days = generateMonthGrid(for: targetMonthDate)
        let isTall = h > w * 1.15
        let isCompact = (h < 165 || w < 185) && !isTall
        let isNarrow = w < 190

        return ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.10, blue: 0.16),
                    Color(red: 0.05, green: 0.06, blue: 0.10)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: isNarrow ? 4 : (isCompact ? 3 : 6)) {
                HStack {
                    Button {
                        withAnimation(AppleDesignSystem.Springs.snappy) {
                            displayedMonthOffset = 0
                        }
                    } label: {
                        Text(monthYearTitle(for: targetMonthDate))
                            .font(.system(size: isNarrow ? 10 : (isCompact ? 10.5 : 12.5), weight: .bold))
                            .foregroundStyle(displayedMonthOffset == 0 ? Color(red: 1.0, green: 0.24, blue: 0.20) : .white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 4)

                    HStack(spacing: isNarrow ? 4 : 6) {
                        Button {
                            withAnimation(AppleDesignSystem.Springs.snappy) {
                                displayedMonthOffset -= 1
                            }
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: isNarrow ? 8 : 10, weight: .bold))
                                .foregroundStyle(.white.opacity(0.75))
                                .frame(width: isNarrow ? 16 : 18, height: isNarrow ? 16 : 18)
                                .background(Color.white.opacity(0.08), in: Circle())
                        }
                        .buttonStyle(.plain)

                        Button {
                            withAnimation(AppleDesignSystem.Springs.snappy) {
                                displayedMonthOffset += 1
                            }
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: isNarrow ? 8 : 10, weight: .bold))
                                .foregroundStyle(.white.opacity(0.75))
                                .frame(width: isNarrow ? 16 : 18, height: isNarrow ? 16 : 18)
                                .background(Color.white.opacity(0.08), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                let symbols = weekdaySymbolsMonFirst
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { idx in
                        Text(symbols[idx])
                            .font(.system(size: isNarrow ? 7.5 : 8.5, weight: .bold))
                            .foregroundStyle(idx >= 5 ? .white.opacity(0.40) : .white.opacity(0.60))
                            .frame(maxWidth: .infinity)
                    }
                }

                let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
                let cellH: CGFloat = isNarrow ? 15 : (isCompact ? 15 : 19)
                LazyVGrid(columns: columns, spacing: isNarrow ? 1.5 : (isCompact ? 1.5 : 3)) {
                    ForEach(Array(days.enumerated()), id: \.offset) { _, dayItem in
                        if let dayNum = dayItem.day {
                            let isToday = dayItem.isToday
                            ZStack {
                                if isToday {
                                    Circle()
                                        .fill(Color(red: 1.00, green: 0.18, blue: 0.16))
                                        .frame(width: cellH, height: cellH)
                                }
                                VStack(spacing: 0.5) {
                                    Text("\(dayNum)")
                                        .font(.system(size: isNarrow ? 8.0 : (isCompact ? 8.5 : 10), weight: isToday ? .bold : .medium, design: .rounded))
                                        .foregroundStyle(isToday ? .white : (dayItem.hasEvent ? .white : .white.opacity(0.78)))
                                    if dayItem.hasEvent && !isToday && !isCompact && !isNarrow {
                                        Circle()
                                            .fill(Color.cyan)
                                            .frame(width: 3, height: 3)
                                    }
                                }
                            }
                            .frame(height: cellH)
                        } else {
                            Color.clear.frame(height: cellH)
                        }
                    }
                }

                if isTall {
                    Divider().background(Color.white.opacity(0.12))
                        .padding(.vertical, 2)

                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(calendarService.events.prefix(isNarrow ? 3 : 4)) { ev in
                            eventCompactRow(ev)
                        }
                    }

                    Spacer(minLength: 0)
                }
            }
            .padding(isNarrow ? 8 : (isCompact ? 9 : 13))
        }
    }

    // MARK: - 4. Prochains Événements

    private func upcomingEventsView(w: CGFloat, h: CGFloat) -> some View {
        let isTall = h > w * 1.15
        let isCompact = h < 165
        let isNarrow = w < 190
        let eventCount = isTall ? (h > 380 ? 7 : 5) : (isCompact ? 2 : 4)

        return ZStack {
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.10, blue: 0.16), Color(red: 0.04, green: 0.05, blue: 0.09)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: isCompact ? 5 : 8) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(shortWeekdayString(for: currentDate).uppercased())
                        .font(.system(size: isNarrow ? 10 : (isCompact ? 11 : 13), weight: .heavy))
                        .foregroundStyle(Color(red: 1.0, green: 0.20, blue: 0.18))
                    Text("\(dayNumberString(for: currentDate)) \(shortMonthString(for: currentDate))")
                        .font(.system(size: isNarrow ? 10 : (isCompact ? 11 : 13), weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    if !isNarrow {
                        Text(loc("calendar.events_count", calendarService.events.count))
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.55))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.08), in: Capsule())
                    }
                }

                Divider().background(Color.white.opacity(0.12))

                VStack(alignment: .leading, spacing: isCompact ? 4 : 6) {
                    ForEach(calendarService.events.prefix(eventCount)) { ev in
                        eventCompactRow(ev)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(isNarrow ? 9 : (isCompact ? 10 : 14))
        }
    }

    // MARK: - 5. Vue Hebdomadaire (7 Jours + Événements)

    private func weeklyCalendarView(w: CGFloat, h: CGFloat) -> some View {
        let isTall = h > w * 1.15
        let isCompact = h < 165
        let isNarrow = w < 190
        let eventCount = isTall ? (h > 380 ? 6 : 5) : (isCompact ? 2 : 3)
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

            VStack(alignment: .leading, spacing: isCompact ? 5 : 9) {
                if isTall {
                    Text(monthYearTitle(for: currentDate))
                        .font(.system(size: isNarrow ? 11 : 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(1)
                }

                HStack(spacing: isNarrow ? 1 : 3) {
                    ForEach(weekDays, id: \.offset) { item in
                        let isSelected = (selectedDayOffset == item.offset)
                        let circleDim: CGFloat = isNarrow ? 16 : (isCompact ? 18 : 22)
                        Button {
                            withAnimation(AppleDesignSystem.Springs.snappy) {
                                selectedDayOffset = item.offset
                            }
                        } label: {
                            VStack(spacing: 2) {
                                Text(item.letter)
                                    .font(.system(size: isNarrow ? 7.0 : (isCompact ? 7.5 : 8.5), weight: .bold))
                                    .foregroundStyle(isSelected ? .white : .white.opacity(0.50))
                                Text(item.num)
                                    .font(.system(size: isNarrow ? 8.5 : (isCompact ? 9.5 : 11), weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .frame(width: circleDim, height: circleDim)
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
                    ForEach(calendarService.events.prefix(eventCount)) { ev in
                        eventCompactRow(ev)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(isNarrow ? 8 : (isCompact ? 10 : 14))
        }
    }

    // MARK: - 6. Présentation Agenda Chronologique

    private func agendaTimelineView(w: CGFloat, h: CGFloat) -> some View {
        let isTall = h > w * 1.15
        let isCompact = h < 165
        let isNarrow = w < 190
        let eventCount = isTall ? (h > 380 ? 7 : 5) : (isCompact ? 2 : 3)

        return ZStack {
            Color(red: 0.06, green: 0.08, blue: 0.12)

            VStack(alignment: .leading, spacing: isCompact ? 5 : 8) {
                HStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(red: 1.0, green: 0.18, blue: 0.16))
                            .frame(width: 6, height: 6)
                        Text(isNarrow ? loc("calendar.agenda_short") : loc("calendar.agenda_full"))
                            .font(.system(size: isNarrow ? 8.5 : (isCompact ? 9 : 10), weight: .heavy))
                            .tracking(0.6)
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 2)
                    Text("\(shortWeekdayString(for: currentDate)) \(dayNumberString(for: currentDate))")
                        .font(.system(size: isNarrow ? 9 : (isCompact ? 9.5 : 11), weight: .bold))
                        .foregroundStyle(Color(red: 1.0, green: 0.25, blue: 0.22))
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Text(Self.timeFmt.string(from: currentDate))
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.red)
                    Circle().fill(Color.red).frame(width: 5, height: 5)
                    Rectangle().fill(Color.red.opacity(0.65)).frame(height: 1)
                }

                VStack(alignment: .leading, spacing: isCompact ? 4 : 6) {
                    ForEach(calendarService.events.prefix(eventCount)) { ev in
                        eventCompactRow(ev)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(isNarrow ? 9 : (isCompact ? 10 : 14))
        }
    }

    // MARK: - Ligne d'Événement Réutilisable

    private func eventCompactRow(_ ev: LaunchpadCalendarEvent) -> some View {
        return HStack(spacing: 7) {
            Capsule()
                .fill(ev.color)
                .frame(width: 3, height: 24)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(ev.title)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if ev.isOngoing(at: currentDate) {
                        Text(loc("calendar.in_progress"))
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
        f.dateFormat = "EEE"
        return f
    }()

    private static let monthFmt: DateFormatter = {
        let f = DateFormatter()
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

    private static let frLocale = Locale(identifier: "fr_FR")
    private static let enLocale = Locale(identifier: "en_US")

    private var activeAppLocale: Locale {
        Locale(identifier: LocalizationManager.activeLanguageCode)
    }

    private var weekdaySymbolsMonFirst: [String] {
        var cal = Calendar.current
        cal.locale = activeAppLocale
        let syms = cal.veryShortStandaloneWeekdaySymbols
        guard syms.count == 7 else { return ["M", "T", "W", "T", "F", "S", "S"] }
        return (Array(syms[1...6]) + [syms[0]]).map { $0.uppercased() }
    }

    private func shortWeekdayString(for date: Date) -> String {
        let loc = activeAppLocale
        if Self.weekdayFmt.locale != loc { Self.weekdayFmt.locale = loc }
        return Self.weekdayFmt.string(from: date).replacingOccurrences(of: ".", with: "").capitalized
    }

    private func shortMonthString(for date: Date) -> String {
        let loc = activeAppLocale
        if Self.monthFmt.locale != loc { Self.monthFmt.locale = loc }
        return Self.monthFmt.string(from: date).replacingOccurrences(of: ".", with: "").capitalized
    }

    private func dayNumberString(for date: Date) -> String {
        "\(Calendar.current.component(.day, from: date))"
    }

    private func monthYearTitle(for date: Date) -> String {
        let loc = activeAppLocale
        if Self.monthYearFmt.locale != loc { Self.monthYearFmt.locale = loc }
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
