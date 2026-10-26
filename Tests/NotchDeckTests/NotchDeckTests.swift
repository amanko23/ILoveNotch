// SPDX-License-Identifier: MIT
import Testing

@testable import NotchDeck

struct NotchDeckTests {
    @Test func theModuleLoads() {
        #expect(NotchDeck.name == "NotchDeck")
    }
}
