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
        // Going deeper pushes from the right and Back reverses it, on the kit's smooth spring.
        Group {
            if let peek = home.peek {
                PeekView(home: home, peek: peek).transition(reduceMotion ? .opacity : Self.deeper)
            } else {
                dashboard.transition(reduceMotion ? .opacity : Self.back)
            }
        }
        .animation(reduceMotion ? Viorim.reduced : Viorim.smooth, value: home.peek)
    }

    private static let deeper = AnyTransition.move(edge: .trailing).combined(with: .opacity)
    private static let back = AnyTransition.move(edge: .leading).combined(with: .opacity)

    private var dashboard: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                ClaudeTile(home: home).layoutPriority(1)
                ViorimTile(home: home)
            }
            .frame(maxHeight: .infinity)
            HStack(spacing: 6) {
                FocusTile(home: home)
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
            title: "Claude Code", symbol: "terminal", tint: Deck.claude, badge: busy > 1 ? "\(busy)" : nil,
            hero: true, home: home, opens: .claude
        ) {
            if agents.phase == .stopped {
                Detail("Turn on Agents in Settings to follow your sessions.")
            } else if !agents.connected.contains(.claude) {
                Detail("Connect Claude Code to follow its sessions here.")
                if agents.available.contains(.claude) {
                    PillButton("Connect", prominent: true) { agents.connect(.claude) }
                }
            } else if let session = HomeFeature.featured(agents.sessions) {
                let waiting = session.state == .waiting
                HStack(spacing: 6) {
                    StatusChip(Deck.stateWord(session), tone: Deck.tone(session))
                    Text(session.title ?? session.project).font(Viorim.body).foregroundStyle(Viorim.ink).lineLimit(1)
                    Spacer(minLength: 0)
                    if session.state == .working || session.state == .compacting { WorkingDot() }
                }
                if let progress = session.progress, session.state != .done {
                    AgentProgressBar(progress: progress, tint: waiting ? Viorim.warning : Viorim.accent)
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
        Tile(title: "Focus", symbol: "timer", tint: Deck.focus, home: home, opens: .focus) {
            HStack(alignment: .firstTextBaseline) {
                PomodoroClock(pomodoro: pomodoro)
                    .font(Viorim.metric(26))
                    .foregroundStyle(Viorim.ink)
                Spacer(minLength: 4)
                RoundDots(pomodoro: pomodoro)
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Detail(Deck.phaseLine(pomodoro))
                Spacer(minLength: 0)
                PillButton(
                    pomodoro.isRunning ? "Pause" : pomodoro.isActive ? "Resume" : "Start",
                    prominent: !pomodoro.isRunning
                ) { pomodoro.toggle() }
            }
        }
    }
}

/// Today: the date and what's next on the calendar.
private struct TodayTile: View {
    let home: HomeFeature

    var body: some View {
        let agenda = home.agenda
        let today = IST.day(.now)
        Tile(title: "Today · \(today)", symbol: "calendar", tint: Deck.calendar, home: home, opens: .calendar) {
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
                PillButton("Continue", prominent: true) { agenda.requestAccess() }
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
            symbol: battery?.symbol ?? "cpu", tint: Deck.system, home: home, opens: .system
        ) {
            let top = monitor.energy.top
            if let first = top.first {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(first.name).font(Viorim.body).foregroundStyle(Viorim.ink).lineLimit(1)
                    Spacer(minLength: 2)
                    Text(first.wattsText).font(Viorim.metric(15)).monospacedDigit().foregroundStyle(Viorim.ink)
                }
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

/// Viorim OS: what's waiting for you there, and a way in.
private struct ViorimTile: View {
    let home: HomeFeature

    var body: some View {
        let viorim = home.viorimOS
        Tile(title: "Viorim OS", symbol: "square.grid.2x2", tint: Viorim.accent, home: home, opens: .viorim) {
            if let total = viorim.status?.total {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(total)").font(Viorim.metric(26)).monospacedDigit().foregroundStyle(Viorim.ink)
                    Text("waiting for you").font(Viorim.footnote).foregroundStyle(Viorim.ink2)
                }
                if let breakdown = viorim.status?.breakdown { Detail(breakdown) }
            } else {
                Detail(viorim.reachable == false ? "Not running at \(viorim.address)" : "RFQs, plans, quotes")
            }
            Spacer(minLength: 0)
            PillButton("Open", prominent: true) { viorim.open() }
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
            TimelineView(.everyMinute) { context in
                Text(IST.date(context.date) + " · " + IST.time(context.date) + " IST")
                    .font(Viorim.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Viorim.ink2)
            }
            Spacer(minLength: 4)
            appearance
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
            FooterButton(symbol: "exclamationmark.triangle", title: "Allow", tint: Viorim.warning) {
                appearance.openAutomationSettings()
            }
            .help(appearance.failure ?? "")
        } else {
            FooterButton(
                symbol: appearance.isDark ? "moon" : "sun.max", title: appearance.isDark ? "Dark" : "Light",
                tint: Viorim.ink2
            ) { appearance.toggle() }
            .help(appearance.isDark ? "Switch your Mac to light appearance" : "Switch your Mac to dark appearance")
            .disabled(appearance.isSwitching)
        }
    }
}

// MARK: Building blocks

/// The words Home's tiles use, and their tints: the Viorim kit's calm roles, one accent.
enum Deck {
    static let claude = Viorim.accent
    static let focus = Viorim.accent
    static let calendar = Viorim.accent
    static let system = Viorim.ink2
    static let weather = Viorim.ink2

    /// A session's state as a status chip's tone.
    static func tone(_ session: AgentSession) -> StatusChip.Tone {
        switch session.state {
        case .waiting: .warning
        case .working, .compacting: .info
        case .idle: .neutral
        case .done: .success
        }
    }

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
            // The chat's title is on the line above; the project, how far along, and how long here.
            var parts: [String] = session.title == nil ? [] : [session.project]
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
///
/// Drawn as the Viorim kit's raised surface on the notch's glass, with a hairline rim. The one hero
/// tile (Claude Code) carries the kit's steel light: a glow in its top-left corner and a lit edge.
struct Tile<Content: View>: View {
    let title: String
    let symbol: String
    let tint: Color
    var badge: String?
    var hero = false
    /// Home, and the peek this tile opens when clicked.
    let home: HomeFeature
    let opens: HomeFeature.Peek
    @ViewBuilder let content: Content
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Viorim.radiusTile, style: .continuous)
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(hero ? Viorim.accent : Viorim.ink3)
                Text(title.uppercased())
                    .font(Viorim.label())
                    .tracking(0.6)
                    .foregroundStyle(Viorim.ink2)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let badge {
                    Text(badge)
                        .font(Viorim.label(9))
                        .foregroundStyle(Viorim.ink)
                        .padding(.horizontal, 5)
                        .background(Viorim.highlight, in: Capsule())
                }
            }
            VStack(alignment: .leading, spacing: 4) { content }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            ZStack {
                shape.fill(Viorim.surfaceRaised.opacity(hovering ? 0.8 : 0.62))
                if hero {
                    RadialGradient(
                        colors: [Viorim.heroTint, .clear], center: .topLeading, startRadius: 0, endRadius: 170
                    )
                    .clipShape(shape)
                }
                shape.strokeBorder(hero ? Viorim.heroRim : Viorim.glassRim, lineWidth: 1)
            }
            .shadow(color: hero ? Viorim.glowSteel.opacity(0.5) : .clear, radius: 14)
        }
        .contentShape(shape)
        .onHover { hovering = $0 }
        .onTapGesture { home.show(opens) }
        .animation(.easeInOut(duration: 0.2), value: hovering)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityAction(named: "Show more") { home.show(opens) }
    }
}

