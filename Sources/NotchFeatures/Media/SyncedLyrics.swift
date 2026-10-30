// SPDX-License-Identifier: MIT
import Foundation

/// A track's lyrics with times, from LRCLIB (lrclib.net: free, no account, no key). Only the artist,
/// title, album and length of what's playing are sent, and only when the track changes while Media
/// or Home is showing it.
public struct SyncedLyrics: Equatable, Sendable {
    public struct Line: Equatable, Sendable {
        public var time: TimeInterval
        public var text: String
    }

    /// Lines in time order; empty when only plain lyrics exist.
    public var lines: [Line]
    /// The plain text, when the lyrics have no times.
    public var plain: String?

    /// The line sung at `position` seconds and the one after it.
    public func line(at position: TimeInterval) -> (current: String?, next: String?) {
        guard let index = lines.lastIndex(where: { $0.time <= position }) else {
            return (nil, lines.first?.text)
        }
        let next = lines.index(after: index)
        return (lines[index].text, next < lines.endIndex ? lines[next].text : nil)
    }

    /// Parses LRC text: lines like "[01:23.45] words", possibly with several times per line.
    static func parse(lrc: String) -> [Line] {
        var lines: [Line] = []
        for raw in lrc.split(whereSeparator: \.isNewline) {
            var rest = Substring(raw)
            var times: [TimeInterval] = []
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                let parts = tag.split(separator: ":")
                if parts.count == 2, let minutes = Double(parts[0]), let seconds = Double(parts[1]) {
                    times.append(minutes * 60 + seconds)
                }
                rest = rest[rest.index(after: close)...]
            }
            let text = rest.trimmingCharacters(in: .whitespaces)
            for time in times { lines.append(Line(time: time, text: text)) }
        }
        return lines.sorted { $0.time < $1.time }
    }
}

/// Fetches and caches lyrics from LRCLIB.
actor LyricsProvider {
    static let shared = LyricsProvider()
    private var cache: [String: SyncedLyrics?] = [:]

    private struct Record: Decodable {
        var syncedLyrics: String?
        var plainLyrics: String?
    }

    static func key(artist: String?, title: String) -> String {
        "\(artist ?? "")\u{1F}\(title)".lowercased()
    }

    /// The lyrics for a track, or nil when LRCLIB has none.
    func lyrics(title: String, artist: String?, album: String?, duration: TimeInterval?) async -> SyncedLyrics? {
        let key = Self.key(artist: artist, title: title)
        if let cached = cache[key] { return cached }
        var found = await get(title: title, artist: artist, album: album, duration: duration)
        if found == nil { found = await search(title: title, artist: artist) }
        let result = found.flatMap(Self.lyrics(from:))
        cache[key] = result
        if cache.count > 200 { cache.removeAll() }
        return result
    }

    private func get(title: String, artist: String?, album: String?, duration: TimeInterval?) async -> Record? {
        var items = [URLQueryItem(name: "track_name", value: title)]
        if let artist { items.append(URLQueryItem(name: "artist_name", value: artist)) }
        if let album { items.append(URLQueryItem(name: "album_name", value: album)) }
        if let duration { items.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded())))) }
        guard let data = await fetch("https://lrclib.net/api/get", items) else { return nil }
        return try? JSONDecoder().decode(Record.self, from: data)
    }

    private func search(title: String, artist: String?) async -> Record? {
        let query = [title, artist].compactMap { $0 }.joined(separator: " ")
        guard let data = await fetch("https://lrclib.net/api/search", [URLQueryItem(name: "q", value: query)]),
            let records = try? JSONDecoder().decode([Record].self, from: data)
        else { return nil }
        return records.first { $0.syncedLyrics != nil } ?? records.first
    }

    private func fetch(_ address: String, _ items: [URLQueryItem]) async -> Data? {
        guard var components = URLComponents(string: address) else { return nil }
        components.queryItems = items
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("NotchDeck (personal)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
            (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return data
    }

    private static func lyrics(from record: Record) -> SyncedLyrics? {
        let lines = record.syncedLyrics.map(SyncedLyrics.parse(lrc:)) ?? []
        let plain = record.plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lines.isEmpty || !(plain ?? "").isEmpty else { return nil }
        return SyncedLyrics(lines: lines, plain: plain)
    }
}

/// Whether what's playing is a video: a video player app, or a browser playing from a video site.
public enum VideoDetector {
    static let players: Set<String> = [
        "com.apple.TV", "com.apple.QuickTimePlayerX", "com.colliderli.iina", "org.videolan.vlc",
        "com.firecore.infuse", "com.netflix.Netflix",
    ]
    static let browsers: Set<String> = [
        "com.apple.Safari", "com.google.Chrome", "company.thebrowser.Browser", "com.microsoft.edgemac",
        "org.mozilla.firefox", "com.brave.Browser", "com.apple.WebKit.GPU", "com.apple.SafariTechnologyPreview",
    ]
    static let services = [
        "youtube", "netflix", "prime video", "primevideo", "disney+", "disney plus", "hotstar", "jiocinema",
        "hulu", "max", "hbo", "apple tv", "zee5", "sonyliv", "twitch", "vimeo",
    ]

    /// A video player always counts; a browser counts when the title, artist or album names a
    /// video service (sites put their name there, e.g. "Netflix" as the artist, "- YouTube" in the
    /// title). Anything else, such as Music or Spotify, is audio.
    public static func isVideo(bundleID: String?, title: String, artist: String?, album: String?)
        -> Bool
    {
        guard let bundleID else { return false }
        if players.contains(bundleID) { return true }
        guard browsers.contains(bundleID) || bundleID.hasPrefix("com.google.Chrome") else { return false }
        let text = [title, artist ?? "", album ?? ""].joined(separator: " ").lowercased()
        let words = Set(text.split { !$0.isLetter && !$0.isNumber && $0 != "+" }.map(String.init))
        return services.contains { service in
            service.contains(" ") || service.contains("+") ? text.contains(service) : words.contains(service)
        }
    }
}
