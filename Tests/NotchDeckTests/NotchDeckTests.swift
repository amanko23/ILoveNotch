// SPDX-License-Identifier: MIT
import AppKit
import Foundation
import NotchCore
import NotchFeatures
import NotchUsage
import SwiftUI
import Testing

@testable import NotchDeck

private func defaults() -> UserDefaults {
    UserDefaults(suiteName: "NotchDeckTests.\(UUID().uuidString)")!
}

@MainActor
struct PomodoroTests {
    @Test func aCycleRunsFocusBreaksAndALongBreakAfterTheLastRound() {
        let pomodoro = Pomodoro(defaults: defaults())
        pomodoro.notifies = false
        pomodoro.startsBreaksAutomatically = false
        var plan = PomodoroPlan()
        plan.rounds = 2
        pomodoro.plan = plan
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        #expect(!pomodoro.isActive && pomodoro.remaining == 25 * 60 && pomodoro.ongoingActivity == nil)

        pomodoro.start(now: start)
        #expect(pomodoro.isRunning && pomodoro.endsAt == start + 25 * 60)
        #expect(pomodoro.ongoingActivity?.countdown == start + 25 * 60 && pomodoro.ongoingActivity?.feature == .home)

        pomodoro.advance(now: start + 25 * 60, finished: true)
        #expect(pomodoro.phase == .shortBreak && pomodoro.finishedRounds == 1 && !pomodoro.isRunning)
        #expect(pomodoro.ongoingActivity?.title == "Short break paused", "waits for a click to start the break")
        pomodoro.advance(now: start + 30 * 60, finished: true)
        #expect(pomodoro.phase == .focus)
        pomodoro.advance(now: start + 55 * 60, finished: true)
        #expect(pomodoro.phase == .longBreak && pomodoro.remaining == 15 * 60, "after the second round")
        pomodoro.advance(now: start + 70 * 60, finished: true)
        #expect(pomodoro.phase == .focus && pomodoro.finishedRounds == 0, "a long break starts a new cycle")

        pomodoro.reset()
        #expect(!pomodoro.isActive && pomodoro.ongoingActivity == nil)
    }

    @Test func pausingKeepsTheTimeLeftAndBreaksCanStartThemselves() {
        let pomodoro = Pomodoro(defaults: defaults())
        pomodoro.notifies = false
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        pomodoro.start(now: start)
        pomodoro.pause(now: start + 60)
        #expect(!pomodoro.isRunning && pomodoro.remaining == 24 * 60)
        #expect(abs(pomodoro.progress(at: start + 600) - 1.0 / 25) < 1e-9, "paused, it doesn't move")
        pomodoro.start(now: start + 120)
        #expect(pomodoro.endsAt == start + 120 + 24 * 60)

        pomodoro.advance(now: start + 25 * 60, finished: true)
        #expect(pomodoro.phase == .shortBreak && pomodoro.isRunning, "breaks start by themselves by default")
        pomodoro.reset()
    }

    @Test func thePlanIsRemembered() {
        let store = defaults()
        let pomodoro = Pomodoro(defaults: store)
        var plan = pomodoro.plan
        plan.focusMinutes = 50
        plan.rounds = 3
        pomodoro.plan = plan
        #expect(pomodoro.remaining == 50 * 60)
        #expect(Pomodoro(defaults: store).plan == plan)
    }
}

struct ClosedPillTests {
    private let song = Activity(feature: .media, symbol: "music.note", title: "Midnight City", duration: .zero)
    private let focus = Activity(
        feature: .home, symbol: "timer", title: "Focus", duration: .zero, countdown: .distantFuture)
    private let claude = ClaudeSummary(title: "deck", progress: 0.5, label: "Claude is working on deck")

    @Test func claudesRingRidesAlongWithWhatsPlaying() {
        let pill = ClosedPillComposer.pill(media: song, pomodoro: nil, claude: claude)
        #expect(pill?.title == "Midnight City" && pill?.feature == .media)
        #expect(pill?.accessory?.progress == 0.5 && pill?.accessory?.tint == ClosedPillComposer.ringTint)
    }

