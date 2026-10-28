// SPDX-License-Identifier: MIT
import EventKit
import SwiftUI

// NotchDeck: a month grid in the Calendar tab, with a day's events beside it.

extension CalendarFeature {
    /// The days the grid shows: whole weeks covering the anchor's month, nil for padding.
    static func monthGrid(for anchor: Date, calendar: Calendar = .current) -> [Date?] {
        guard let month = calendar.dateInterval(of: .month, for: anchor),
            let days = calendar.range(of: .day, in: .month, for: anchor)
        else { return [] }
        let lead = (calendar.component(.weekday, from: month.start) - calendar.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: lead)
        for day in days {
            cells.append(calendar.date(byAdding: .day, value: day - 1, to: month.start))
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }

    /// Moves the grid a month back or forward.
    public func moveMonth(by months: Int) {
        guard let moved = Calendar.current.date(byAdding: .month, value: months, to: monthAnchor) else { return }
        monthAnchor = moved
        loadMonth()
    }

    /// The shown month's events that touch `day`, in agenda order.
    func events(on day: Date) -> [DayEvent] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return monthEvents.filter { $0.start < end && $0.end > start }.sorted(by: DayEvent.agendaOrder)
    }

    /// Loads the shown month's events, only while the grid is on screen.
    func loadMonth() {
        guard showsMonth, phase == .foreground, access == .granted,
            let month = Calendar.current.dateInterval(of: .month, for: monthAnchor)
        else {
            monthEvents = []
            return
        }
        let store = eventStoreForMonth
        let predicate = store.predicateForEvents(withStart: month.start, end: month.end, calendars: nil)
        monthEvents = store.events(matching: predicate)
            .map(DayEvent.init)
            .filter { showsAllDay || !$0.isAllDay }
    }
}

/// Switches the tab between today and the month.
struct MonthToggle: View {
    let calendar: CalendarFeature

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.5, dampingFraction: 1)) { calendar.showsMonth.toggle() }
        } label: {
            Text(calendar.showsMonth ? "Today" : "Month")
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(.white.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
        .help(calendar.showsMonth ? "Show today's agenda" : "Show the whole month")
    }
}

/// The month: a grid on the left, the picked day's events on the right.
struct MonthView: View {
    let calendar: CalendarFeature
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            grid.frame(width: 176)
            dayList.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var grid: some View {
        let system = Calendar.current
        let cells = CalendarFeature.monthGrid(for: calendar.monthAnchor)
        let busy = Set(calendar.monthEvents.map { system.startOfDay(for: $0.start) })
        let symbols = system.veryShortStandaloneWeekdaySymbols
        let initials = (0..<7).map { symbols[(system.firstWeekday - 1 + $0) % 7] }
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        return VStack(spacing: 3) {
            HStack {
                chevron("chevron.left", label: "Previous month") { calendar.moveMonth(by: -1) }
                Spacer(minLength: 0)
                Text(calendar.monthAnchor, format: .dateTime.month(.wide).year())
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                chevron("chevron.right", label: "Next month") { calendar.moveMonth(by: 1) }
            }
            LazyVGrid(columns: columns, spacing: 1) {
                ForEach(Array(initials.enumerated()), id: \.offset) { _, initial in
                    Text(initial).font(.system(size: 8.5, weight: .semibold)).foregroundStyle(.white.opacity(0.45))
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        cell(day, busy: busy.contains(system.startOfDay(for: day)))
                    } else {
                        Color.clear.frame(height: 18)
                    }
                }
            }
        }
    }

    private func cell(_ day: Date, busy: Bool) -> some View {
        let system = Calendar.current
        let today = system.isDateInToday(day)
        let picked = system.isDate(day, inSameDayAs: calendar.selectedDay)
        return Button {
            withAnimation(reduceMotion ? nil : .spring(duration: 0.33, bounce: 0.15)) {
                calendar.selectedDay = system.startOfDay(for: day)
            }
        } label: {
            VStack(spacing: 1) {
                Text("\(system.component(.day, from: day))")
                    .font(.system(size: 10, weight: today ? .bold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(today ? Color.black : .white)
                    .frame(width: 16, height: 14)
                    .background {
                        if today {
                            Circle().fill(Color.accentColor)
                        } else if picked {
                            Circle().fill(.white.opacity(0.18))
                        }
                    }
                Circle().fill(busy ? Color.accentColor : .clear).frame(width: 3, height: 3)
            }
            .frame(height: 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(day, format: .dateTime.weekday(.wide).day().month(.wide)))
        .accessibilityValue(busy ? "Has events" : "")
    }

    private var dayList: some View {
        let events = calendar.events(on: calendar.selectedDay)
        return VStack(alignment: .leading, spacing: 4) {
            Text(calendar.selectedDay, format: .dateTime.weekday(.wide).day().month(.abbreviated))
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 4)
            if events.isEmpty {
                Text("Nothing planned")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.horizontal, 4)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(events) { event in
                            EventRow(calendar: calendar, event: event) {}
                        }
                    }
                }
                .fadingEdges()
            }
        }
    }

    private func chevron(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 9, weight: .semibold)).frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.7))
        .accessibilityLabel(label)
    }
}
