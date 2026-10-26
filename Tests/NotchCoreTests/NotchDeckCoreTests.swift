// SPDX-License-Identifier: MIT
import Foundation
import Testing

@testable import NotchCore

/// NotchDeck's additions to the core: the landing tab, the drawer's defaults, and accessories.
struct NotchDeckCoreTests {
    private func after(_ events: NotchEvent...) -> NotchState {
        var state = NotchState()
        for event in events { _ = state.handle(event) }
        return state
    }

    @Test func homeLeadsTheTabsAndSystemEndsThem() {
        #expect(FeatureID.allCases.first == .home && FeatureID.allCases.last == .system)
        #expect(FeatureID.home.title == "Home" && FeatureID.system.title == "System")
    }

    @Test func setLastTabChoosesWhereTheNotchOpensWithoutOpeningIt() {
        let state = after(.show, .setLastTab(.home))
        #expect(state.presentation == .compact && state.lastTab == .home)
        #expect(after(.show, .setLastTab(.home), .clicked).presentation == .expanded(tab: .home))
    }

    @Test func setLastTabIgnoresDisabledTabsAndAnOpenNotch() {
        #expect(after(.show, .setTabs([.media, .notes]), .setLastTab(.home)).lastTab == .media)
        let open = after(.show, .selectTab(.notes), .setLastTab(.home))
        #expect(open.presentation == .expanded(tab: .notes) && open.lastTab == .notes)
    }

    @Test func aHoveredActivityKeepsTheTabItOpens() {
        let meeting = Activity(feature: .calendar, symbol: "video.fill", title: "Standup", duration: .zero)
        let hovered = after(.show, .setOngoing(meeting), .pointerEntered, .setLastTab(.home))
        #expect(hovered.presentation == .hoverArmed && hovered.lastTab == .calendar)
        #expect(
            after(.show, .setOngoing(meeting), .pointerEntered, .setLastTab(.home), .clicked).presentation
                == .expanded(tab: .calendar))
    }

    @Test func anAccessoryTravelsWithItsActivity() {
        let ring = Activity.Accessory(symbol: "terminal.fill", progress: 0.5, tint: 0xD97757, label: "Claude, 3 of 6")
        let song = Activity(feature: .media, symbol: "music.note", title: "Song", duration: .zero, accessory: ring)
        #expect(after(.show, .setOngoing(song)).restingActivity?.accessory == ring)
    }

    @MainActor
    @Test func someTabsCanStartInTheDrawer() throws {
        let defaults = try #require(UserDefaults(suiteName: "NotchDeckCore.\(UUID().uuidString)"))
        let preferences = NotchPreferences(defaults: defaults, drawerByDefault: [.shelf, .notes])
        #expect(preferences.tabs.contains(.shelf) && !preferences.rowTabs.contains(.shelf), "on, in the drawer")
        preferences.place(.shelf, at: 1)
        #expect(preferences.rowTabs.contains(.shelf))
        let reopened = NotchPreferences(defaults: defaults, drawerByDefault: [.shelf, .notes])
        #expect(reopened.rowTabs.contains(.shelf) && !reopened.rowTabs.contains(.notes), "the user's choice stays")
        reopened.reset()
        #expect(!reopened.rowTabs.contains(.shelf), "reset brings the default drawer back")
    }
}
