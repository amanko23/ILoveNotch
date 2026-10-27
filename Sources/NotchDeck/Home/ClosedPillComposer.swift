// SPDX-License-Identifier: MIT
import Foundation
import NotchCore
import NotchUsage

/// What Claude Code is up to, boiled down for the closed notch.
public struct ClaudeSummary: Hashable, Sendable {
    /// The busiest session's project, or "2 working".
    public var title: String
    /// Its to-do progress, 0...1, when it has a list.
    public var progress: Double?
    /// What VoiceOver reads.
    public var label: String

    public init(title: String, progress: Double?, label: String) {
        self.title = title
        self.progress = progress
        self.label = label
    }

    /// Sessions that are working or compacting: a waiting one has the closed notch to itself
    /// already (the Agents tab's "needs you"), and an idle one has nothing to show.
    public init?(_ sessions: [AgentSession]) {
        let busy = sessions.filter { $0.state == .working || $0.state == .compacting }
        guard let first = busy.max(by: { ($0.progress ?? -1, $0.updated) < ($1.progress ?? -1, $1.updated) })
        else { return nil }
        title = busy.count == 1 ? first.title ?? first.project : "\(busy.count) working"
        progress = first.progress
        var label = "Claude is working on \(first.title ?? first.project)"
        if first.todosTotal > 0 { label += ", \(first.todosDone) of \(first.todosTotal) done" }
        self.label = label
    }
}

/// Merges what's playing, Pomodoro, and Claude's progress into the one pill the closed notch shows
/// beside the camera: Pomodoro's countdown or what's playing, with a ring for Claude's progress
/// after it, or Claude alone when nothing else is on. A meeting about to start, or an agent waiting
/// for approval, still shows over it (`PanelCoordinator`).
@MainActor
public final class ClosedPillComposer {
    /// What's playing, as the Media tab raises it.
    public var media: Activity? {
        didSet { compose() }
    }
    /// The Pomodoro countdown while a cycle runs.
    public var pomodoro: Activity? {
        didSet { compose() }
    }
    public var claude: ClaudeSummary? {
        didSet { compose() }
    }
    /// Called with the pill whenever it changes, nil when there's nothing to show.
    public var onChange: ((Activity?) -> Void)?
    private var shown: Activity?

    public init() {}

    /// The ring's colour: the Viorim kit's one accent, steel.
    public nonisolated static let ringTint: UInt32 = 0x9DB2CB

    private func compose() {
        let pill = Self.pill(media: media, pomodoro: pomodoro, claude: claude)
        guard pill != shown else { return }
        shown = pill
        onChange?(pill)
    }

    nonisolated static func pill(media: Activity?, pomodoro: Activity?, claude: ClaudeSummary?) -> Activity? {
        let ring = claude.map {
            Activity.Accessory(symbol: "terminal.fill", progress: $0.progress, tint: ringTint, label: $0.label)
        }
        if var pill = pomodoro ?? media {
            pill.accessory = ring
            return pill
        }
        guard let claude else { return nil }
        return Activity(
            feature: .home, symbol: "terminal.fill", title: claude.title, duration: .zero,
            accessory: claude.progress == nil ? nil : ring)
    }
}
