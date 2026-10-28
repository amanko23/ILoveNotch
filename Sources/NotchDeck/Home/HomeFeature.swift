// SPDX-License-Identifier: MIT
import AppKit
import NotchCore
import NotchFeatures
import NotchUsage
import Observation
import SwiftUI

/// Home: NotchDeck's dashboard, the tab the notch opens on. Claude Code, Pomodoro, today's
/// calendar, and the agents' takeaways as tiles you can drag into any order, with the weather,
/// the battery, the date and time, and a light/dark switch along the bottom. A tile opens a peek
/// with more. Nothing here runs while Home is off screen, except Pomodoro's one deadline.
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
    /// The Apps tab, whose takeaways Home's tile shows too.
    public let apps: AppsFeature

    /// The dashboard's four tiles, in the order the user dragged them into.
    public enum TileKind: String, CaseIterable, Sendable {
        case claude, focus, calendar, takeaways
    }
    public var tileOrder: [TileKind] {
        didSet { defaults.set(tileOrder.map(\.rawValue), forKey: Key.tileOrder) }
    }

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
        apps = AppsFeature(web: webApps)
        tileOrder = Self.order(defaults.stringArray(forKey: Key.tileOrder))
        agentProjects = defaults.stringArray(forKey: Key.agentProjects) ?? Self.defaultAgentProjects
        opensOnHome = defaults.object(forKey: Key.opensOnHome) as? Bool ?? true
        showsClaudeInClosedNotch = defaults.object(forKey: Key.showsClaude) as? Bool ?? true
    }

    public var view: some View { HomeView(home: self) }

    /// A stored order, with unknown tiles dropped and missing ones appended.
    static func order(_ stored: [String]?) -> [TileKind] {
        var seen = Set<TileKind>()
        let kept = (stored ?? []).compactMap(TileKind.init).filter { seen.insert($0).inserted }
        return kept + TileKind.allCases.filter { !seen.contains($0) }
    }

    /// Moves `tile` to where `target` is.
    public func move(_ tile: TileKind, to target: TileKind) {
        guard tile != target, let from = tileOrder.firstIndex(of: tile),
            let to = tileOrder.firstIndex(of: target)
        else { return }
        var order = tileOrder
        order.remove(at: from)
        order.insert(tile, at: to)
        tileOrder = order
    }

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
            apps.refreshAll()
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
        static let tileOrder = "home.tileOrder"
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
