// SPDX-License-Identifier: MIT
import AppKit
import NotchCore
import NotchFeatures
import NotchUsage
import Observation
import SwiftUI

/// Home: NotchDeck's dashboard, the tab the notch opens on. Claude Code, Pomodoro, today's
/// calendar, and the Mac's battery and energy as tiles, with the weather, a light/dark switch, and
/// Switch User along the bottom. A tile opens a peek with more. Nothing here runs while Home is off
/// screen, except Pomodoro's one deadline.
@MainActor
@Observable
public final class HomeFeature: NotchFeature {
    /// The detail a tile opens, in place of the tiles.
    public enum Peek: String, Sendable {
        case claude, focus, calendar, system, weather, user, viorim
    }

    public let id = FeatureID.home
    public var phase: FeaturePhase = .stopped {
        didSet { if phase != oldValue { update() } }
    }
    public var peek: Peek?

    public let pomodoro: Pomodoro
    public let weather: WeatherModel
    public let appearance = AppearanceSwitch()
    public let agenda: Agenda
    public let focus = FocusShortcuts()
    public let monitor: SystemMonitor
    public let agents: AgentsFeature
    public let webApps: WebApps

    /// Per-feature setting: the agent projects that get a page each in the Claude peek, by folder
    /// name. Sessions in any other folder share an "Other" page.
    public var agentProjects: [String] {
        didSet { defaults.set(agentProjects, forKey: Key.agentProjects) }
    }
    public static let defaultAgentProjects = [
        "holdings-agent", "ipo-agent", "industry-agent", "investor-agent", "viorim-os",
    ]

    /// Per-feature setting: the notch always opens on Home, not the tab used last.
    public var opensOnHome: Bool {
        didSet { defaults.set(opensOnHome, forKey: Key.opensOnHome) }
    }
    /// Per-feature setting: a ring for Claude's progress beside what's playing in the closed notch.
    public var showsClaudeInClosedNotch: Bool {
        didSet { defaults.set(showsClaudeInClosedNotch, forKey: Key.showsClaude) }
    }
    /// Opens another tab, such as Agents from the Claude peek.
    @ObservationIgnored public var openTab: ((FeatureID) -> Void)?
    /// Opens Home's page in Settings.
    @ObservationIgnored public var openSettings: (() -> Void)?
    @ObservationIgnored private let defaults: UserDefaults

    public init(
        eventStore: EventStore, agents: AgentsFeature, monitor: SystemMonitor, defaults: UserDefaults = .standard
    ) {
        self.agents = agents
        self.monitor = monitor
        self.defaults = defaults
        pomodoro = Pomodoro(defaults: defaults)
        weather = WeatherModel(defaults: defaults)
        agenda = Agenda(eventStore: eventStore)
        webApps = WebApps(defaults: defaults)
        agentProjects = defaults.stringArray(forKey: Key.agentProjects) ?? Self.defaultAgentProjects
        opensOnHome = defaults.object(forKey: Key.opensOnHome) as? Bool ?? true
        showsClaudeInClosedNotch = defaults.object(forKey: Key.showsClaude) as? Bool ?? true
    }

    public var view: some View { HomeView(home: self) }

    public func show(_ peek: Peek) {
        self.peek = peek
        switch peek {
        case .focus: focus.refresh()
        case .weather: weather.refreshIfStale()
        default: break
        }
    }

    /// The session the Claude tile shows: one that needs you, else one at work, else the latest.
    public static func featured(_ sessions: [AgentSession]) -> AgentSession? {
        sessions.first { $0.state == .waiting }
            ?? sessions.filter { $0.state == .working || $0.state == .compacting }.max { $0.updated < $1.updated }
            ?? sessions.max { $0.updated < $1.updated }
    }

    private func update() {
        if phase == .foreground {
            monitor.start(for: "home")
            agenda.start()
            appearance.startObserving()
            weather.refreshIfStale()
        } else {
            monitor.stop(for: "home")
            agenda.stop()
            appearance.stopObserving()
            peek = nil
        }
    }

    private enum Key {
        static let opensOnHome = "home.opensOnHome"
        static let showsClaude = "home.showsClaudeInClosedNotch"
        static let agentProjects = "home.agentProjects"
    }
}

/// System: the battery's health and charge, the apps using the most energy, and accessory batteries,
/// in a tab of their own. It samples only while it's on screen.
@MainActor
@Observable
public final class SystemFeature: NotchFeature {
    public let id = FeatureID.system
    public var phase: FeaturePhase = .stopped {
        didSet {
            guard phase != oldValue else { return }
            if phase == .foreground { monitor.start(for: "system") } else { monitor.stop(for: "system") }
        }
    }
    public let monitor: SystemMonitor

    public init(monitor: SystemMonitor) {
        self.monitor = monitor
    }

    public var view: some View { SystemView(monitor: monitor) }
}
