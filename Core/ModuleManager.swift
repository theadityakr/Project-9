import Foundation

@MainActor
final class ModuleManager: ObservableObject {

    @Published private(set) var modules: [any AppModule] = []

    // MARK: - Registration

    /// Register a module. Duplicate IDs are silently ignored.
    func register(_ module: any AppModule) {
        guard !modules.contains(where: { $0.id == module.id }) else { return }
        modules.append(module)
    }

    /// Remove the module with the given id, calling `stop()` first.
    func unregister(id: String) {
        guard let index = modules.firstIndex(where: { $0.id == id }) else { return }
        modules[index].stop()
        modules.remove(at: index)
    }

    // MARK: - Lifecycle

    /// Start all registered modules.
    func startAll() {
        modules.forEach { $0.start() }
    }

    /// Stop all registered modules.
    func stopAll() {
        modules.forEach { $0.stop() }
    }

    // MARK: - Queries

    /// Look up a registered module by id.
    func module(id: String) -> (any AppModule)? {
        modules.first { $0.id == id }
    }
}