    @Test func pomodoroOutranksMusicAndClaudeShowsAlone() {
        #expect(ClosedPillComposer.pill(media: song, pomodoro: focus, claude: nil)?.title == "Focus")
        let alone = ClosedPillComposer.pill(media: nil, pomodoro: nil, claude: claude)
        #expect(alone?.title == "deck" && alone?.feature == .home && alone?.accessory != nil)
        let noList = ClaudeSummary(title: "deck", progress: nil, label: "")
        #expect(ClosedPillComposer.pill(media: nil, pomodoro: nil, claude: noList)?.accessory == nil)
        #expect(ClosedPillComposer.pill(media: nil, pomodoro: nil, claude: nil) == nil)
    }

    @Test func onlyBusySessionsMakeASummary() {
        let now = Date.now
        let waiting = AgentSession(id: "claude-a", tool: .claude, state: .waiting, project: "api", updated: now)
        let idle = AgentSession(id: "claude-b", tool: .claude, state: .idle, project: "web", updated: now)
        #expect(ClaudeSummary([waiting, idle]) == nil, "waiting has its own reminder; idle has nothing to show")
        let working = AgentSession(
            id: "claude-c", tool: .claude, state: .working, project: "deck", updated: now, todosDone: 2,
            todosTotal: 4)
        let summary = ClaudeSummary([waiting, working])
        #expect(summary?.title == "deck" && summary?.progress == 0.5)
        let compacting = AgentSession(id: "claude-d", tool: .claude, state: .compacting, project: "x", updated: now)
        #expect(ClaudeSummary([working, compacting])?.title == "2 working")
    }
}

struct EnergyTests {
    @Test func helpersCountAsTheirOutermostApp() {
        let helper =
            "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/"
            + "Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"
        #expect(EnergySnapshot.owner(of: helper) == "/Applications/Google Chrome.app")
        #expect(EnergySnapshot.owner(of: "/opt/homebrew/bin/node") == "/opt/homebrew/bin/node")
    }

    @Test func rankingTurnsNanojoulesIntoWattsPerApp() {
        let start = ContinuousClock.now
        let app = "/Applications/Xcode.app"
        let earlier = EnergySnapshot(
            taken: start,
            processes: [
                1: .init(nanojoules: 0, path: app + "/Contents/MacOS/Xcode"),
                2: .init(nanojoules: 0, path: app + "/Contents/Helpers/Helper.app/Contents/MacOS/Helper"),
                3: .init(nanojoules: 0, path: "/usr/local/bin/tool"),
                4: .init(nanojoules: 5, path: "/usr/bin/idle"),
            ])
        let later = EnergySnapshot(
            taken: start + .seconds(2),
            processes: [
                1: .init(nanojoules: 3_000_000_000, path: app + "/Contents/MacOS/Xcode"),
                2: .init(nanojoules: 1_000_000_000, path: app + "/Contents/Helpers/Helper.app/Contents/MacOS/Helper"),
                3: .init(nanojoules: 1_000_000_000, path: "/usr/local/bin/tool"),
                4: .init(nanojoules: 6, path: "/usr/bin/idle"),
                5: .init(nanojoules: 9_000_000_000, path: "/Applications/New.app/Contents/MacOS/New"),
            ])
        let ranking = EnergySnapshot.ranking(from: earlier, to: later, limit: 5)
        #expect(ranking.map(\.id) == [app, "/usr/local/bin/tool"], "a process that just started isn't ranked")
        #expect(ranking.first?.watts == 2 && ranking.first?.isApp == true && ranking.first?.name == "Xcode")
        #expect(ranking.last?.wattsText == "0.5 W")
    }

    @Test func aSnapshotOfThisMacReadsItsOwnProcesses() {
        let snapshot = EnergySnapshot.take()
        #expect(snapshot.processes[getpid()] != nil, "the test runner is one of the user's processes")
    }
}

struct WeatherTests {
    @Test func coordinatesAreRoundedBeforeTheyLeaveTheMac() throws {
        let url = try #require(OpenMeteo.forecastURL(latitude: 18.52043, longitude: 73.85674, fahrenheit: false))
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(query.first { $0.name == "latitude" }?.value == "18.5")
        #expect(query.first { $0.name == "longitude" }?.value == "73.9")
        #expect(query.first { $0.name == "temperature_unit" }?.value == "celsius")
    }

