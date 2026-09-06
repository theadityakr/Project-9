# Caffeine (DIY)

A minimal menu bar app that keeps your Mac awake — same idea as the original
Caffeine app, built from scratch in ~200 lines of Swift.

**How it works:** the whole app boils down to one system API,
[`IOPMAssertionCreateWithName`](https://developer.apple.com/documentation/iokit/1557134-iopmassertioncreatewithname),
which registers a "power management assertion" telling macOS not to sleep
the display. Everything else — the menu bar icon, the click handling, the
timeout menu — is just UI wrapped around that one call.

## What you get

- A coffee cup in the menu bar (empty = off, full = on)
- **Left-click** the icon to toggle instantly
- **Right-click** (or Control-click) for a menu with timed durations
  (15 min / 30 min / 1 hr / 2 hr / 4 hr) and Quit
- No Dock icon, no app switcher entry — pure menu bar utility

## Running it

You'll need a Mac with Xcode (or the Xcode Command Line Tools) installed —
this can't be built or tested outside macOS since it depends on AppKit and
IOKit, which is why I'm handing you the source rather than a working binary.

**Fastest way to try it, from Terminal:**
```bash
cd CaffeineApp
swift run
```
The cup icon should appear in your menu bar within a couple seconds.

**In Xcode:** open `Package.swift` directly (File > Open), then hit Run.
Xcode will treat it as a normal app target you can build and debug.

**To get a real double-clickable app** (so you can drag it to Applications
or add it to Login Items):
```bash
./scripts/build-app.sh
```
This produces `Caffeine.app` in the project folder.

## Project layout

```
CaffeineApp/
├── Package.swift              # SPM manifest — no Xcode project file needed
├── Sources/Caffeine/
│   └── main.swift              # the entire app
└── scripts/
    └── build-app.sh             # wraps the built binary into a .app bundle
```

## Notes on the implementation

- **`kIOPMAssertionTypeNoDisplaySleep`** keeps the *display* from sleeping
  (screen stays on, no dimming, no screensaver) — this is what the original
  Caffeine does. If you'd rather keep the *system* awake while letting the
  display sleep normally (e.g. for background downloads), swap in
  `kIOPMAssertionTypePreventUserIdleSystemSleep` instead.
- The activation policy (`.accessory`) is set in code rather than via
  `Info.plist`'s `LSUIElement`, since a plain SPM executable has no
  Info.plist until you bundle it. The build script adds `LSUIElement` to the
  bundle's Info.plist too, so it stays out of the Dock either way you run it.
- Icons use SF Symbols (`cup.and.saucer` / `cup.and.saucer.fill`) as
  template images, so they'll automatically adapt to light/dark menu bars
  and Control Center-style tinting.

## Ideas if you want to take it further

- **Launch at login** — use
  [`SMAppService.mainApp`](https://developer.apple.com/documentation/servicemanagement/smappservice)
  (macOS 13+) and add a checkbox menu item that calls `.register()` /
  `.unregister()`.
- **Preferences window** — a small `NSWindow` or SwiftUI `Settings` scene
  for things like "default timeout" or "activate on launch," backed by
  `UserDefaults`.
- **Custom icon** — swap the SF Symbol lookup in `updateIcon()` for your own
  `.pdf`/`.png` template images if you want a distinctive cup design instead
  of the system one.
- **Global keyboard shortcut** — add a hotkey (e.g. via the `HotKey`
  package) to toggle without touching the menu bar at all.

Happy to build out any of these with you — just say which one.
