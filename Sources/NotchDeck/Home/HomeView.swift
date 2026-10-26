// SPDX-License-Identifier: MIT
import AppKit
import NotchFeatures
import NotchUsage
import SwiftUI

/// Home's tiles, or the peek one of them opened. At the default size the notch gives it about
/// 396 × 192 pt; every tile keeps to two lines of detail so nothing clips there.
struct HomeView: View {
    let home: HomeFeature
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let peek = home.peek {
                PeekView(home: home, peek: peek)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else {
                dashboard.transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.86), value: home.peek)
    }

    private var dashboard: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                ClaudeTile(home: home)
                FocusTile(home: home)
            }
            .frame(maxHeight: .infinity)
            HStack(spacing: 6) {
                TodayTile(home: home)
                SystemTile(home: home)
            }
            .frame(maxHeight: .infinity)
            HomeFooter(home: home)
        }
    }
}

// MARK: Tiles

/// Claude Code: the session that needs you, or the one at work, with its progress.
private struct ClaudeTile: View {
    let home: HomeFeature

    var body: some View {
        let agents = home.agents
        let busy = agents.active.count
        Tile(
            title: "Claude Code", symbol: "terminal.fill", tint: Deck.claude, badge: busy > 1 ? "\(busy)" : nil,
            action: { home.show(.claude) }
        ) {
            if agents.phase == .stopped {
                Detail("Turn on Agents in Settings to follow your sessions.")
            } else if !agents.connected.contains(.claude) {
                Detail("Connect Claude Code to follow its sessions here.")
                if agents.available.contains(.claude) {
                    PillButton("Connect") { agents.connect(.claude) }
                }
            } else if let session = HomeFeature.featured(agents.sessions) {
                let waiting = session.state == .waiting
                Text(Deck.headline(session))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(waiting ? Color.orange : .white)
                    .lineLimit(1)
                if let progress = session.progress, session.state != .done {
                    AgentProgressBar(progress: progress, tint: waiting ? .orange : Deck.claude)
                }
                TimelineView(.everyMinute) { context in
                    Detail(Deck.detail(session, now: context.date))
                }
            } else {
                Detail("No sessions right now. Start Claude Code in a terminal.")
            }
        }
    }
}

/// Pomodoro: the time left, the round, and a button to start or pause.
private struct FocusTile: View {
    let home: HomeFeature

    var body: some View {
        let pomodoro = home.pomodoro
        Tile(title: "Focus", symbol: "timer", tint: Deck.focus, action: { home.show(.focus) }) {
            HStack(alignment: .firstTextBaseline) {
                PomodoroClock(pomodoro: pomodoro)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                Spacer(minLength: 4)
                RoundDots(pomodoro: pomodoro)
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Detail(Deck.phaseLine(pomodoro))
                Spacer(minLength: 0)
                PillButton(pomodoro.isRunning ? "Pause" : pomodoro.isActive ? "Resume" : "Start") {
                    pomodoro.toggle()
                }
            }
        }
    }
}

/// Today: the date and what's next on the calendar.
private struct TodayTile: View {
    let home: HomeFeature

    var body: some View {
        let agenda = home.agenda
        let today = Date.now.formatted(.dateTime.weekday(.abbreviated).day())
        Tile(title: "Today · \(today)", symbol: "calendar", tint: Deck.calendar, action: { home.show(.calendar) }) {
            switch agenda.access {
            case .granted:
                let next = agenda.upcoming.prefix(2)
                if next.isEmpty {
                    Detail("Nothing else this week.")
                } else {
                    ForEach(Array(next)) { event in EventRow(event: event) }
                }
            case .notDetermined:
                Detail("See what's next on your calendar.")
                PillButton("Continue") { agenda.requestAccess() }
            case .denied:
                Detail("Calendar access is off.")
                PillButton("Open Settings") { agenda.openPrivacySettings() }
            }
        }
    }
}

/// System: the charge, and the app using the most energy.
private struct SystemTile: View {
    let home: HomeFeature

