import SwiftUI

@main
struct Project9App: App {
    @StateObject private var moduleManager: ModuleManager

    init() {
        let manager = ModuleManager()
        manager.register(CaffeineModule())
        _moduleManager = StateObject(wrappedValue: manager)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(moduleManager)
                .onAppear {
                    moduleManager.startAll()
                }
        }
        .commands {
            // Remove default "New Window" command — this is a single-window utility host.
            CommandGroup(replacing: .newItem) {}
        }
    }
}
