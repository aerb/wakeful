import AppKit
import SwiftUI
import WakefulCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let notifier = Notifier()
    private lazy var model = AppModel(
        controller: SessionController(
            preventer: IOKitSleepPreventer(), lidControl: PmsetLidControl(), store: .default),
        hasLidPermission: { PmsetLidControl().hasPermission() },
        settingsStore: SettingsStore(),
        notifier: notifier)

    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var statusSymbol: String?
    private var settingsWindow: NSWindow?
    private var signalSources: [DispatchSourceSignal] = []

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
            if let dir = ProcessInfo.processInfo.environment["WAKEFUL_SNAPSHOT_DIR"] {
                Snapshots.render(to: URL(fileURLWithPath: dir))
                exit(0)
            }
        #endif

        if let other = otherRunningInstance() {
            other.activate()
            NSApp.terminate(nil)
            return
        }

        model.onSessionChange = { [weak self] in self?.updateStatusItem() }
        model.onOpenSettings = { [weak self] in self?.showSettings() }
        model.recoverStaleSession()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        }
        updateStatusItem()

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        notifier.requestAuthorization()
        observeSystemEvents()
        handleTerminationSignals()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop(.appQuit)
    }

    private func otherRunningInstance() -> NSRunningApplication? {
        guard let id = Bundle.main.bundleIdentifier else { return nil }
        return NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    }

    private func observeSystemEvents() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.willPowerOffNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let reason: EndReason = note.name == NSWorkspace.willSleepNotification ? .systemSleep : .appQuit
                MainActor.assumeIsolated { self?.model.stop(reason) }
            }
        }
    }

    /// Reverts on `kill` and Ctrl-C too, not just on a normal quit.
    private func handleTerminationSignals() {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.model.stop(.appQuit) }
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    // MARK: - Status item and popover

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let symbol: String
        switch model.session?.mode {
        case nil: symbol = "cup.and.saucer"
        case .awake: symbol = "cup.and.saucer.fill"
        case .awakeLidClosed: symbol = "cup.and.heat.waves.fill"
        }
        // This runs every second during a session; only swap the image when the mode changes.
        if symbol != statusSymbol {
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Wakeful")
            image?.isTemplate = true
            button.image = image
            statusSymbol = symbol
        }

        if let session = model.session {
            let left = DurationFormat.countdown(model.remaining)
            button.title = " \(left)"
            button.toolTip = "\(session.mode.displayName): \(left) left"
        } else {
            button.title = ""
            button.toolTip = "Wakeful: off"
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            model.refresh()
            // Built on open and dropped on close, so a closed panel does no SwiftUI work while
            // the countdown ticks.
            popover.contentViewController = NSHostingController(rootView: PopoverView(model: model))
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            NSApp.activate()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        popover.contentViewController = nil
    }

    // MARK: - Settings window

    private func showSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
            window.title = "Wakeful Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        model.refresh()
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
