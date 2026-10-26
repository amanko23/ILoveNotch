# NotchDeck: build it on your Mac

The code was written in a Linux container with **no Swift compiler**, so it has never been
built. The logic is covered by tests and the Claude Code hook script was exercised under
`dash` and `bash --posix`, but expect a short round of compile fixes on the first build. The
prompt at the bottom hands that round to Claude Code.

You need: macOS 15.6+ (you have 15.8.1), Xcode 26, Homebrew, and the GitHub CLI.

## 1. Get the code into your own fork

```sh
# Fork upstream as "notchdeck" (or fork on github.com and clone it)
gh repo fork niyamvora/ILoveNotch --fork-name notchdeck --clone --remote
cd notchdeck            # origin = your fork, upstream = niyamvora/ILoveNotch

# Bring in the NotchDeck branch: either the bundle or the patches (both are in the handoff folder)
git fetch ~/Downloads/notchdeck.bundle notchdeck:notchdeck   # from the bundle
git checkout notchdeck
#   or:  git checkout -b notchdeck && git am ~/Downloads/notchdeck-patches/*.patch

git submodule update --init --recursive
git push -u origin notchdeck
```

The fork is personal use, so private or public both work. A **public** fork gets free macOS CI
minutes. A private one spends your account's minutes (macOS minutes count 10×).

## 2. Build and run

```sh
brew install xcodegen
make setup
make format     # applies swift-format; the code was hand-formatted, so expect small changes
make test       # unit, snapshot, and performance tests
make run        # Debug build → launches NotchDeck
make install    # when you're happy: Release build into /Applications/NotchDeck.app
```

NotchDeck has its own bundle ID (`com.amankothari.notchdeck`), so it runs beside ILoveNotch if
you have that too. Quit ILoveNotch while you try NotchDeck, or the two notches overlap.

## 3. First launch checklist

1. Hover the notch: it opens on **Home**.
2. **Claude tile → Connect.** This adds hooks to `~/.claude/settings.json` (it backs the file up to
   `~/Library/Application Support/NotchDeck/Backups` first). Start a Claude Code session and give
   it a multi-step task: the tile shows Working, the step, and a progress bar. Approval prompts
   turn it orange. The closed notch shows a ring beside what's playing.
3. **Today tile → Continue** to allow Calendar.
4. **Weather**: allow Location when asked, or type a city in Settings › Home.
5. **Dark/Light** in the footer: macOS asks once to let NotchDeck control System Events.
6. **Switch User**: works as display sleep until you allow Accessibility (Settings › Privacy &
   Security › Accessibility). After that it goes straight to the lock screen.
7. **Focus**: make a shortcut in the Shortcuts app with the "Set Focus" action and put "Focus"
   in its name. It appears in the Focus peek.
8. **Pomodoro**: Start in the Focus tile. The closed notch counts down, and a notification
   arrives at each switch.

Tab row: Home, Media, Calendar, Timer, Agents, System. Everything else (Shelf, Clipboard, Notes,
Sound, …) is one click away behind the grid button. Right-click the tabs to rearrange them.

## 4. What changed, by commit

| Commit | What |
|---|---|
| Fork ILoveNotch as NotchDeck | Name, bundle ID, URL scheme, data folders; Sparkle and the App Store edition removed; `make install` never touches ILoveNotch.app |
| Core hooks | `.home`/`.system` tabs, `Activity.Accessory` (the ring in the closed notch), `NotchEvent.setLastTab`, tabs that start in the drawer |
| Claude Code progress | Hook script records to-do counts, current step, turn start, compacting/ready; Agents tab shows progress |
| NotchDeck module | Home, peeks, System tab, Pomodoro, weather, appearance, Switch User, Focus shortcuts, the closed-notch pill |

Upstream files touched are kept small (see `CLAUDE.md`). Merge ILoveNotch updates with
`git fetch upstream && git merge upstream/main`.

## 5. Prompt for Claude Code on your Mac

Run `claude` in the repository folder and paste:

```text
This is NotchDeck, my personal fork of ILoveNotch. Read CLAUDE.md and docs/notchdeck/handoff.md
first. The `notchdeck` branch was written without a Swift compiler, so it has never been built.
Your job is to get it building and tested on this Mac without changing what it does.

1. Run `sw_vers`, `xcodebuild -version`, `swift --version`. Stop and tell me if macOS < 15.6 or
   Xcode < 26.
2. Run `make setup`, then `make format`, then `make test`. Fix every compile error and failing
   test. Prefer the smallest fix that keeps the intended behaviour; check upstream code in
   Sources/NotchFeatures and Sources/NotchUsage for the patterns that compile under Swift 6
   strict concurrency with warnings as errors. Don't weaken tests to make them pass: if a test's
   expectation is wrong, explain why before changing it.
3. Run `make build CONFIGURATION=Release` and `make licenses`; fix anything they report.
4. Run `SNAPSHOT_DIR=/tmp/notchdeck-snapshots swift test --filter HomeRenderTests`, open the PNGs,
   and fix any clipped or overlapping text in Home, its peeks, or the System tab at both sizes.
5. `make run`, then walk the "First launch checklist" in docs/notchdeck/handoff.md with me.
   Tell me what to click and what you expect to see.
6. Commit the fixes in small commits on `notchdeck` (no new dependencies, no GPL code, keep the
   SPDX headers). Don't push until I've reviewed.

Report: toolchain versions, every fix you made and why, test results, and anything you couldn't
verify.
```

## Known limits

- **Claude progress** comes from Claude's own to-do list (TodoWrite, or the newer task tools).
  Short replies without a list show Working with no bar.
- **Focus** can't be read or set by apps directly, so it goes through your Shortcuts.
- **Energy** covers your own processes. System daemons need root, which NotchDeck doesn't ask for.
- **AirPods** and most third-party Bluetooth devices don't expose their battery to apps.
- **Switch User** has no public API, so it locks the screen (where macOS offers Switch User).
