// SPDX-License-Identifier: MIT
import Foundation
import SwiftUI

/// A permission prompt Claude Code left for the notch to answer: what it wants to do, and where.
/// The hook script waits up to a minute for the answer, then lets the terminal ask.
public struct PermissionRequest: Identifiable, Hashable, Sendable {
    /// The request file's name without `.req`: the session and when it asked.
    public let id: String
    public let sessionID: String
    /// The project folder's name.
    public let project: String
    /// The tool it wants to use, such as Bash or Edit.
    public let tool: String
    /// The command, or the file, on one line.
    public let summary: String
    public let date: Date

    /// Reads a request file: session, folder, tool, and summary, one per line.
    init?(id: String, contents: String, date: Date) {
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.count >= 4, !lines[0].isEmpty else { return nil }
        self.id = id
        sessionID = lines[0]
        project = lines[1].isEmpty ? "Claude Code" : URL(filePath: lines[1]).lastPathComponent
        tool = lines[2]
        summary = lines[3].trimmingCharacters(in: .whitespaces)
        self.date = date
    }

    /// "Claude wants to run" for a command, "Claude wants to edit" for a file, and so on.
    public var verb: String {
        switch tool {
        case "Bash": "Claude wants to run"
        case "Edit", "MultiEdit", "NotebookEdit": "Claude wants to edit"
        case "Write": "Claude wants to write"
        case "Read": "Claude wants to read"
        default: "Claude wants to use \(tool)"
        }
    }
}

/// How the notch answers a permission prompt.
public enum PermissionAnswer: String, Sendable {
    case allow, deny
    /// Leaves it to the terminal's own prompt.
    case terminal
}

/// A permission prompt with its answers: the project, what Claude wants to do, the command or file
/// in a monospaced well, and Deny, In terminal, and Allow. For the Agents tab and Home.
public struct PermissionCard: View {
    let request: PermissionRequest
    let agents: AgentsFeature

    public init(request: PermissionRequest, agents: AgentsFeature) {
        self.request = request
        self.agents = agents
    }

    /// The Viorim kit's steel accent.
    private static let accent = Color(red: 0x9D / 255, green: 0xB2 / 255, blue: 0xCB / 255)

    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Circle().fill(.orange).frame(width: 6, height: 6)
                Text(request.verb).font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                Text(request.project).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Text(request.summary)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .textSelection(.enabled)
            HStack(spacing: 6) {
                answerButton("Deny", .deny, fill: .primary.opacity(0.12), text: .primary)
                answerButton("In terminal", .terminal, fill: .primary.opacity(0.12), text: .primary)
                Spacer(minLength: 0)
                answerButton("Allow", .allow, fill: Self.accent, text: .black)
            }
        }
        .padding(8)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(request.verb): \(request.summary), in \(request.project)")
    }

    private func answerButton(_ title: String, _ answer: PermissionAnswer, fill: Color, text: Color) -> some View {
        Button(title) { agents.answer(request, answer) }
            .buttonStyle(.plain)
            .font(.caption.weight(.semibold))
            .foregroundStyle(text)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(fill, in: Capsule())
    }
}
