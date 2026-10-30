// SPDX-License-Identifier: MIT
import NotchFeatures
import SwiftUI

/// The Agents tab: every session the connected tools reported, the ones waiting for approval
/// first in line to be noticed, with a way back to each one's terminal.
struct AgentsView: View {
    let agents: AgentsFeature

    var body: some View {
        if agents.connected.isEmpty {
            setup
        } else if let request = agents.permissionRequests.first {
            // NotchDeck: a prompt to answer comes before everything else.
            ScrollView {
                VStack(spacing: 6) {
                    PermissionCard(request: request, agents: agents)
                    if agents.permissionRequests.count > 1 {
                        Text("\(agents.permissionRequests.count - 1) more waiting")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(agents.sessions) { row($0) }
                }
                .padding(.vertical, 6)
            }
            .fadingEdges()
        } else if agents.sessions.isEmpty {
            FeatureUnavailableView(
                symbol: "terminal", title: "No agents at work",
                message: "Sessions show up here when \(names(agents.connected)) starts working.")
        } else {
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(agents.sessions) { row($0) }
                }
                .padding(.vertical, 6)
            }
            .fadingEdges()
        }
    }

    private var setup: some View {
        VStack(spacing: 8) {
            FeatureUnavailableView(
                symbol: "terminal", title: "Your coding agents, in the notch",
                message: agents.available.isEmpty
                    ? "Install Claude Code or Codex, then connect it here."
                    : "The notch shows when an agent needs your approval or finishes, and takes you back to its "
                        + "terminal. Connecting adds a hook to the tool's own settings.")
            HStack(spacing: 8) {
                ForEach(agents.available) { tool in
                    Button("Connect \(tool.name)") { agents.connect(tool) }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.15), in: Capsule())
                }
            }
            if let failure = agents.failure {
                Text(failure).font(.caption).foregroundStyle(.orange).multilineTextAlignment(.center)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func row(_ session: AgentSession) -> some View {
        let waiting = session.state == .waiting
        return HStack(spacing: 10) {
            ProviderLogo(providerID: session.tool.rawValue, name: session.tool.name, size: 18)
                .foregroundStyle(ProviderStyle.of(session.tool.rawValue).gradient)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.project).font(.callout.weight(.medium)).lineLimit(1)
                status(session)
                    .font(.caption)
                    .foregroundStyle(waiting ? Color.orange : Color.primary.opacity(0.55))
                    .lineLimit(1)
                if let progress = session.progress, session.state != .done {
                    let tint = waiting ? Color.orange : ProviderStyle.of(session.tool.rawValue).start
                    AgentProgressBar(progress: progress, tint: tint)
                        .padding(.top, 3)
                        .accessibilityLabel("\(session.todosDone) of \(session.todosTotal) to-dos done")
                }
            }
            Spacer(minLength: 0)
            if session.app != nil {
                Button("Go") { agents.open(session) }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(waiting ? Color.orange.opacity(0.85) : .white.opacity(0.14), in: Capsule())
                    .help("Go to its terminal")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(waiting ? Color.orange.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 9))
        .contentShape(Rectangle())
        .contextMenu {
            Button("Go to Terminal") { agents.open(session) }.disabled(session.app == nil)
            Button("Clear") { agents.clear(session) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Clear") { agents.clear(session) }
    }

    @ViewBuilder private func status(_ session: AgentSession) -> some View {
        switch session.state {
        case .waiting: Text("\(session.tool.shortName) needs you: \(session.detail ?? "waiting for approval")")
        case .working: Text(AgentSession.workingLine(session))
        case .compacting: Text("\(session.tool.shortName) is compacting its context")
        case .idle: Text("\(session.tool.shortName) is ready")
        // Fixed when drawn, not a ticking clock: it's redrawn whenever the tab is.
        case .done:
            Text("\(session.tool.shortName) finished \(session.updated.formatted(.relative(presentation: .named)))")
        }
    }
}

extension AgentSession {
    /// "Working 4m · Running tests · 2 of 5": how long this turn has run, the step it's on, and how
    /// far through its to-dos it is, whichever it reported.
    public static func workingLine(_ session: AgentSession, now: Date = .now) -> String {
        var parts = ["Working"]
        if let since = session.workingSince {
            let minutes = Int(now.timeIntervalSince(since) / 60)
            if minutes >= 1 { parts[0] += minutes >= 60 ? " \(minutes / 60)h \(minutes % 60)m" : " \(minutes)m" }
        }
        if let step = session.step { parts.append(step) }
        if session.todosTotal > 0 { parts.append("\(session.todosDone) of \(session.todosTotal)") }
        return parts.joined(separator: " · ")
    }
}

/// A slim bar for an agent's to-do progress.
public struct AgentProgressBar: View {
    let progress: Double
    let tint: Color

    public init(progress: Double, tint: Color) {
        self.progress = progress
        self.tint = tint
    }

    public var body: some View {
        Capsule()
            .fill(.primary.opacity(0.15))
            .frame(height: 4)
            .overlay(alignment: .leading) {
                GeometryReader { track in
                    Capsule().fill(tint).frame(width: max(4, track.size.width * min(max(progress, 0), 1)))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: progress)
    }
}

/// "Claude Code and Codex".
private func names(_ tools: Set<AgentTool>) -> String {
    AgentTool.allCases.filter(tools.contains).map(\.name).formatted(.list(type: .and))
}

extension AgentsFeature {
    /// Settings › Agents: which tools report to the notch.
    public var settingsView: some View { AgentsSettings(agents: self) }
}

private struct AgentsSettings: View {
    @Bindable var agents: AgentsFeature

    var body: some View {
        Group {
            ForEach(AgentTool.allCases) { tool in
                // A closure, not a method reference: see the app's GeneralSettings.
                Toggle(
                    isOn: Binding(
                        get: { agents.connected.contains(tool) },
                        set: { $0 ? agents.connect(tool) : agents.disconnect(tool) })
                ) {
                    HStack(spacing: 6) {
                        ProviderLogo(providerID: tool.rawValue, name: tool.name, size: 14)
                        Text(tool.name)
                    }
                    Text(explanation(tool))
                }
                .disabled(!agents.available.contains(tool))
            }
            Toggle("Show when an agent finishes in the background", isOn: $agents.announcesDone)
            Toggle("Chime when a long task finishes", isOn: $agents.chimesOnLongTasks)
            Toggle(isOn: $agents.answersFromNotch) {
                Text("Answer permission prompts from the notch")
                Text(
                    "When Claude Code asks to run a command or change a file, the notch shows Allow and Deny. "
                        + "Unanswered for a minute, or with NotchDeck closed, the terminal asks as usual.")
            }
            .disabled(!agents.connected.contains(.claude))
            if let failure = agents.failure {
                Text(failure).font(.caption).foregroundStyle(.red)
            }
        }
        .onAppear(perform: agents.refreshConnected)
    }

    private func explanation(_ tool: AgentTool) -> String {
        guard agents.available.contains(tool) else { return "Not on this Mac." }
        let adds = "Adds hooks to ~/\(tool.configPath); turning this off removes them."
        return tool == .codex ? adds + " Codex asks you to trust them the next time it starts." : adds
    }
}
