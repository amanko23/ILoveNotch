// SPDX-License-Identifier: MIT
import Foundation
import Testing
import UniformTypeIdentifiers

@testable import NotchDeck

struct ConvertTests {
    @Test func eachKindOfFileGetsItsFormats() {
        #expect(Converter.targets(for: .png).map(\.title).prefix(3) == ["JPEG", "PNG", "JPEG, 2000 px"])
        #expect(Converter.targets(for: .pdf).map(\.ext) == ["png", "jpg"])
        #expect(Converter.targets(for: .quickTimeMovie).map(\.ext) == ["mp4", "mov", "m4a"])
        #expect(Converter.targets(for: .mp3).map(\.ext) == ["m4a"])
        #expect(Converter.targets(for: .plainText).isEmpty)
    }

    @Test func outputsSitBesideTheOriginalWithoutOverwriting() {
        let source = URL(filePath: "/tmp/Holiday.png")
        let taken: Set<String> = ["/tmp/Holiday.jpg", "/tmp/Holiday 2.jpg"]
        let output = Converter.outputURL(for: source, ext: "jpg") { taken.contains($0.path(percentEncoded: false)) }
        #expect(output.path(percentEncoded: false) == "/tmp/Holiday 3.jpg")
        // Same extension as the original: never the original itself.
        let same = Converter.outputURL(for: source, ext: "png") { _ in false }
        #expect(same.path(percentEncoded: false) == "/tmp/Holiday 2.png")
    }

    @Test func theResizeKeepsTheShapeAndNeverEnlarges() {
        #expect(Converter.fitted(CGSize(width: 4000, height: 3000), maxSide: 2000) == CGSize(width: 2000, height: 1500))
        #expect(Converter.fitted(CGSize(width: 1200, height: 4800), maxSide: 2000) == CGSize(width: 500, height: 2000))
        #expect(Converter.fitted(CGSize(width: 800, height: 600), maxSide: 2000) == CGSize(width: 800, height: 600))
    }
}
