# OpenNotch

A small macOS utility that turns the MacBook notch into a drop zone, a clipboard history, and a
terminal-style activity heatmap. Written from scratch in Swift (SwiftUI + AppKit), no dependencies.

On Macs without a notch it shows a small pill at the top-center of the screen instead.

## Download

Download [OpenNotch-0.1.0-macos.zip](https://github.com/terri-yaki/opennotch/releases/download/v0.1.0/OpenNotch-0.1.0-macos.zip) from the [v0.1.0 release](https://github.com/terri-yaki/opennotch/releases/tag/v0.1.0). Unzip it, then open OpenNotch.app.

OpenNotch is a menu-bar app and has no Dock icon. It needs macOS 14 or later.

This build is ad-hoc signed. A copy downloaded from GitHub is quarantined, and Gatekeeper blocks it, so double-click will not open it. After unzip, if macOS blocks it, open System Settings → Privacy & Security → Open Anyway, or right-click OpenNotch.app and choose Open. If that is not enough:

```bash
xattr -dr com.apple.quarantine OpenNotch.app
```

## Features

- **Shelf**: drag files toward the notch and the shelf expands. Drop to park them, drag them back
  out later, double-click to open, right-click for Reveal in Finder / Copy Path / Remove.
  Only file references are stored; nothing is copied.
- **Clipboard**: history of copied text (40 items, in memory only). Click to copy again, pin the
  ones you want to keep. Items flagged as concealed or transient by password managers are skipped,
  and history can be paused from the menu bar.
- **Activity**: scroll through full-page heatmaps (36 weeks): files shelved and clips copied
  (theme color); Claude Code, Codex and Grok tokens per day in each tool's brand color, read
  from their local logs, with Claude's 5-hour window and Codex's 5h/weekly limits; and a live
  per-core CPU heatmap with CPU and memory meters.
- **Now Playing**: Apple Music artwork, progress and controls, with time-synced lyrics that
  scroll and highlight as the song plays. Album art shows in the notch while music plays.
  Lyrics come from [LRCLIB](https://lrclib.net) (only title, artist, album and duration are
  sent), falling back to lyrics embedded in the track. The first time, macOS asks to let
  OpenNotch control Music.
- **Battery**: plug in and the notch widens to show a battery filling up with liquid; a small
  liquid battery gauge sits in the panel header.
- **Theme**: pick a color (purple by default, or rainbow) from the dots in the Activity tab;
  it tints the heatmap and the pet.
- **Liquid pet**: a colorful gooey blob living beside the notch. Its eyes and body follow your
  cursor, fast mouse motion stirs it up, it bounces when you hover or drop files, and it falls
  asleep after 30 seconds of stillness. Toggle it from the menu bar.
- **Half-sphere panel**: the notch grows into a pure-black half sphere (it stays a semicircle
  the whole way through the animation); buttons and items are gently pulled toward the pointer.
- Menu bar item: pin the shelf open, pause clipboard history, launch at login, clear data.

Hover the notch for a moment (or drag files to it) to open. Move away to close, or pin it open
with the pin button.

## Build and run

Requires macOS 14 (Sonoma) or later and Xcode or the Command Line Tools.

```bash
./build.sh
open build/OpenNotch.app
```

The app is ad-hoc signed, so the first time you may need to right-click it and choose Open.
You can also open `Package.swift` in Xcode and run from there.

## Project layout

```
Sources/OpenNotch/
  OpenNotchApp.swift      entry point, menu bar item
  NotchPanel.swift        borderless panel that floats over the menu bar / notch
  NotchController.swift   geometry, hover and drag detection, expand/collapse
  NotchState.swift        shared UI state
  NotchRootView.swift     SwiftUI shell, tabs, drop target
  ShelfStore/ShelfView    file shelf
  ClipboardStore/View     clipboard history
  ActivityStore.swift     per-day counts (UserDefaults)
  HeatmapView.swift       animated terminal heatmap (TimelineView + Canvas)
  PetModel/PetView        liquid pet: spring physics + metaball rendering
  Magnetic.swift          cursor tracking and the .magnetic() modifier
  Theme.swift             color themes and the swatch picker
  MusicStore/MusicView    Apple Music now playing (AppleScript) and LRCLIB lyrics
  UsageStore.swift        AI tool token usage from local CLI logs (cached per file)
  SystemMonitor.swift     per-core CPU and memory sampling
  BatteryMonitor.swift    IOKit power-source notifications
  LiquidBattery.swift     the liquid battery icon
```

## Ideas to extend it

- Global hotkey to toggle the shelf
- Image and file clipboard entries
- Media controls and volume/brightness overlays in the notch
- Tweak the wave in `HeatmapView.swift` (speed `1.7`, spatial frequency `0.30` / `0.22`, hue range `0.07`)

## Contributing

Issues, discussions, and pull requests are open. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT. This is an independent implementation inspired by the general idea of notch shelves;
it does not use code from any other app.

OpenNotch is made by terriyaki.