    var body: some View {
        let monitor = home.monitor
        let battery = monitor.battery
        Tile(
            title: battery.map { "System · \($0.percent)%" } ?? "System",
            symbol: battery?.symbol ?? "cpu", tint: Deck.system, action: { home.show(.system) }
        ) {
            let top = monitor.energy.top
            if let first = top.first {
                Text("Top energy: \(first.name) \(first.wattsText)")
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                if top.count > 1 {
                    Detail(top.dropFirst().prefix(2).map { "\($0.name) \($0.wattsText)" }.joined(separator: " · "))
                }
            } else {
                Detail(monitor.energy.isMeasuring ? "Measuring energy use…" : "Nothing is using much energy.")
                if let battery { Detail(battery.powerText) }
            }
        }
    }
}

// MARK: Footer

/// The weather, the light/dark switch, and Switch User, along the bottom.
private struct HomeFooter: View {
    let home: HomeFeature

    var body: some View {
        HStack(spacing: 0) {
            weather
            Spacer(minLength: 4)
            appearance
            Spacer(minLength: 4)
            FooterButton(symbol: "person.2.fill", title: "Switch User", tint: .white) { home.show(.user) }
                .help("Lock and switch to another user")
        }
        .frame(height: 22)
    }

    @ViewBuilder private var weather: some View {
        let model = home.weather
        if let forecast = model.forecast {
            FooterButton(
                symbol: forecast.symbol,
                title: "\(Forecast.degrees(forecast.temperature)) \(forecast.condition.text)", tint: Deck.weather
            ) { home.show(.weather) }
        } else {
            FooterButton(
                symbol: model.status == .needsLocation ? "location.slash" : "cloud.sun.fill",
                title: model.status == .loading || model.status == .locating ? "Weather…" : "Weather",
                tint: Deck.weather
            ) { home.show(.weather) }
        }
    }

    @ViewBuilder private var appearance: some View {
        let appearance = home.appearance
        if appearance.failure != nil {
            FooterButton(symbol: "exclamationmark.triangle.fill", title: "Allow", tint: .orange) {
                appearance.openAutomationSettings()
            }
            .help(appearance.failure ?? "")
        } else {
            FooterButton(
                symbol: appearance.isDark ? "moon.fill" : "sun.max.fill", title: appearance.isDark ? "Dark" : "Light",
                tint: appearance.isDark ? Deck.focus : Deck.weather
            ) { appearance.toggle() }
            .help(appearance.isDark ? "Switch your Mac to light appearance" : "Switch your Mac to dark appearance")
            .disabled(appearance.isSwitching)
        }
    }
}

// MARK: Building blocks

/// NotchDeck's tints and the words its tiles use.
enum Deck {
    static let claude = Color(red: 0.85, green: 0.47, blue: 0.34)
    static let focus = Color(red: 0.79, green: 0.64, blue: 1)
    static let calendar = Color(red: 0.39, green: 0.66, blue: 1)
    static let system = Color(red: 1, green: 0.84, blue: 0.04)
    static let weather = Color(red: 1, green: 0.8, blue: 0.3)

    /// "Working · notchdeck".
    static func headline(_ session: AgentSession) -> String { "\(stateWord(session)) · \(session.project)" }

    /// "Needs you", "Working", "Compacting", "Ready", or "Done".
    static func stateWord(_ session: AgentSession) -> String {
        switch session.state {
        case .waiting: "Needs you"
        case .working: "Working"
        case .compacting: "Compacting"
        case .idle: "Ready"
        case .done: "Done"
        }
    }

    /// The second line: what it's waiting for, or the step it's on, how far through its to-dos it
    /// is, and how long it's been going.
    static func detail(_ session: AgentSession, now: Date) -> String {
        switch session.state {
        case .waiting: return session.detail ?? "Waiting for your approval"
        case .compacting: return "Making room in its context"
        case .idle: return "Waiting for your prompt"
        case .done:
            let when = session.updated.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
            return "Finished \(when)"
        case .working:
            var parts: [String] = []
            if let step = session.step { parts.append(step) }
            if session.todosTotal > 0 { parts.append("\(session.todosDone) of \(session.todosTotal)") }
            if let since = session.workingSince, let elapsed = elapsed(since: since, now: now) { parts.append(elapsed) }
            return parts.isEmpty ? "Working on it" : parts.joined(separator: " · ")
        }
    }

