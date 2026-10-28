# CLAUDE.md

NotchDeck is a personal fork of [ILoveNotch](https://github.com/niyamvora/ILoveNotch) (MIT) for a
MacBook on macOS 15.6+. It's a native SwiftUI + AppKit notch app built with Xcode 26 (Swift 6.2).

## Build and check

```sh
make setup      # once: XcodeGen + submodules
make run        # Debug build, relaunch
make install    # Release build into /Applications/NotchDeck.app
make test       # swift test (unit + snapshot + performance)
make format     # apply swift-format; `make lint` is what CI enforces
make licenses   # SPDX headers + third-party notices
make check      # everything CI runs
```

The README says macOS 14.6, but the toolchain needs Xcode 26 → **macOS 15.6 or later to build**.
The app itself runs on 14.6+; macOS 26 APIs (Liquid Glass) sit behind `#available`.

## Licence policy (hard rules)

- This project is **MIT**. Never copy code from GPL projects (sk-ruban/notchi is GPL-3.0-only;
  TheBoredTeam/boring.notch and Ebullioscopic/Atoll are GPL-3.0) or from repos with no licence
  (spitfiresb/notch). Ideas and documented behaviour only.
- Code adapted from MIT/BSD/Apache projects (e.g. abizer/wtop MIT, gmr/claude-status BSD-3) must be
  listed in `THIRD_PARTY_NOTICES.md` in the same commit.
- Every Swift file starts with `// SPDX-License-Identifier: MIT`. `make licenses` must pass.
- No new package dependencies without asking.

## Architecture rules

- New NotchDeck code goes in `Sources/NotchDeck` (tests in `Tests/NotchDeckTests`). Keep diffs to
  upstream files small and surgical so `git merge upstream/main` stays easy.
- Every tab is a `NotchFeature` (`Sources/NotchCore/FeatureLifecycle.swift`): do **no** work in
  `.stopped`, only cheap event-driven observers in `.background`, full work in `.foreground`.
  Timers are wall-clock deadlines, never per-second polling while off screen.
- Swift 6 language mode, strict concurrency, warnings are errors. UI types are `@MainActor`.
- The closed notch shows one ongoing activity at a time (`PanelCoordinator.setOngoing`);
  `ClosedPillComposer` merges music, Pomodoro and Claude progress into the `.home` slot.
- User-visible text follows the existing voice: plain, specific, no jargon.

## Claude Code hooks

`Sources/NotchUsage/Agents/AgentHooks.swift` installs opt-in hooks into `~/.claude/settings.json`.
They must never block Claude Code (`async: true`), must always exit 0, and must never record prompt
or code content: only state, project folder, terminal app, pid, the approval message, to-do counts
and the current step label. Only use hook events Claude Code has had for a long time; an unknown
event name can invalidate the user's settings file.

## Privacy

No accounts, no telemetry. Weather calls api.open-meteo.com with coordinates rounded to 0.1°.
The Apps tab asks your own sites (Viorim OS and the agents) for `/api/notch` with their saved
sign-in, only while it is on screen. Nothing else leaves the Mac. Never store or handle passwords (Switch User hands off to the login
window).