    @Test func aForecastDecodesFromOpenMeteo() throws {
        let json = """
            {"latitude":18.5,"longitude":73.875,"timezone":"Asia/Kolkata",
             "current":{"time":"2026-10-26T10:15","interval":900,"temperature_2m":21.4,
              "apparent_temperature":20.2,"weather_code":2,"is_day":1},
             "daily":{"time":["2026-10-26","2026-10-27","2026-10-28"],"weather_code":[2,0,80],
              "temperature_2m_max":[26.1,24.0,22.3],"temperature_2m_min":[17.0,16.2,15.1],
              "precipitation_probability_max":[10,null,65]}}
            """
        let forecast = try OpenMeteo.decodeForecast(Data(json.utf8), place: "Pune", fahrenheit: false)
        #expect(forecast.temperature == 21.4 && forecast.condition.text == "Partly cloudy" && forecast.isDay)
        #expect(forecast.days.count == 3 && forecast.days[1].rainChance == nil && forecast.days[2].rainChance == 65)
        #expect(forecast.symbol == "cloud.sun.fill" && Forecast.degrees(forecast.temperature) == "21°")
        #expect(WeatherCondition(code: 95).symbol() == "cloud.bolt.rain.fill")
    }
}

struct HomeDataTests {
    @Test func theAgendaListsWhatsLeftDayByDay() {
        let calendar = Calendar.current
        // 2 pm local time, so every event below stays on today in any time zone.
        let today = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_790_000_000))
        let now = today + 14 * 3600
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let events = [
            AgendaEvent(id: "past", title: "Breakfast", start: now - 7200, end: now - 3600, isAllDay: false),
            AgendaEvent(id: "later", title: "Review", start: now + 3600, end: now + 7200, isAllDay: false),
            AgendaEvent(id: "now", title: "Standup", start: now - 600, end: now + 600, isAllDay: false),
            AgendaEvent(id: "tomorrow", title: "Gym", start: tomorrow, end: tomorrow + 86400, isAllDay: true),
        ]
        #expect(Agenda.upcoming(events, now: now).map(\.id) == ["now", "later", "tomorrow"])
    }

    @Test func focusShortcutsAreFoundByName() {
        let output = "Morning Routine\nSet Focus: Work\nTurn Off Focus\nDND for an hour\nResize Images\n"
        #expect(FocusShortcuts.focusShortcuts(in: output) == ["Set Focus: Work", "Turn Off Focus", "DND for an hour"])
    }

    @Test func theBatteryReadsAppleSiliconAndIntelRegistries() throws {
        let appleSilicon = try #require(
            BatteryReport(registry: [
                "CurrentCapacity": 84, "MaxCapacity": 100, "IsCharging": true, "ExternalConnected": true,
                "CycleCount": 212, "DesignCapacity": 6075, "NominalChargeCapacity": 5528, "Temperature": 3050,
                "InstantAmperage": 2000, "Voltage": 12500, "AvgTimeToFull": 45, "AdapterDetails": ["Watts": 70],
            ]))
        #expect(appleSilicon.percent == 84 && appleSilicon.health == 90 && appleSilicon.cycleCount == 212)
        #expect(appleSilicon.batteryWatts == 25 && appleSilicon.adapterWatts == 70)
        #expect(appleSilicon.remainingText == "0:45" && appleSilicon.temperature == 30.5)
        let discharging = try #require(
            BatteryReport(registry: [
                "CurrentCapacity": 3000, "MaxCapacity": 6000, "InstantAmperage": UInt64(bitPattern: -1000),
                "Voltage": 12000, "AvgTimeToEmpty": 65535,
            ]))
        #expect(discharging.percent == 50 && discharging.batteryWatts == -12, "signed amperage, as its bit pattern")
        #expect(discharging.minutesRemaining == nil, "65535 means still estimating")
        #expect(BatteryReport(registry: ["CurrentCapacity": 1]) == nil)
    }

    @Test func theClaudeTileSaysWhatsHappening() {
        let since = Date(timeIntervalSince1970: 1_790_000_000)
        let working = AgentSession(
            id: "claude-1", tool: .claude, state: .working, project: "deck", updated: since, todosDone: 2,
            todosTotal: 5, step: "Running tests", workingSince: since)
        #expect(Deck.headline(working) == "Working · deck")
        #expect(Deck.detail(working, now: since + 65 * 60) == "2 of 5 · 1h 5m")
        let fresh = AgentSession(id: "claude-2", tool: .claude, state: .working, project: "x", updated: since)
        #expect(Deck.detail(fresh, now: since) == "Working on it")
        #expect(Deck.clock(24 * 60 + 59.2) == "25:00" && Deck.clock(3725) == "1:02:05")
    }

    @MainActor
    @Test func theTileFeaturesTheSessionThatNeedsYou() {
        let now = Date.now
        let done = AgentSession(id: "claude-a", tool: .claude, state: .done, project: "a", updated: now)
        let working = AgentSession(id: "claude-b", tool: .claude, state: .working, project: "b", updated: now - 60)
        let waiting = AgentSession(id: "claude-c", tool: .claude, state: .waiting, project: "c", updated: now - 120)
        #expect(HomeFeature.featured([done, working, waiting])?.id == "claude-c")
        #expect(HomeFeature.featured([done, working])?.id == "claude-b")
        #expect(HomeFeature.featured([done])?.id == "claude-a")
    }
}