/// A line of secondary text.
struct Detail: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Viorim.footnote)
            .foregroundStyle(Viorim.ink2)
            .lineLimit(1)
    }
}

/// A small capsule button. `prominent` is the Viorim kit's Frost capsule, kept for the one primary
/// action in view; the rest sit on the raised surface with a hairline.
struct PillButton: View {
    let title: String
    let tint: Color
    let foreground: Color
    let action: () -> Void

    init(_ title: String, prominent: Bool = false, action: @escaping () -> Void) {
        self.init(
            title, tint: prominent ? Viorim.action : Viorim.surfaceRaised,
            foreground: prominent ? Viorim.onAction : Viorim.ink, action: action)
    }

    init(_ title: String, tint: Color, foreground: Color, action: @escaping () -> Void) {
        self.title = title
        self.tint = tint
        self.foreground = foreground
        self.action = action
    }

    var body: some View {
        Button(title, action: action)
            .buttonStyle(PressStyle())
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(tint, in: Capsule())
            .overlay(Capsule().strokeBorder(Viorim.glassRim, lineWidth: 1))
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
            .foregroundStyle(Viorim.ink)
            .background(Viorim.surfaceRaised.opacity(hovering ? 0.6 : 0), in: Capsule())
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .onHover { hovering = $0 }
    }
}

/// The time left in the Pomodoro session: counting down live while it runs.
struct PomodoroClock: View {
    let pomodoro: Pomodoro
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let endsAt = pomodoro.endsAt {
                let now = Date.now
                Text(timerInterval: now...max(endsAt, now), countsDown: true)
            } else {
                // Changed digits roll (snappy); Reduce Motion changes them at once.
                Text(Deck.clock(pomodoro.remaining))
                    .contentTransition(reduceMotion ? .identity : .numericText(countsDown: true))
                    .animation(reduceMotion ? nil : Viorim.snappy, value: pomodoro.remaining)
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
                    .fill(index < pomodoro.finishedRounds ? Viorim.accent : Viorim.separator)
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
                .font(Viorim.footnote)
                .monospacedDigit()
                .foregroundStyle(Viorim.ink2)
                .frame(width: 44, alignment: .leading)
            Text(event.title).font(Viorim.footnote).foregroundStyle(Viorim.ink).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}
