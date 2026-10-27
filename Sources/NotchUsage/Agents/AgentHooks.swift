// SPDX-License-Identifier: MIT
import Foundation
import NotchFeatures

/// A coding agent whose hooks can report to the notch.
public enum AgentTool: String, CaseIterable, Identifiable, Sendable {
    case claude, codex

    public var id: Self { self }

    public var name: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        }
    }

    /// For the closed notch, where there's little room.
    public var shortName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }

    /// Its hooks file, relative to the home folder.
    var configPath: String {
        switch self {
        case .claude: ".claude/settings.json"
        case .codex: ".codex/hooks.json"
        }
    }

    /// The tool's hook events, what each one means for the notch, and which of an event's cases
    /// count. Claude Code tells hooks it needs approval through a notification, sent once a prompt
    /// has waited a few seconds; Codex has an event for it. Claude's "waiting for your input" after
    /// every idle minute isn't asking for anything, so it's left out.
    ///
    /// NotchDeck adds three of Claude Code's long-standing events: a session starting (ready),
    /// compacting its context, and its to-do list changing, which is the one measure of progress
    /// Claude Code gives hooks. Only events Claude Code has had for a long time: one it doesn't know
    /// can make it reject the whole settings file.
    var events: [(event: String, matcher: String?, state: String)] {
        let waiting: (String, String?, String) =
            switch self {
            case .claude: ("Notification", "permission_prompt|elicitation_dialog", "waiting")
            case .codex: ("PermissionRequest", nil, "waiting")
            }
        let common: [(event: String, matcher: String?, state: String)] = [
            ("UserPromptSubmit", nil, "working"), waiting, ("PostToolUse", nil, "resumed"), ("Stop", nil, "done"),
            ("SessionEnd", nil, "ended"),
        ]
        guard self == .claude else { return common }
        return common + [
            ("SessionStart", nil, "idle"), ("PreCompact", nil, "compacting"),
            ("PostToolUse", Self.todoTools, "todos"),
        ]
    }

    /// Claude Code's to-do tools: the older TodoWrite, which sends the whole list each time, and the
    /// newer task tools, which add and update one task at a time.
    static let todoTools = "TodoWrite|TaskCreate|TaskUpdate"
}

/// What went wrong changing a tool's settings. Nothing is written when any of these happen.
public enum AgentHooksError: LocalizedError, Equatable {
    case unreadable(String)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let path): "\(path) isn't a JSON object NotchDeck can read, so it wasn't changed."
        }
    }
}

/// Adds and removes the notch's hooks in Claude Code's and Codex's own settings: opt-in per tool,
/// next to whatever hooks are already there, and removing takes out exactly what adding put in.
/// The hooks run a small script that writes one file per session into `states`, which
/// `AgentsFeature` watches.
public struct AgentHooks: Sendable {
    let home: URL
    /// The hook script, named so NotchDeck can always tell its hooks from anyone else's.
    let script: URL
    /// Where the script writes each session's state.
    let states: URL
    /// A copy of each settings file from just before NotchDeck last changed it.
    let backups: URL

    static let scriptName = "notchdeck-agent-hook"

    public init() {
        self.init(
            home: FileManager.default.homeDirectoryForCurrentUser,
            support: AppSupport.file(Self.scriptName).deletingLastPathComponent())
    }

    init(home: URL, support: URL) {
        self.home = home
        script = support.appending(path: Self.scriptName)
        states = support.appending(path: "Agents", directoryHint: .isDirectory)
        backups = support.appending(path: "Backups", directoryHint: .isDirectory)
    }

    func configFile(_ tool: AgentTool) -> URL { home.appending(path: tool.configPath) }

    /// Whether the tool is on this Mac: its settings folder exists.
    func isPresent(_ tool: AgentTool) -> Bool {
        FileManager.default.fileExists(atPath: configFile(tool).deletingLastPathComponent().path)
    }

    /// Whether the tool's settings have the notch's hooks.
    func isInstalled(_ tool: AgentTool) -> Bool {
        guard let settings = settings(tool) else { return false }
        return Self.hasOurs(settings)
    }

    /// Whether the installed hooks are exactly the ones this version adds, so an update that hooks
    /// more events can add them to a tool that's already connected.
    func isCurrent(_ tool: AgentTool) -> Bool {
        guard let settings = settings(tool) else { return false }
        return Self.ours(in: settings) == Self.ours(in: Self.adding(tool, command: command, to: [:]))
    }

