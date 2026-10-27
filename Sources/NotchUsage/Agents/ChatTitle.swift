// SPDX-License-Identifier: MIT
import Foundation

/// A Claude Code chat's title, read from its transcript (one JSON object per line) the way Claude
/// Code's own session list names it: the latest name given with /rename, else Claude's latest
/// summary, else the first thing you asked. Read on this Mac only; nothing is stored.
enum ChatTitle {
    static func read(transcript path: String) -> String? {
        guard let data = try? Data(contentsOf: URL(filePath: path), options: .alwaysMapped) else { return nil }
        return title(in: data)
    }

    static func title(in data: Data) -> String? {
        let lines = data.split(separator: UInt8(ascii: "\n"))
        var summary: String?
        for line in lines.reversed() {
            guard let object = parse(line, containing: ["custom-title", "summary"]) else { continue }
            if object["type"] as? String == "custom-title", let title = clean(object["customTitle"] as? String) {
                return title
            }
            if summary == nil, object["type"] as? String == "summary" { summary = clean(object["summary"] as? String) }
        }
        if let summary { return summary }
        for line in lines {
            guard let object = parse(line, containing: ["\"user\""]), object["type"] as? String == "user",
                object["isMeta"] as? Bool != true,
                let message = object["message"] as? [String: Any]
            else { continue }
            let text: String? =
                if let content = message["content"] as? String {
                    content
                } else {
                    (message["content"] as? [[String: Any]])?.first { $0["type"] as? String == "text" }?["text"]
                        as? String
                }
            // Slash commands, their output, and tool results aren't what you asked.
            guard let text, !text.hasPrefix("<"), let title = clean(text) else { continue }
            return title
        }
        return nil
    }

    /// Parses a line only when it mentions one of `markers`, so long transcripts stay quick.
    private static func parse(_ line: Data.SubSequence, containing markers: [String]) -> [String: Any]? {
        let text = String(decoding: line, as: UTF8.self)
        guard markers.contains(where: { text.contains($0) }) else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any]
    }

    /// One line, at most 80 characters.
    private static func clean(_ text: String?) -> String? {
        guard let first = text?.split(whereSeparator: \.isNewline).first else { return nil }
        let line = first.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return nil }
        return line.count > 80 ? String(line.prefix(79)) + "…" : line
    }
}
