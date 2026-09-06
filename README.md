# Project-9

A modular macOS utility platform. Each feature lives as a self-contained **module**
and is surfaced through a unified sidebar-driven SwiftUI shell.

---

## Architecture

```
Project-9/
├── Core/
│   ├── Module.swift          # AppModule protocol
│   └── ModuleManager.swift   # Registration & lifecycle
├── App/
│   └── CaffeineModule.swift  # AppModule adapter + SwiftUI view
├── Modules/
│   └── Caffeine/             # Standalone SPM package (menu-bar daemon)
│       ├── Package.swift
│       ├── Sources/Caffeine/main.swift
│       └── scripts/build-app.sh
├── ContentView.swift         # Sidebar + detail shell
└── Project9App.swift         # @main entry — registers all modules
```

### How modules work

1. Conform to the `AppModule` protocol (`Core/Module.swift`).
2. Implement `start()` / `stop()` / `view() → AnyView`.
3. Register in `Project9App.init()` via `manager.register(YourModule())`.

That's it — the sidebar entry, icon, description, and version badge appear automatically.

---

## Modules

| Module | Description | Version |
|---|---|---|
| **Caffeine** | Keeps the Mac display awake via an IOPMAssertion | 1.1 |

---

## Adding a new module

```swift
// 1. Create MyModule.swift in App/
final class MyModule: AppModule {
    let id          = "com.project9.mymodule"
    let name        = "My Module"
    let icon        = "star"
    let description = "Does something useful"
    let version     = "1.0"

    func start() { /* setup */ }
    func stop()  { /* teardown */ }
    func view()  -> AnyView { AnyView(MyModuleView()) }
}

// 2. Register it in Project9App.swift
manager.register(MyModule())
```

---

## Building Caffeine as a standalone .app

```bash
cd Modules/Caffeine
./scripts/build-app.sh              # uses git version tag automatically
./scripts/build-app.sh --version 2.0.0   # or pin a version
```

Output lands in `Modules/Caffeine/dist/Caffeine.app`.  
Drag it to `/Applications` or add it to **System Settings › General › Login Items**.

### Running in development

```bash
cd Modules/Caffeine
swift run        # cup icon appears in menu bar immediately
```

---

## Requirements

- macOS 13.0+
- Xcode 15+ or Xcode Command Line Tools

---

## License

MIT