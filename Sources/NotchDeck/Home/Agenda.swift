// SPDX-License-Identifier: MIT
import AppKit
import EventKit
import NotchFeatures
import Observation

/// One upcoming event, for Home's Today tile and calendar peek.
public struct AgendaEvent: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var color: RGB?

    public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool, color: RGB? = nil) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.color = color
    }

    /// "10:30", "All day", or a later day's name: "Tue".
    public func when(now: Date = .now) -> String {
        let calendar = Calendar.current
        if !calendar.isDate(start, inSameDayAs: now), start > now {
            return start.formatted(.dateTime.weekday(.abbreviated))
        }
        return isAllDay ? "All day" : start.formatted(date: .omitted, time: .shortened)
    }
}

/// The next few events, from the Calendar access ILoveNotch's Calendar tab already asks for. It
/// reads the calendar only while Home is on screen, and again when the calendar changes.
@MainActor
@Observable
public final class Agenda {
    public enum Access: Equatable, Sendable { case notDetermined, denied, granted }

    public private(set) var access: Access
    /// The next events over the coming week, soonest first: what's on now, then what's next.
    public private(set) var upcoming: [AgendaEvent] = []
    /// Days of this month that have an event, for the month grid's dots.
    public private(set) var busyDays: Set<Int> = []
    @ObservationIgnored private let eventStore: EventStore
    @ObservationIgnored private var changes: NSObjectProtocol?

    public init(eventStore: EventStore) {
        self.eventStore = eventStore
        access = Self.currentAccess()
    }

    public func start() {
        access = Self.currentAccess()
        guard access == .granted else { return }
        if changes == nil {
            changes = NotificationCenter.default.addObserver(
                forName: .EKEventStoreChanged, object: eventStore.store, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.reload() }
            }
        }
        reload()
    }

    public func stop() {
        if let changes { NotificationCenter.default.removeObserver(changes) }
        changes = nil
        upcoming = []
        busyDays = []
    }

    public func requestAccess() {
        eventStore.store.requestFullAccessToEvents { [weak self] _, _ in
            guard let self else { return }
            Task { @MainActor in self.start() }
        }
    }

    public func openPrivacySettings() {
        NSWorkspace.shared.open(.privacySettings("Privacy_Calendars"))
    }

    public func openCalendarApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func reload(now: Date = .now) {
        guard access == .granted else { return }
        let calendar = Calendar.current
        let store = eventStore.store
        let today = calendar.startOfDay(for: now)
        guard let weekOut = calendar.date(byAdding: .day, value: 7, to: today),
            let month = calendar.dateInterval(of: .month, for: now)
        else { return }
        let week = store.events(matching: store.predicateForEvents(withStart: now, end: weekOut, calendars: nil))
        upcoming = Self.upcoming(week.map(Self.event), now: now)
        let monthEvents = store.events(
            matching: store.predicateForEvents(withStart: month.start, end: month.end, calendars: nil))
        busyDays = Set(monthEvents.map { calendar.component(.day, from: max($0.startDate, month.start)) })
    }

    /// What's still to come, day by day: each day's all-day events first, then by start time. At
    /// most `limit`.
    nonisolated static func upcoming(_ events: [AgendaEvent], now: Date, limit: Int = 6) -> [AgendaEvent] {
        let calendar = Calendar.current
        func key(_ event: AgendaEvent) -> (Date, Int, Date, String) {
            (calendar.startOfDay(for: max(event.start, now)), event.isAllDay ? 0 : 1, event.start, event.title)
        }
        return Array(events.filter { $0.end > now }.sorted { key($0) < key($1) }.prefix(limit))
    }

    private static func event(_ event: EKEvent) -> AgendaEvent {
        AgendaEvent(
            id: event.eventIdentifier ?? UUID().uuidString, title: event.title ?? "Untitled", start: event.startDate,
            end: event.endDate, isAllDay: event.isAllDay, color: rgb(event.calendar?.cgColor))
    }

    private static func rgb(_ color: CGColor?) -> RGB? {
        guard let color, let srgb = NSColor(cgColor: color)?.usingColorSpace(.sRGB) else { return nil }
        return RGB(red: srgb.redComponent, green: srgb.greenComponent, blue: srgb.blueComponent)
    }

    private static func currentAccess() -> Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }
}
