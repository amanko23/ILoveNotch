// SPDX-License-Identifier: MIT
import AppKit
import NotchCore
import Observation
import UserNotifications

/// How long each part of a Pomodoro cycle runs.
public struct PomodoroPlan: Equatable, Sendable {
    public var focusMinutes = 25
    public var shortBreakMinutes = 5
    public var longBreakMinutes = 15
    /// Focus sessions before a long break.
    public var rounds = 4

    public init() {}
}

/// Pomodoro: focus, a short break, and after every few rounds a long one. Like the Timer tab's
/// countdown it's one wall-clock deadline, never a per-second tick, so it keeps time while the Mac
/// sleeps and costs nothing while the notch is closed.
@MainActor
@Observable
public final class Pomodoro {
    public enum Phase: String, Sendable {
        case focus, shortBreak, longBreak

        public var title: String {
            switch self {
            case .focus: "Focus"
            case .shortBreak: "Short break"
            case .longBreak: "Long break"
            }
        }

        public var symbol: String {
            switch self {
            case .focus: "timer"
            case .shortBreak, .longBreak: "cup.and.saucer.fill"
            }
        }
    }

    public private(set) var phase = Phase.focus
    /// Focus sessions finished since the last long break.
    public private(set) var finishedRounds = 0
    /// Set while running.
    public private(set) var endsAt: Date?
    /// Time left while paused or not started.
    public private(set) var remaining: TimeInterval
    /// A cycle is under way: running, paused, or between sessions.
    public private(set) var isActive = false

