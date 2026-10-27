// SPDX-License-Identifier: MIT
import AppKit
import NotchCore
import NotchFeatures
import NotchUsage
import SwiftUI

/// A tile's peek, in place of the tiles: a back button and title, then the detail. Everything
/// stays inside the notch, so moving the pointer to it never closes the notch.
struct PeekView: View {
    let home: HomeFeature
    let peek: HomeFeature.Peek

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    home.peek = nil
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 22)
                        .foregroundStyle(Viorim.ink)
                        .background(Viorim.surfaceRaised, in: Circle())
                        .overlay(Circle().strokeBorder(Viorim.glassRim, lineWidth: 1))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Back to Home")
                .accessibilityLabel("Back to Home")
                Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 0)
                if let tab = tab {
                    PillButton("Open \(tab.title)") { home.openTab?(tab) }
                }
            }
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var title: String {
        switch peek {
        case .claude:
            let count = home.agents.sessions.count
            return count == 1 ? "Claude Code · 1 session" : "Claude Code · \(count) sessions"
        case .focus: return "Focus"
        case .calendar: return Date.now.formatted(.dateTime.month(.wide).year())
        case .system: return "Battery & energy"
        case .weather: return home.weather.forecast?.place.map { "Weather · \($0)" } ?? "Weather"
        case .user: return "Switch User"
        }
    }

    /// The full tab this peek previews.
    private var tab: FeatureID? {
        switch peek {
        case .claude: .agents
        case .calendar: .calendar
        case .system: .system
        case .focus, .weather, .user: nil
        }
    }

    @ViewBuilder private var content: some View {
        switch peek {
        case .claude: ClaudePeek(agents: home.agents)
        case .focus: FocusPeek(pomodoro: home.pomodoro, focus: home.focus)
        case .calendar: CalendarPeek(agenda: home.agenda)
        case .system: SystemPeek(monitor: home.monitor)
        case .weather: WeatherPeek(weather: home.weather, openSettings: { home.openSettings?() })
        case .user: UserPeek()
        }
    }
}

// MARK: Claude Code

private struct ClaudePeek: View {
    let agents: AgentsFeature

