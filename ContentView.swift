import SwiftUI

struct ContentView: View {
    @EnvironmentObject var moduleManager: ModuleManager
    @State private var selectedModuleID: String?

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            sidebarView
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            detailView
        }
        .frame(minWidth: 780, minHeight: 520)
        .onAppear {
            if selectedModuleID == nil {
                selectedModuleID = moduleManager.modules.first?.id
            }
        }
    }

    // MARK: - Sidebar

    private var sidebarView: some View {
        List(moduleManager.modules, id: \.id, selection: $selectedModuleID) { module in
            ModuleSidebarRow(module: module)
                .tag(module.id)
        }
        .listStyle(.sidebar)
        .navigationTitle("Project-9")
        .navigationSubtitle("\(moduleManager.modules.count) module\(moduleManager.modules.count == 1 ? "" : "s")")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: {}) {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Settings")
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailView: some View {
        if let selected = moduleManager.modules.first(where: { $0.id == selectedModuleID }) {
            VStack(spacing: 0) {
                ModuleDetailHeader(module: selected)
                Divider()
                selected.view()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            EmptyStateView()
        }
    }
}

// MARK: - Sidebar Row

private struct ModuleSidebarRow: View {
    let module: any AppModule

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: module.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(
                    LinearGradient(
                        colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .shadow(color: Color.accentColor.opacity(0.4), radius: 3, y: 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(module.name)
                    .font(.system(size: 13, weight: .medium))
                if !module.description.isEmpty {
                    Text(module.description)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Detail Header

private struct ModuleDetailHeader: View {
    let module: any AppModule

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: module.icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(
                    LinearGradient(
                        colors: [Color.accentColor, Color.accentColor.opacity(0.65)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: Color.accentColor.opacity(0.35), radius: 5, y: 3)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(module.name)
                        .font(.system(size: 18, weight: .bold))
                    if !module.version.isEmpty {
                        Text("v\(module.version)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary)
                            .clipShape(Capsule())
                    }
                }
                if !module.description.isEmpty {
                    Text(module.description)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.bar)
    }
}

// MARK: - Empty State

private struct EmptyStateView: View {
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.08))
                    .frame(width: 90, height: 90)
                    .scaleEffect(pulse ? 1.12 : 1.0)
                    .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: pulse)

                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(Color.accentColor)
            }

            Text("No Module Selected")
                .font(.system(size: 18, weight: .semibold))

            Text("Choose a module from the sidebar to get started.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { pulse = true }
    }
}