    public var plan: PomodoroPlan {
        didSet {
            save()
            if endsAt == nil, !isActive || remaining > duration(of: phase) { remaining = duration(of: phase) }
        }
    }
    /// Breaks start by themselves when a focus session ends.
    public var startsBreaksAutomatically: Bool {
        didSet { defaults.set(startsBreaksAutomatically, forKey: Key.autoBreaks) }
    }
    /// The next focus session starts by itself when a break ends.
    public var startsFocusAutomatically: Bool {
        didSet { defaults.set(startsFocusAutomatically, forKey: Key.autoFocus) }
    }
    /// A macOS notification at every switch, besides the chime and the notch.
    public var notifies: Bool {
        didSet { defaults.set(notifies, forKey: Key.notifies) }
    }
    /// Raised when a session ends.
    @ObservationIgnored public var onActivity: ((Activity) -> Void)?
    @ObservationIgnored private var alarm: Task<Void, Never>?
    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var plan = PomodoroPlan()
        if let stored = defaults.array(forKey: Key.plan) as? [Int], stored.count == 4, stored.allSatisfy({ $0 > 0 }) {
            (plan.focusMinutes, plan.shortBreakMinutes, plan.longBreakMinutes, plan.rounds) =
                (stored[0], stored[1], stored[2], stored[3])
        }
        self.plan = plan
        remaining = TimeInterval(plan.focusMinutes * 60)
        startsBreaksAutomatically = defaults.object(forKey: Key.autoBreaks) as? Bool ?? true
        startsFocusAutomatically = defaults.bool(forKey: Key.autoFocus)
        notifies = defaults.object(forKey: Key.notifies) as? Bool ?? true
    }

    public var isRunning: Bool { endsAt != nil }

    public func remaining(at date: Date) -> TimeInterval {
        endsAt.map { max(0, $0.timeIntervalSince(date)) } ?? remaining
    }

    /// How far through the current session it is, 0...1.
    public func progress(at date: Date) -> Double {
        let total = duration(of: phase)
        return total > 0 ? min(max(1 - remaining(at: date) / total, 0), 1) : 0
    }

    public func duration(of phase: Phase) -> TimeInterval {
        let minutes =
            switch phase {
            case .focus: plan.focusMinutes
            case .shortBreak: plan.shortBreakMinutes
            case .longBreak: plan.longBreakMinutes
            }
        return TimeInterval(minutes * 60)
    }

    // MARK: Controls

    public func start(now: Date = .now) {
        guard endsAt == nil else { return }
        if notifies, !isActive { Self.askToNotify() }
        isActive = true
        endsAt = now.addingTimeInterval(remaining)
        scheduleAlarm()
    }

    public func pause(now: Date = .now) {
        guard let endsAt else { return }
        remaining = max(0, endsAt.timeIntervalSince(now))
        self.endsAt = nil
        alarm?.cancel()
    }

    public func toggle(now: Date = .now) {
        if isRunning { pause(now: now) } else { start(now: now) }
    }

    /// Ends this session now and moves on, without the chime.
    public func skip(now: Date = .now) {
        advance(now: now, finished: false)
    }

    /// Back to the start of a fresh cycle.
    public func reset() {
        alarm?.cancel()
        alarm = nil
        endsAt = nil
        isActive = false
        phase = .focus
        finishedRounds = 0
        remaining = duration(of: .focus)
    }

    /// What the closed notch shows while a cycle runs: the time left, counting down, or that it's
    /// paused. Nil when no cycle is under way.
    public var ongoingActivity: Activity? {
        guard isActive else { return nil }
        if let endsAt {
            return Activity(
                feature: .home, symbol: phase.symbol, title: phase.title, duration: .zero, countdown: endsAt)
        }
        return Activity(feature: .home, symbol: "pause.fill", title: "\(phase.title) paused", duration: .zero)
    }

    // MARK: Switching sessions

    private func scheduleAlarm() {
        alarm?.cancel()
        guard let endsAt else { return }
        let delay = max(0, endsAt.timeIntervalSinceNow)
        alarm = Task { [weak self] in
            // The continuous clock counts through sleep: a session that ends while the Mac sleeps
            // ends on wake.
            do { try await Task.sleep(for: .seconds(delay), tolerance: .milliseconds(250)) } catch { return }
            self?.advance(now: .now, finished: true)
        }
    }

    func advance(now: Date, finished: Bool) {
        alarm?.cancel()
        alarm = nil
        let ended = phase
        switch phase {
        case .focus:
            finishedRounds += 1
            phase = finishedRounds >= plan.rounds ? .longBreak : .shortBreak
        case .shortBreak:
            phase = .focus
        case .longBreak:
            finishedRounds = 0
            phase = .focus
        }
        remaining = duration(of: phase)
        endsAt = nil
        isActive = true
        if finished { announce(ended: ended) }
        let continues = phase == .focus ? startsFocusAutomatically : startsBreaksAutomatically
        if continues { start(now: now) }
    }

    private func announce(ended: Phase) {
        NSSound(named: ended == .focus ? "Glass" : "Hero")?.play()
        let next = Int(duration(of: phase) / 60)
        let (title, body): (String, String) =
            switch phase {
            case .focus: ("Break's over", "Time for focus session \(finishedRounds + 1) of \(plan.rounds).")
            case .shortBreak: ("Focus session done", "Take a \(next)-minute break.")
            case .longBreak: ("\(plan.rounds) sessions done", "Take a \(next)-minute break. You've earned it.")
            }
        onActivity?(Activity(feature: .home, symbol: phase.symbol, title: title, duration: .seconds(4)))
        if notifies { Self.notify(title: title, body: body) }
    }

    // MARK: Notifications

    private static func askToNotify() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private static func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: "pomodoro", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    private func save() {
        defaults.set(
            [plan.focusMinutes, plan.shortBreakMinutes, plan.longBreakMinutes, plan.rounds], forKey: Key.plan)
    }

    private enum Key {
        static let plan = "pomodoro.plan"
        static let autoBreaks = "pomodoro.startsBreaksAutomatically"
        static let autoFocus = "pomodoro.startsFocusAutomatically"
        static let notifies = "pomodoro.notifies"
    }
}