/// Home and its peeks, drawn offscreen at the default open size and the smallest: each one has to
/// lay out without trapping. With SNAPSHOT_DIR set, PNGs land there for a look.
@MainActor
struct HomeRenderTests {
    private func home() -> HomeFeature {
        let store = defaults()
        return HomeFeature(
            eventStore: EventStore(), agents: AgentsFeature(defaults: store), monitor: SystemMonitor(),
            defaults: store)
    }

    @Test func theDashboardDraws() throws {
        try render(home().view, name: "home")
    }

    @Test(arguments: [HomeFeature.Peek.claude, .focus, .calendar, .system, .weather, .user, .viorim])
    func everyPeekDraws(peek: HomeFeature.Peek) throws {
        let home = home()
        home.peek = peek
        try render(home.view, name: "home-\(peek.rawValue)")
    }

    @Test func theSystemTabDraws() throws {
        try render(SystemFeature(monitor: SystemMonitor()).view, name: "system")
    }

    private func render(_ view: some View, name: String) throws {
        try render(view, name: name, size: CGSize(width: 396, height: 192))
        try render(view, name: name + "-smallest", size: CGSize(width: 350, height: 102))
    }

    private func render(_ view: some View, name: String, size: CGSize) throws {
        let framed = view.frame(width: size.width, height: size.height).padding(16).background(.black)
            .foregroundStyle(.white).environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: framed)
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: CGSize(width: size.width + 32, height: size.height + 32)),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        #expect(bitmap.pixelsWide > 0)
        if let directory = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            try bitmap.representation(using: .png, properties: [:])?.write(
                to: URL(filePath: directory).appending(path: "\(name).png"))
        }
    }
}

@MainActor
struct WebAppsTests {
    @Test func theAppsOpenTheirOwnAddresses() throws {
        let defaults = try #require(UserDefaults(suiteName: "WebAppsTests"))
        defaults.removePersistentDomain(forName: "WebAppsTests")
        let addresses = WebApps(defaults: defaults).apps.map(\.address)
        #expect(
            addresses == [
                "https://app.viorim.com/", "https://agents-umber-gamma.vercel.app/",
                "https://holdings-agent.vercel.app/",
            ])
    }

    @Test func timesAreInIndiaStandardTime() {
        let noonUTC = Date(timeIntervalSince1970: 1_793_102_400)  // 27 Oct 2026, 12:00 UTC
        #expect(IST.time(noonUTC) == "17:30" && IST.date(noonUTC) == "27 Oct 2026")
    }
}

struct AppsSummaryTests {
    @Test func aSummaryReadsTakeawaysAndTodosInEitherShape() throws {
        let json = #"{"takeaways":["NAV up 2%"],"todos":["Call Ravi",{"title":"Send deck","done":true}]}"#
        let summary = try JSONDecoder().decode(AppsFeature.Summary.self, from: Data(json.utf8))
        #expect(summary.takeaways == ["NAV up 2%"])
        #expect(
            summary.todos.map(\.title) == ["Call Ravi", "Send deck"] && summary.todos.map(\.done) == [false, true])
        #expect(
            AppsFeature.summaryURL("https://holdings-agent.vercel.app/")?.absoluteString
                == "https://holdings-agent.vercel.app/api/notch")
    }
}

@MainActor
struct HomeTileOrderTests {
    @Test func aStoredOrderKeepsKnownTilesAndAddsMissingOnes() {
        let order = HomeFeature.order(["takeaways", "bogus", "claude", "claude"])
        #expect(order == [.takeaways, .claude, .focus, .calendar])
        #expect(HomeFeature.order(nil) == HomeFeature.TileKind.allCases)
    }
}
