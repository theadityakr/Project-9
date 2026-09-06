import SwiftUI
import AppKit

// MARK: - CaffeineModule

/// Module adapter that bridges the standalone Caffeine menu-bar daemon
/// with Project-9's `AppModule` protocol.
///
/// The module's SwiftUI view provides a rich control surface for the
/// caffeine feature — mirroring (and extending) the menu-bar interface
/// so it can be used without touching the menu bar at all.
final class CaffeineModule: AppModule {

    // MARK: AppModule identity

    let id          = "com.project9.caffeine"
    let name        = "Caffeine"
    let icon        = "cup.and.saucer.fill"
    let description = "Keep your Mac awake on demand"
    let version     = "1.1"

    // MARK: Shared state (observed by the SwiftUI view)

    let caffeineState = CaffeineState()

    // MARK: Lifecycle

    func start() {
        // Nothing to do — CaffeineState manages itself lazily.
    }

    func stop() {
        caffeineState.deactivate()
    }

    // MARK: View

    func view() -> AnyView {
        AnyView(CaffeineModuleView(state: caffeineState))
    }
}

// MARK: - CaffeineState (ObservableObject shared between module & view)

@MainActor
final class CaffeineState: ObservableObject {

    // MARK: Published state

    @Published private(set) var isActive   = false
    @Published private(set) var activeUntil: Date?
    @Published private(set) var remaining: String = ""

    // MARK: Private

    private var assertionID: IOPMAssertionID = 0
    private var timeoutTimer: Timer?
    private var countdownTimer: Timer?

    // MARK: - API

    func activate(duration: TimeInterval?) {
        deactivate()                           // release any previous assertion

        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Requested by user via Project-9 Caffeine" as CFString,
            &assertionID
        )
        guard result == kIOReturnSuccess else { return }

        isActive = true

        if let duration {
            activeUntil = Date().addingTimeInterval(duration)
            timeoutTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.deactivate() }
            }
        } else {
            activeUntil = nil
        }

        startCountdown()
    }

    func deactivate() {
        if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
        }
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        stopCountdown()
        isActive    = false
        activeUntil = nil
        remaining   = ""
    }

    func toggle() {
        isActive ? deactivate() : activate(duration: nil)
    }

    // MARK: - Countdown

    private func startCountdown() {
        stopCountdown()
        updateRemaining()
        guard activeUntil != nil else { return }
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateRemaining() }
        }
    }

    private func stopCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }

    private func updateRemaining() {
        guard let until = activeUntil else {
            remaining = ""
            return
        }
        let secs = max(0, until.timeIntervalSinceNow)
        if secs < 60 {
            remaining = "< 1 min left"
        } else {
            let mins = Int(secs / 60)
            remaining = mins < 60 ? "\(mins) min left" : "\(mins / 60)h \(mins % 60)m left"
        }
    }
}

// MARK: - Needs IOKit import in this file

import IOKit.pwr_mgt

// MARK: - CaffeineModuleView

struct CaffeineModuleView: View {
    @ObservedObject var state: CaffeineState

    private let durations: [(label: String, seconds: TimeInterval)] = [
        ("15 minutes",  15 * 60),
        ("30 minutes",  30 * 60),
        ("1 hour",      60 * 60),
        ("2 hours",   2 * 60 * 60),
        ("4 hours",   4 * 60 * 60),
        ("8 hours",   8 * 60 * 60),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                statusCard
                controlsCard
                infoCard
            }
            .padding(28)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Status Card

    private var statusCard: some View {
        VStack(spacing: 20) {
            // Animated cup icon
            ZStack {
                Circle()
                    .fill(
                        state.isActive
                            ? LinearGradient(colors: [.orange, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [Color(.windowBackgroundColor), Color(.separatorColor)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 100, height: 100)
                    .shadow(
                        color: state.isActive ? .orange.opacity(0.45) : .clear,
                        radius: state.isActive ? 20 : 0
                    )
                    .animation(.spring(duration: 0.4), value: state.isActive)

                Image(systemName: state.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(state.isActive ? .white : .secondary)
                    .animation(.spring(duration: 0.3), value: state.isActive)
                    .symbolEffect(.bounce, value: state.isActive)
            }

            VStack(spacing: 6) {
                Text(state.isActive ? "Caffeine is Active" : "Caffeine is Off")
                    .font(.system(size: 22, weight: .bold))
                    .contentTransition(.numericText())
                    .animation(.default, value: state.isActive)

                Group {
                    if !state.remaining.isEmpty {
                        Label(state.remaining, systemImage: "timer")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.orange)
                    } else if state.isActive {
                        Label("Active indefinitely", systemImage: "infinity")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Your display will sleep normally")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .animation(.default, value: state.isActive)
            }

            // Main toggle button
            Button(action: { state.toggle() }) {
                Text(state.isActive ? "Deactivate" : "Activate")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 160, height: 40)
                    .foregroundStyle(.white)
                    .background(
                        state.isActive
                            ? LinearGradient(colors: [.red.opacity(0.8), .red], startPoint: .top, endPoint: .bottom)
                            : LinearGradient(colors: [.orange, .orange.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: (state.isActive ? Color.red : Color.orange).opacity(0.3), radius: 6, y: 3)
            }
            .buttonStyle(.plain)
            .animation(.spring(duration: 0.3), value: state.isActive)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Controls Card

    private var controlsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Activate For…")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                spacing: 10
            ) {
                ForEach(durations, id: \.label) { option in
                    DurationButton(label: option.label) {
                        state.activate(duration: option.seconds)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Info Card

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("How it works", systemImage: "info.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("""
                Caffeine registers a **power assertion** with macOS (`IOPMAssertionCreateWithName`) that prevents the display from dimming or sleeping. \
                The assertion is automatically released when you deactivate, set a timer that expires, or quit the app.
                """)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - DurationButton

private struct DurationButton: View {
    let label: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(hover ? Color.accentColor.opacity(0.15) : Color(.separatorColor).opacity(0.3))
                .foregroundStyle(hover ? Color.accentColor : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(hover ? Color.accentColor.opacity(0.4) : .clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
    }
}
