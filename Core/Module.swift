import SwiftUI

/// A self-contained feature module that can be registered with `ModuleManager`.
protocol AppModule: AnyObject {
    /// Stable, unique identifier (e.g. reverse-DNS string).
    var id: String { get }
    /// Human-readable module name shown in the sidebar.
    var name: String { get }
    /// SF Symbol name used as the sidebar icon.
    var icon: String { get }
    /// One-line description shown as a subtitle in the detail view.
    var description: String { get }
    /// Semver string shown in the module detail header.
    var version: String { get }

    /// Called once when the app launches (after all modules are registered).
    func start()
    /// Called when the app is about to terminate.
    func stop()
    /// Returns the SwiftUI view rendered in the detail pane.
    func view() -> AnyView
}

// MARK: - Default implementations
extension AppModule {
    var description: String { "" }
    var version: String { "" }
}
