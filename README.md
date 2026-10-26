# NotchDeck

A personal notch dashboard for a MacBook, built on
[ILoveNotch](https://github.com/niyamvora/ILoveNotch) by Niyam Vora (MIT). Everything ILoveNotch
does is still here: media, sound, shelf, clipboard, calendar, tasks, notes, shortcuts, timer,
network, mirror, AI usage and agents. NotchDeck adds:

- **Home**: hover the notch and a dashboard opens with Claude Code, a Pomodoro timer, today's
  calendar and your Mac's battery and energy. Weather, a light/dark switch and Switch User sit
  along the bottom. Click a tile for a quick peek: a month calendar, battery health and the apps
  using the most energy, Focus shortcuts, every Claude session, the forecast.
- **Claude Code progress**: working / waiting for you / compacting / ready, with a progress bar
  from Claude's own to-do list, the current step and how long it's been working. The closed notch
  shows a progress ring next to what's playing.
- **System**: battery health, cycle count, temperature, charging watts, the apps using the most
  energy right now, and Bluetooth keyboard/mouse/trackpad batteries.
- **Pomodoro**: 25-minute focus sessions, 5-minute breaks, a long break after four, with a chime and
  a notification at each switch. It keeps time while the Mac sleeps.
- **Weather**: free forecast from [Open-Meteo](https://open-meteo.com) for your location (or a city
  you type), no account or API key.

## Build

Needs **macOS 15.6+** and **Xcode 26** (the project uses Swift 6.2).

```sh
brew install xcodegen
make setup
make run          # or: make install  → /Applications/NotchDeck.app
```

NotchDeck has its own name and bundle ID (`com.amankothari.notchdeck`), so it can run beside a
real ILoveNotch. It never updates itself from ILoveNotch's releases. "Update NotchDeck" in the menu
bar rebuilds from your checkout instead.

## Keeping up with ILoveNotch

```sh
git fetch upstream
git merge upstream/main     # NotchDeck's own code lives in Sources/NotchDeck, so conflicts stay small
```

## Licence

MIT. See [LICENSE](LICENSE) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). The original
ILoveNotch README is kept at [docs/upstream-README.md](docs/upstream-README.md).
