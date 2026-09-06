import Cocoa
import IOKit.pwr_mgt
import ServiceManagement
import UserNotifications

// MARK: - Entry point
// Runs as a plain SPM executable (no .app bundle required for development).
// Activation policy is set in code; the build script also sets LSUIElement
// in Info.plist so it stays out of the Dock either way.

let app      = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: UI
    private var statusItem: NSStatusItem!

    // MARK: Power assertion state
    private var assertionID: IOPMAssertionID = 0
    private var isActive      = false
    private var timeoutTimer: Timer?
    private var countdownTimer: Timer?
    private var activeUntil: Date?

    // MARK: Preferences keys
    private enum Prefs {
        static let defaultDuration = "defaultDurationSeconds"   // TimeInterval? (0 = indefinite)
        static let activateOnLaunch = "activateOnLaunch"        // Bool
        static let launchAtLogin    = "launchAtLogin"           // Bool (reflected, not stored by us)
    }

    // MARK: Duration options
    private let durationOptions: [(title: String, seconds: TimeInterval)] = [
        ("15 Minutes",  15 * 60),
        ("30 Minutes",  30 * 60),
        ("1 Hour",      60 * 60),
        ("2 Hours",   2 * 60 * 60),
        ("4 Hours",   4 * 60 * 60),
        ("8 Hours",   8 * 60 * 60),
    ]

    // MARK: - Application lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        requestNotificationPermission()

        // Auto-activate if the user set a default duration preference
        if UserDefaults.standard.bool(forKey: Prefs.activateOnLaunch) {
            let savedSeconds = UserDefaults.standard.double(forKey: Prefs.defaultDuration)
            let duration: TimeInterval? = savedSeconds > 0 ? savedSeconds : nil
            startPreventingSleep(timeout: duration)
        } else {
            // Release any stale assertion that survived a previous crash
            stopPreventingSleep()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopPreventingSleep()
    }

    // MARK: - Status item setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        updateIcon()
    }

    // MARK: - Notification permission

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: - Click handling

    @objc private func statusItemClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent else { return }
        let isRight   = event.type == .rightMouseUp
        let isControl = event.type == .leftMouseUp && event.modifierFlags.contains(.control)
        if isRight || isControl { showMenu() } else { toggle() }
    }

    private func showMenu() {
        guard let button = statusItem.button else { return }
        let menu = buildMenu()
        menu.popUp(positioning: nil,
                   at: NSPoint(x: 0, y: button.bounds.height + 5),
                   in: button)
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        // ── Toggle ──────────────────────────────────────────────────────────
        let toggleTitle = isActive ? "Deactivate" : "Activate"
        menu.addItem(withTitle: toggleTitle, action: #selector(toggle), keyEquivalent: "")

        // Status / countdown line
        if isActive {
            let statusText: String
            if let remaining = formattedRemaining() {
                statusText = "Active — \(remaining)"
            } else {
                statusText = "Active indefinitely"
            }
            let info = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
            info.isEnabled = false
            menu.addItem(info)
        }

        menu.addItem(.separator())

        // ── Timed activation ────────────────────────────────────────────────
        let timeoutMenu = NSMenu()
        for opt in durationOptions {
            let item = NSMenuItem(title: opt.title,
                                  action: #selector(activateWithTimeout(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = opt.seconds
            timeoutMenu.addItem(item)
        }
        let timeoutItem = NSMenuItem(title: "Activate For…", action: nil, keyEquivalent: "")
        timeoutItem.submenu = timeoutMenu
        menu.addItem(timeoutItem)

        menu.addItem(.separator())

        // ── Preferences ─────────────────────────────────────────────────────
        let prefsMenu = NSMenu()

        // Activate on launch toggle
        let activateOnLaunchItem = NSMenuItem(title: "Activate on Launch",
                                              action: #selector(toggleActivateOnLaunch),
                                              keyEquivalent: "")
        activateOnLaunchItem.target = self
        activateOnLaunchItem.state = UserDefaults.standard.bool(forKey: Prefs.activateOnLaunch) ? .on : .off
        prefsMenu.addItem(activateOnLaunchItem)

        // Default duration sub-sub-menu
        let defaultDurMenu = NSMenu()
        let indefiniteItem = NSMenuItem(title: "Indefinitely",
                                        action: #selector(setDefaultDuration(_:)),
                                        keyEquivalent: "")
        indefiniteItem.target = self
        indefiniteItem.representedObject = TimeInterval(0)
        indefiniteItem.state = UserDefaults.standard.double(forKey: Prefs.defaultDuration) == 0 ? .on : .off
        defaultDurMenu.addItem(indefiniteItem)

        for opt in durationOptions {
            let item = NSMenuItem(title: opt.title,
                                  action: #selector(setDefaultDuration(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = opt.seconds
            item.state = UserDefaults.standard.double(forKey: Prefs.defaultDuration) == opt.seconds ? .on : .off
            defaultDurMenu.addItem(item)
        }
        let defaultDurItem = NSMenuItem(title: "Default Duration", action: nil, keyEquivalent: "")
        defaultDurItem.submenu = defaultDurMenu
        prefsMenu.addItem(defaultDurItem)

        // Launch at Login (macOS 13+)
        if #available(macOS 13.0, *) {
            let lalItem = NSMenuItem(title: "Launch at Login",
                                     action: #selector(toggleLaunchAtLogin),
                                     keyEquivalent: "")
            lalItem.target = self
            lalItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
            prefsMenu.addItem(lalItem)
        }

        let prefsItem = NSMenuItem(title: "Preferences", action: nil, keyEquivalent: "")
        prefsItem.submenu = prefsMenu
        menu.addItem(prefsItem)

        menu.addItem(.separator())

        // ── Quit ────────────────────────────────────────────────────────────
        menu.addItem(withTitle: "Quit Caffeine", action: #selector(quit), keyEquivalent: "q")

        // Ensure all items without an explicit target use self
        for item in menu.items where item.action != nil && item.target == nil {
            item.target = self
        }
        return menu
    }

    // MARK: - Actions

    @objc private func toggle() {
        if isActive { stopPreventingSleep() } else { startPreventingSleep(timeout: nil) }
    }

    @objc private func activateWithTimeout(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? TimeInterval else { return }
        startPreventingSleep(timeout: seconds)
    }

    @objc private func toggleActivateOnLaunch() {
        let current = UserDefaults.standard.bool(forKey: Prefs.activateOnLaunch)
        UserDefaults.standard.set(!current, forKey: Prefs.activateOnLaunch)
    }

    @objc private func setDefaultDuration(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? TimeInterval else { return }
        UserDefaults.standard.set(seconds, forKey: Prefs.defaultDuration)
    }

    @objc private func toggleLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            do {
                let service = SMAppService.mainApp
                if service.status == .enabled {
                    try service.unregister()
                } else {
                    try service.register()
                }
            } catch {
                NSLog("Caffeine: launch-at-login toggle failed: \(error)")
            }
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - Power assertion

    private func startPreventingSleep(timeout: TimeInterval?) {
        releaseAssertionIfNeeded()
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        stopCountdown()

        let reason = "Requested by user via Caffeine" as CFString
        let result  = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &assertionID
        )

        guard result == kIOReturnSuccess else {
            NSLog("Caffeine: failed to create power assertion (IOReturn \(result))")
            isActive = false
            updateIcon()
            return
        }

        isActive = true

        if let timeout {
            activeUntil = Date().addingTimeInterval(timeout)
            timeoutTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
                self?.stopPreventingSleep()
                self?.sendExpiryNotification()
            }
        } else {
            activeUntil = nil
        }

        startCountdown()
        updateIcon()
    }

    private func stopPreventingSleep() {
        releaseAssertionIfNeeded()
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        stopCountdown()
        activeUntil = nil
        isActive    = false
        updateIcon()
    }

    private func releaseAssertionIfNeeded() {
        if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
        }
    }

    // MARK: - Countdown timer

    private func startCountdown() {
        stopCountdown()
        guard activeUntil != nil else { return }
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.updateIcon()
        }
    }

    private func stopCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }

    private func formattedRemaining() -> String? {
        guard let until = activeUntil else { return nil }
        let secs = max(0, until.timeIntervalSinceNow)
        if secs < 60 { return "< 1 min" }
        let mins = Int(secs / 60)
        return mins < 60 ? "\(mins) min" : "\(mins / 60)h \(mins % 60)m"
    }

    // MARK: - Expiry notification

    private func sendExpiryNotification() {
        let content         = UNMutableNotificationContent()
        content.title       = "Caffeine Deactivated"
        content.body        = "Your timed Caffeine session has ended. Your display will sleep normally again."
        content.sound       = .default

        let request = UNNotificationRequest(
            identifier: "caffeine.expiry.\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil   // deliver immediately
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error { NSLog("Caffeine: notification error: \(error)") }
        }
    }

    // MARK: - Icon

    private func updateIcon() {
        let symbol = isActive ? "cup.and.saucer.fill" : "cup.and.saucer"
        let image  = NSImage(systemSymbolName: symbol, accessibilityDescription: "Caffeine")
        image?.isTemplate = true
        statusItem.button?.image = image

        // Show remaining time as the button tooltip
        if let remaining = formattedRemaining() {
            statusItem.button?.toolTip = "Caffeine — \(remaining) left"
        } else if isActive {
            statusItem.button?.toolTip = "Caffeine — active"
        } else {
            statusItem.button?.toolTip = "Caffeine — off"
        }
    }
}