    var body: some View {
        if agents.sessions.isEmpty {
            Detail("No sessions. Start Claude Code in a terminal and it shows up here.")
        } else {
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(agents.sessions) { session in row(session) }
                }
            }
            .fadingEdges()
        }
    }

    private func row(_ session: AgentSession) -> some View {
        let waiting = session.state == .waiting
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title ?? session.project).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                TimelineView(.everyMinute) { context in
                    Text("\(Deck.stateWord(session)) · \(Deck.detail(session, now: context.date))")
                }
                .font(.system(size: 11))
                .foregroundStyle(waiting ? Viorim.warning : Viorim.ink2)
                .lineLimit(1)
                if let progress = session.progress, session.state != .done {
                    AgentProgressBar(progress: progress, tint: waiting ? Viorim.warning : Viorim.accent)
                }
            }
            Spacer(minLength: 0)
            if session.app != nil {
                PillButton("Go", prominent: waiting) { agents.open(session) }
                    .help("Go to its terminal")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            waiting ? Viorim.warningSoft.opacity(0.8) : Viorim.surfaceRaised.opacity(0.55),
            in: RoundedRectangle(cornerRadius: Viorim.radiusWell)
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: Focus

private struct FocusPeek: View {
    let pomodoro: Pomodoro
    let focus: FocusShortcuts

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    PomodoroRing(pomodoro: pomodoro).frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        PomodoroClock(pomodoro: pomodoro).font(.system(size: 20, weight: .semibold, design: .rounded))
                        Detail(Deck.phaseLine(pomodoro))
                    }
                }
                HStack(spacing: 6) {
                    PillButton(
                        pomodoro.isRunning ? "Pause" : pomodoro.isActive ? "Resume" : "Start",
                        prominent: !pomodoro.isRunning
                    ) {
                        pomodoro.toggle()
                    }
                    PillButton("Skip") { pomodoro.skip() }.disabled(!pomodoro.isActive)
                    PillButton("Reset") { pomodoro.reset() }.disabled(!pomodoro.isActive)
                }
                let plan = pomodoro.plan
                Detail(
                    "\(plan.focusMinutes) min focus, \(plan.shortBreakMinutes) min breaks, "
                        + "\(plan.longBreakMinutes) after \(plan.rounds)")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                SectionLabel("Focus modes")
                if focus.names.isEmpty {
                    Text(
                        focus.hasLoaded
                            ? "Make a shortcut with Set Focus in the Shortcuts app and put Focus in its name."
                            : "Looking for your Focus shortcuts…"
                    )
                    .font(.system(size: 10.5))
                    .foregroundStyle(Viorim.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    if focus.hasLoaded { PillButton("Open Shortcuts") { focus.openShortcutsApp() } }
                } else {
                    ForEach(focus.names.prefix(4), id: \.self) { name in
                        PillButton(focus.running == name ? "\(name)…" : name) { focus.run(name) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The session's time as a ring that empties as it runs, redrawn each second while on screen.
private struct PomodoroRing: View {
    let pomodoro: Pomodoro

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let progress = pomodoro.progress(at: context.date)
            ZStack {
                Circle().stroke(Viorim.surfaceSunken, lineWidth: 4)
                Circle()
                    .trim(from: 0, to: 1 - progress)
                    .stroke(Viorim.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: pomodoro.phase.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Deck.focus)
            }
            .padding(3)
        }
        .accessibilityHidden(true)
    }
}

// MARK: Calendar

private struct CalendarPeek: View {
    let agenda: Agenda

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            MiniMonth(busyDays: agenda.busyDays).frame(width: 150)
            VStack(alignment: .leading, spacing: 4) {
                switch agenda.access {
                case .granted:
                    if agenda.upcoming.isEmpty {
                        Detail("Nothing on your calendar this week.")
                    } else {
                        ForEach(agenda.upcoming.prefix(5)) { event in EventRow(event: event) }
                    }
                case .notDetermined:
                    Detail("See your events here.")
                    PillButton("Continue", prominent: true) { agenda.requestAccess() }
                case .denied:
                    Detail("Calendar access is off.")
                    PillButton("Open Settings") { agenda.openPrivacySettings() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// This month as a grid, today circled and days with events dotted.
struct MiniMonth: View {
    let busyDays: Set<Int>
    var today = Date.now

    var body: some View {
        let calendar = Calendar.current
        let days = calendar.range(of: .day, in: .month, for: today) ?? 1..<31
        let first = calendar.dateInterval(of: .month, for: today)?.start ?? today
        let lead = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        let symbols = calendar.veryShortWeekdaySymbols
        let weekdays = (0..<7).map { symbols[($0 + calendar.firstWeekday - 1) % 7] }
        let day = calendar.component(.day, from: today)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 1), count: 7)
        LazyVGrid(columns: columns, spacing: 1) {
            ForEach(Array(weekdays.enumerated()), id: \.offset) { _, symbol in
                Text(symbol).font(Viorim.label(8.5)).foregroundStyle(Viorim.ink3)
            }
            ForEach(0..<lead, id: \.self) { _ in Color.clear.frame(height: 15) }
            ForEach(Array(days), id: \.self) { number in
                Text("\(number)")
                    .font(.system(size: 9.5, weight: number == day ? .bold : .regular))
                    .monospacedDigit()
                    .frame(width: 17, height: 15)
                    .background(number == day ? Viorim.action : .clear, in: Circle())
                    .overlay(alignment: .bottom) {
                        if busyDays.contains(number), number != day {
                            Circle().fill(Deck.calendar).frame(width: 3, height: 3).offset(y: 2)
                        }
                    }
                    .foregroundStyle(number == day ? Viorim.onAction : number < day ? Viorim.ink3 : Viorim.ink)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(today.formatted(date: .complete, time: .omitted))
    }
}

// MARK: System

private struct SystemPeek: View {
    let monitor: SystemMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            BatteryStats(battery: monitor.battery)
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    SectionLabel("Using the most energy")
                    EnergyList(energy: monitor.energy, limit: 3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    SectionLabel("Devices")
                    AccessoryList(accessories: monitor.accessories)
                }
                .frame(width: 130, alignment: .leading)
            }
        }
    }
}

// MARK: Weather

private struct WeatherPeek: View {
    let weather: WeatherModel
    let openSettings: () -> Void

    var body: some View {
        if let forecast = weather.forecast {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: forecast.symbol)
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 26))
                    Text(Forecast.degrees(forecast.temperature))
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(forecast.condition.text).font(.system(size: 12, weight: .medium))
                        Detail("Feels like \(Forecast.degrees(forecast.feelsLike))")
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(forecast.days, id: \.date) { day in
                            HStack(spacing: 6) {
                                Text(Forecast.dayName(day.date)).frame(width: 40, alignment: .leading)
                                Image(systemName: WeatherCondition(code: day.code).symbol())
                                    .symbolRenderingMode(.hierarchical)
                                    .frame(width: 16)
                                Text("\(Forecast.degrees(day.high)) / \(Forecast.degrees(day.low))").monospacedDigit()
                                if let rain = day.rainChance, rain >= 20 {
                                    Text("\(rain)%").foregroundStyle(Viorim.info)
                                }
                            }
                            .font(.system(size: 11))
                        }
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Detail(status(forecast))
                    Spacer(minLength: 0)
                    PillButton("Refresh") { weather.refresh() }
                }
                Link("Weather data by Open-Meteo.com", destination: URL(string: "https://open-meteo.com/")!)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Viorim.ink3)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                switch weather.status {
                case .needsLocation:
                    Detail("Location access is off. Allow it, or type a city in Settings.")
                    HStack(spacing: 6) {
                        PillButton("Open Location Settings") {
                            NSWorkspace.shared.open(.privacySettings("Privacy_LocationServices"))
                        }
                        PillButton("Type a City", action: openSettings)
                    }
                case .failed(let message):
                    Detail(message)
                    PillButton("Try Again") { weather.refresh() }
                default:
                    Detail("Getting the forecast…")
                }
            }
        }
    }

    private func status(_ forecast: Forecast) -> String {
        if case .failed(let message) = weather.status { return message }
        if weather.status == .loading || weather.status == .locating { return "Updating…" }
        return "Updated \(forecast.fetched.formatted(date: .omitted, time: .shortened))"
    }
}