    private func settings(_ tool: AgentTool) -> [String: Any]? {
        guard let data = try? Data(contentsOf: configFile(tool)) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    public func install(_ tool: AgentTool) throws {
        try FileManager.default.createDirectory(at: states, withIntermediateDirectories: true)
        try writeScript()
        try edit(tool) { Self.adding(tool, command: command, to: $0) }
    }

    /// Takes the tool's hooks out. With no tool left, the script and its session files go too.
    public func uninstall(_ tool: AgentTool) throws {
        try edit(tool) { Self.removing(from: $0) }
        guard !AgentTool.allCases.contains(where: isInstalled) else { return }
        try? FileManager.default.removeItem(at: states)
        try? FileManager.default.removeItem(at: script)
    }

    /// Rewrites the script if an update changed it, so installed hooks run the current one.
    func refreshScript() {
        guard (try? String(contentsOf: script, encoding: .utf8)) != Self.scriptSource else { return }
        try? writeScript()
    }

    private func writeScript() throws {
        try Data(Self.scriptSource.utf8).write(to: script, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
    }

    /// Single quotes keep the space in "Application Support" from splitting the command.
    private var command: String { "'\(script.path)'" }

    // MARK: Settings files

    /// Reads a tool's JSON settings (a missing file is an empty one), changes them, and writes them
    /// back atomically with their permissions kept, after saving a backup. A file that exists but
    /// can't be read as a JSON object is never touched.
    private func edit(_ tool: AgentTool, _ change: ([String: Any]) -> [String: Any]) throws {
        let file = configFile(tool)
        let fileManager = FileManager.default
        var settings: [String: Any] = [:]
        var permissions: Any?
        if fileManager.fileExists(atPath: file.path) {
            guard let data = try? Data(contentsOf: file),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { throw AgentHooksError.unreadable("~/" + tool.configPath) }
            settings = object
            permissions = try? fileManager.attributesOfItem(atPath: file.path)[.posixPermissions]
            try fileManager.createDirectory(at: backups, withIntermediateDirectories: true)
            try data.write(to: backups.appending(path: "\(tool.rawValue)-\(file.lastPathComponent)"), options: .atomic)
        }
        let changed = change(settings)
        guard !NSDictionary(dictionary: changed).isEqual(to: settings) else { return }
        // Codex's hooks.json holds only hooks: one NotchDeck emptied goes, rather than stay empty.
        if tool == .codex, changed.isEmpty {
            try? fileManager.removeItem(at: file)
            return
        }
        try fileManager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(
            withJSONObject: changed, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: file, options: .atomic)
        if let permissions { try? fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: file.path) }
    }

    /// The notch's handlers in `settings`, as "event matcher command" lines, to compare.
    static func ours(in settings: [String: Any]) -> Set<String> {
        let events = settings["hooks"] as? [String: Any] ?? [:]
        var found: Set<String> = []
        for (event, groups) in events {
            for case let group as [String: Any] in groups as? [Any] ?? [] {
                for handler in group["hooks"] as? [Any] ?? [] where isOurs(handler) {
                    let command = (handler as? [String: Any])?["command"] as? String ?? ""
                    found.insert("\(event) \(group["matcher"] as? String ?? "*") \(command)")
                }
            }
        }
        return found
    }

    static func isOurs(_ handler: Any) -> Bool {
        ((handler as? [String: Any])?["command"] as? String)?.contains(scriptName) == true
    }

    static func hasOurs(_ settings: [String: Any]) -> Bool {
        let events = settings["hooks"] as? [String: Any] ?? [:]
        return events.values.contains { groups in
            (groups as? [Any] ?? []).contains {
                (($0 as? [String: Any])?["hooks"] as? [Any] ?? []).contains(where: isOurs)
            }
        }
    }

    /// `settings` with the notch's hooks for `tool` after everyone else's, one group per event. It
    /// runs in the background (`async`), so an agent never waits on it.
    static func adding(_ tool: AgentTool, command: String, to settings: [String: Any]) -> [String: Any] {
        var settings = removing(from: settings)
        var events = settings["hooks"] as? [String: Any] ?? [:]
        for (event, matcher, state) in tool.events {
            var group: [String: Any] = [
                "hooks": [["type": "command", "command": "\(command) \(tool.rawValue) \(state)", "async": true]]
            ]
            if let matcher { group["matcher"] = matcher }
            events[event] = (events[event] as? [Any] ?? []) + [group]
        }
        settings["hooks"] = events
        return settings
    }

    /// `settings` without the notch's hooks. Groups, events, and a `hooks` key left empty go too;
    /// everything else stays as it was.
    static func removing(from settings: [String: Any]) -> [String: Any] {
        guard let events = settings["hooks"] as? [String: Any] else { return settings }
        var kept: [String: Any] = [:]
        for (event, value) in events {
            guard let groups = value as? [Any] else {
                kept[event] = value
                continue
            }
            let remaining = groups.compactMap { group -> Any? in
                guard var group = group as? [String: Any], let handlers = group["hooks"] as? [Any],
                    handlers.contains(where: isOurs)
                else { return group }
                let others = handlers.filter { !isOurs($0) }
                if others.isEmpty { return nil }
                group["hooks"] = others
                return group
            }
            if !remaining.isEmpty { kept[event] = remaining }
        }
        var settings = settings
        settings["hooks"] = kept.isEmpty ? nil : kept
        return settings
    }

    // MARK: The hook script

    /// Runs on the agent's hook events. It writes one small file per session beside itself: the
    /// state, the project folder, the app the agent runs in, its process, what it's waiting for, and
    /// (NotchDeck) how far through its to-do list it is, the step it's on, and when it started
    /// working. Never the prompt or any code, and nothing leaves the Mac. `plutil` reads the hook's
    /// JSON, since macOS has no `jq`. It never blocks the agent and always exits 0.
    ///
    /// The session file, one field per line: state, folder, bundle ID, TERM_PROGRAM, pid, message,
    /// tool, to-dos done, to-dos in all, current step, when it started working (Unix time), and the
    /// path of the session's transcript, where the app reads its title (the path only, never its text).
    static let scriptSource = #"""
        #!/bin/sh
        # NotchDeck agent status, run by Claude Code's and Codex's hooks. NotchDeck adds the hooks
        # when you connect a tool in Settings > Agents and removes them when you disconnect.
        # Usage: notchdeck-agent-hook <claude|codex> <event> < hook.json
        # Events: idle working waiting resumed compacting todos done ended
        tool=$1
        event=$2
        dir="$(dirname "$0")/Agents"
        if [ ! -d "$dir" ]; then cat >/dev/null; exit 0; fi
        # After every tool call: only worth reading while one of this tool's sessions is waiting,
        # compacting, or idle, any of which a tool call means is working again.
        if [ "$event" = resumed ] && ! grep -qsxE 'waiting|compacting|idle' "$dir/$tool"-*; then
            cat >/dev/null
            exit 0
        fi
        input=$(cat)
        field() { printf '%s' "$input" | /usr/bin/plutil -extract "$1" raw -o - - 2>/dev/null | tr '\n\r' '  '; }
        value() { field "$1" | sed 's/ *$//'; }
        session=$(field session_id | tr -cd 'A-Za-z0-9._-')
        [ -n "$session" ] || exit 0
        file="$dir/$tool-$session"
        old() { sed -n "${1}p" "$file" 2>/dev/null; }
        previous=$(old 1)
        finished=$(old 8)
        total=$(old 9)
        step=$(old 10)
        since=$(old 11)
        case $finished in '' | *[!0-9]*) finished=0 ;; esac
        case $total in '' | *[!0-9]*) total=0 ;; esac
        case $since in '' | *[!0-9]*) since= ;; esac
        case $event in
        ended) rm -f "$file"; exit 0 ;;
        resumed)
            case $previous in
            waiting | compacting | idle) state=working ;;
            *) exit 0 ;;
            esac
            ;;
        todos)
            state=working
            case $(value tool_name) in
            TodoWrite)
                todos=$(printf '%s' "$input" | /usr/bin/plutil -extract tool_input.todos json -o - - 2>/dev/null)
                total=$(printf '%s' "$todos" | grep -o '"status" *: *"' | wc -l | tr -d ' ')
                finished=$(printf '%s' "$todos" | grep -o '"status" *: *"completed"' | wc -l | tr -d ' ')
                step=
                i=0
                while [ "$i" -lt "$total" ] && [ "$i" -lt 100 ]; do
                    if [ "$(value "tool_input.todos.$i.status")" = in_progress ]; then
                        step=$(value "tool_input.todos.$i.activeForm")
                        break
                    fi
                    i=$((i + 1))
                done
                ;;
            TaskCreate) total=$((total + 1)) ;;
            TaskUpdate)
                case $(value tool_input.status) in
                completed) finished=$((finished + 1)) ;;
                deleted) total=$((total - 1)) ;;
                in_progress) step=$(value tool_input.activeForm) ;;
                esac
                ;;
            esac
            [ "$total" -ge 0 ] || total=0
            [ "$finished" -le "$total" ] || finished=$total
            ;;
        working)
            state=working
            # A new prompt after a finished list starts counting afresh.
            if [ "$total" -gt 0 ] && [ "$finished" -ge "$total" ]; then
                finished=0
                total=0
                step=
            fi
            ;;
        idle | waiting | compacting | done) state=$event ;;
        *) exit 0 ;;
        esac
        # When the turn started, for "Working 4m": kept through approvals and compacting.
        if [ "$state" = working ]; then
            case $previous in
            working | waiting | compacting) [ -n "$since" ] || since=$(date +%s) ;;
            *) since=$(date +%s) ;;
            esac
        fi
        message=
        asked=
        if [ "$state" = waiting ]; then
            message=$(field message)
            asked=$(field tool_name)
        fi
        tmp=$(mktemp "$dir/.$tool.XXXXXX") || exit 0
        {
            printf '%s\n' "$state" "$(field cwd)" "${__CFBundleIdentifier:-}" "${TERM_PROGRAM:-}" "$PPID"
            printf '%s\n' "$message" "$asked" "$finished" "$total" "$step" "$since" "$(field transcript_path)"
        } >"$tmp"
        mv -f "$tmp" "$file"
        exit 0

        """#
}