    /// "4m", "1h 5m", or nil under a minute.
    static func elapsed(since: Date, now: Date) -> String? {
        let minutes = Int(now.timeIntervalSince(since) / 60)
        guard minutes >= 1 else { return nil }
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    /// "25-minute focus", "Focus · 2 of 4", or "Paused · 2 of 4".
    @MainActor static func phaseLine(_ pomodoro: Pomodoro) -> String {
        guard pomodoro.isActive else { return "\(pomodoro.plan.focusMinutes)-minute focus" }
        let round = min(pomodoro.finishedRounds + (pomodoro.phase == .focus ? 1 : 0), pomodoro.plan.rounds)
        let state = pomodoro.isRunning ? pomodoro.phase.title : "Paused"
        return pomodoro.phase == .focus ? "\(state) · \(round) of \(pomodoro.plan.rounds)" : state
    }

    /// "4:05", or "1:02:03".
    static func clock(_ seconds: TimeInterval) -> String {
        let whole = Int(max(0, seconds).rounded(.up))
        let (hours, minutes, secs) = (whole / 3600, whole / 60 % 60, whole % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%d:%02d", minutes, secs)
    }
}

/// A dashboard tile: a titled, rounded card that opens its peek when clicked. Buttons inside it
/// still work on their own.
struct Tile<Content: View>: View {
    let title: String
    let symbol: String
    let tint: Color
    var badge: String?
    let action: () -> Void
    @ViewBuilder let content: Content
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 0)
                if let badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .bold))
                        .monospacedDigit()
                        .padding(.horizontal, 5)
                        .background(tint.opacity(0.3), in: Capsule())
                }
            }
            VStack(alignment: .leading, spacing: 3) { content }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(hovering ? 0.11 : 0.07))
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { hovering = $0 }
        .onTapGesture(perform: action)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityAction(named: "Show more", action)
    }
}

/// A line of secondary text.
struct Detail: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.6))
            .lineLimit(1)
    }
}

/// A small capsule button, as the notch's other tabs use.
struct PillButton: View {
    let title: String
    let tint: Color
    let foreground: Color
    let action: () -> Void

    init(
        _ title: String, tint: Color = .white.opacity(0.15), foreground: Color = .white,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.tint = tint
        self.foreground = foreground
        self.action = action
    }

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(tint, in: Capsule())
            .fixedSize()
    }
}

/// One of the footer's buttons: a symbol and a word.
private struct FooterButton: View {
    let symbol: String
    let title: String
    let tint: Color
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(tint)
                Text(title).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
            }
            .padding(.horizontal, 6)
            .frame(height: 22)
            .background(.white.opacity(hovering ? 0.09 : 0), in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// The time left in the Pomodoro session: counting down live while it runs.
struct PomodoroClock: View {
    let pomodoro: Pomodoro

    var body: some View {
        Group {
            if let endsAt = pomodoro.endsAt {
                let now = Date.now
                Text(timerInterval: now...max(endsAt, now), countsDown: true)
            } else {
                Text(Deck.clock(pomodoro.remaining))
            }
        }
        .monospacedDigit()
        .lineLimit(1)
    }
}

/// A dot per focus session in the cycle, filled once it's done.
private struct RoundDots: View {
    let pomodoro: Pomodoro

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<pomodoro.plan.rounds, id: \.self) { index in
                Circle()
                    .fill(index < pomodoro.finishedRounds ? Deck.focus : .white.opacity(0.22))
                    .frame(width: 5, height: 5)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(pomodoro.finishedRounds) of \(pomodoro.plan.rounds) focus sessions done")
    }
}

/// An event in a list: its calendar's color, when, and its title.
struct EventRow: View {
    let event: AgendaEvent

    var body: some View {
        HStack(spacing: 6) {
            Capsule().fill(event.color?.color ?? Deck.calendar).frame(width: 3, height: 12)
            Text(event.when())
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 44, alignment: .leading)
            Text(event.title).font(.system(size: 11)).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}