// MARK: Switch User

private struct UserPeek: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Locks your Mac and opens the login window, where you can pick another user. Your apps keep running.")
                .font(.system(size: 11.5))
                .fixedSize(horizontal: false, vertical: true)
            PillButton("Lock & Switch User", prominent: true) { UserSwitcher.lockAndSwitch() }
            if !UserSwitcher.locksDirectly {
                Text(
                    "Without Accessibility access, this puts the display to sleep instead. That locks your Mac "
                        + "when it asks for your password right away."
                )
                .font(.system(size: 10.5))
                .foregroundStyle(Viorim.ink2)
                .fixedSize(horizontal: false, vertical: true)
                PillButton("Allow Accessibility") { UserSwitcher.openAccessibilitySettings() }
            }
            Spacer(minLength: 0)
            Detail("NotchDeck never sees or stores a password.")
        }
    }
}

// MARK: Shared with the System tab

/// A small uppercase label over a group.
struct SectionLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(Viorim.label())
            .tracking(0.6)
            .foregroundStyle(Viorim.ink2)
            .lineLimit(1)
    }
}

/// The battery's charge, health, and cycle count as three small boxes.
struct BatteryStats: View {
    let battery: BatteryReport?

    var body: some View {
        HStack(spacing: 6) {
            if let battery {
                Stat(value: "\(battery.percent)%", label: chargeLabel(battery))
                Stat(value: battery.health.map { "\($0)%" } ?? "—", label: "health")
                Stat(value: battery.cycleCount.map { "\($0)" } ?? "—", label: "cycles")
            } else {
                Stat(value: "—", label: "no battery")
            }
        }
    }

