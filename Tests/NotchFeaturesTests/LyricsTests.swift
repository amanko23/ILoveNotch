// SPDX-License-Identifier: MIT
import Foundation
import Testing

@testable import NotchFeatures

struct LyricsTests {
    @Test func lrcLinesAreTimedAndSorted() {
        let lines = SyncedLyrics.parse(lrc: "[00:12.50] Second\n[ar:Someone]\n[00:01.00][01:00.00] Hook\n")
        #expect(lines.map(\.time) == [1, 12.5, 60])
        #expect(lines.map(\.text) == ["Hook", "Second", "Hook"])
    }

    @Test func theLineSungNowAndTheNextOne() {
        let lyrics = SyncedLyrics(lines: SyncedLyrics.parse(lrc: "[00:01.00] One\n[00:05.00] Two"), plain: nil)
        #expect(lyrics.line(at: 0).current == nil && lyrics.line(at: 0).next == "One")
        #expect(lyrics.line(at: 3).current == "One" && lyrics.line(at: 3).next == "Two")
        #expect(lyrics.line(at: 9).current == "Two" && lyrics.line(at: 9).next == nil)
    }

    @Test func videosAreToldApartFromMusic() {
        let chrome = "com.google.Chrome"
        #expect(VideoDetector.isVideo(bundleID: chrome, title: "Trailer - YouTube", artist: nil, album: nil))
        #expect(VideoDetector.isVideo(bundleID: "com.apple.Safari", title: "Episode 3", artist: "Netflix", album: nil))
        #expect(VideoDetector.isVideo(bundleID: "com.colliderli.iina", title: "movie.mkv", artist: nil, album: nil))
        #expect(!VideoDetector.isVideo(bundleID: "com.spotify.client", title: "YouTube", artist: nil, album: nil))
        #expect(!VideoDetector.isVideo(bundleID: "com.apple.Safari", title: "Maximum", artist: "Band", album: nil))
    }
}
