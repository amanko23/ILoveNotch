// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import NotchDeck

struct InboxDownloadsTests {
    @Test func aNotificationRecordReadsItsTitleAndBody() throws {
        let plist: [String: Any] = [
            "app": "com.apple.mail", "req": ["titl": "Ravi", "subt": "Deck", "body": "Sent it over"],
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        let item = try #require(InboxFeature.parse(data, id: "1", app: "x", delivered: .now))
        #expect(item.app == "com.apple.mail" && item.title == "Ravi" && item.body == "Deck — Sent it over")
    }

    @Test func downloadsAddUpOnlyWhenEverySizeIsKnown() {
        let known = DownloadsFeature.Download(id: "a", name: "a.zip", bytes: 50, total: 100, speed: 0)
        let unknown = DownloadsFeature.Download(id: "b", name: "b.zip", bytes: 10, total: nil, speed: 0)
        #expect(DownloadsFeature.overall([known]) == 0.5)
        #expect(DownloadsFeature.overall([known, unknown]) == nil)
        #expect(DownloadsFeature.activity(for: [known, unknown])?.title == "2 downloading")
        #expect(DownloadsFeature.activity(for: []) == nil)
    }

    @Test func browsersPartialFilesAreRecognised() {
        let chrome = DownloadsFeature.inProgress(URL(filePath: "/tmp/none/report.pdf.crdownload"))
        #expect(chrome?.name == "report.pdf")
        #expect(DownloadsFeature.inProgress(URL(filePath: "/tmp/none/report.pdf")) == nil)
    }
}