    private func chargeLabel(_ battery: BatteryReport) -> String {
        if battery.isCharging, let watts = battery.batteryWatts, watts > 0.5 {
            return String(format: "charging · %.0f W", watts)
        }
        if let left = battery.remainingText { return battery.isCharging ? "full in \(left)" : "\(left) left" }
        return battery.powerText.lowercased()
    }
}

/// One figure and what it is.
struct Stat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(Viorim.metric(17)).monospacedDigit().foregroundStyle(Viorim.ink).lineLimit(1)
            Text(label).font(.system(size: 9.5)).foregroundStyle(Viorim.ink2).lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Viorim.surfaceSunken.opacity(0.55), in: RoundedRectangle(cornerRadius: Viorim.radiusWell))
        .accessibilityElement(children: .combine)
    }
}

/// The apps using the most energy, each with a bar against the busiest; clicking one brings it
/// forward.
struct EnergyList: View {
    let energy: EnergySampler
    let limit: Int

    var body: some View {
        let top = Array(energy.top.prefix(limit))
        if top.isEmpty {
            Detail(energy.isMeasuring ? "Measuring…" : "Nothing is using much energy.")
        } else {
            let most = max(top.first?.watts ?? 1, 0.1)
            ForEach(top) { app in
                Button {
                    guard app.isApp else { return }
                    NSWorkspace.shared.openApplication(
                        at: URL(filePath: app.id), configuration: NSWorkspace.OpenConfiguration())
                } label: {
                    HStack(spacing: 6) {
                        AppIcon(path: app.isApp ? app.id : nil).frame(width: 14, height: 14)
                        Text(app.name).font(.system(size: 11)).lineLimit(1).frame(width: 74, alignment: .leading)
                        Capsule()
                            .fill(Viorim.surfaceSunken)
                            .frame(height: 4)
                            .overlay(alignment: .leading) {
                                GeometryReader { track in
                                    Capsule().fill(Viorim.accent).frame(width: track.size.width * app.watts / most)
                                }
                            }
                        Text(app.wattsText)
                            .font(.system(size: 10.5))
                            .monospacedDigit()
                            .foregroundStyle(Viorim.ink2)
                            .frame(width: 38, alignment: .trailing)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(app.isApp ? "Bring \(app.name) forward" : app.id)
                .accessibilityLabel("\(app.name), \(app.wattsText)")
            }
        }
    }
}

/// An app's icon from its bundle, or a generic one for a process outside any app.
struct AppIcon: View {
    let path: String?

    var body: some View {
        if let path {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().accessibilityHidden(true)
        } else {
            Image(systemName: "gearshape.fill").resizable().scaledToFit().opacity(0.6).accessibilityHidden(true)
        }
    }
}

/// Bluetooth accessories that report a battery.
struct AccessoryList: View {
    let accessories: [AccessoryBattery]

    var body: some View {
        if accessories.isEmpty {
            Detail("None that share a battery level.")
        } else {
            ForEach(accessories.prefix(4)) { accessory in
                HStack(spacing: 6) {
                    Image(systemName: accessory.symbol).font(.system(size: 10)).frame(width: 14)
                    Text(accessory.name).font(.system(size: 11)).lineLimit(1)
                    Spacer(minLength: 2)
                    Text("\(accessory.percent)%")
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(accessory.percent <= 20 ? Viorim.warning : Viorim.ink2)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
