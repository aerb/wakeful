import Foundation
import Observation
import ServiceManagement
import WakefulCore

/// Everything the popover and Settings window show, and the actions they can take.
@MainActor
@Observable
final class AppModel {
    private(set) var session: Session?
    private(set) var now = Date()
    private(set) var lidPermitted = false
    private(set) var launchAtLogin = false
    var errorMessage: String?

    var selectedMode: SessionMode = .awake
    var selectedDuration: TimeInterval

    var settings: WakefulSettings {
        didSet {
            settingsStore.save(settings)
            if settings.defaultDuration != oldValue.defaultDuration {
                selectedDuration = settings.defaultDuration
            }
        }
    }

    @ObservationIgnored var onSessionChange: (() -> Void)?
    @ObservationIgnored var onOpenSettings: (() -> Void)?

    @ObservationIgnored private let controller: SessionController
    @ObservationIgnored private let hasLidPermission: () -> Bool
    @ObservationIgnored private let settingsStore: SettingsStore
    @ObservationIgnored private let notifier: Notifier
    @ObservationIgnored private var ticker: Timer?

    init(
        controller: SessionController, hasLidPermission: @escaping () -> Bool, settingsStore: SettingsStore,
        notifier: Notifier
    ) {
        self.controller = controller
        self.hasLidPermission = hasLidPermission
        self.settingsStore = settingsStore
        self.notifier = notifier
        let settings = settingsStore.load()
        self.settings = settings
        self.selectedDuration = settings.defaultDuration
        controller.onEvent = { [weak self] event in self?.handle(event) }
        refresh()
    }

    // MARK: - Derived state

    var remaining: TimeInterval { session?.remaining(at: now) ?? 0 }

    /// Share of the session still to run, from 1 down to 0.
    var fractionRemaining: Double {
        guard let session else { return 0 }
        let total = session.expiresAt.timeIntervalSince(session.startedAt)
        return total > 0 ? min(1, max(0, remaining / total)) : 0
    }

    var canExtend: Bool {
        session != nil && remaining + 1 < (Presets.durations.max() ?? 0)
    }

    // MARK: - Actions

    /// Re-reads things that can change outside the app. Called when the popover opens.
    func refresh() {
        lidPermitted = hasLidPermission()
        launchAtLogin = SMAppService.mainApp.status == .enabled
        if !lidPermitted && selectedMode == .awakeLidClosed {
            selectedMode = .awake
        }
        now = Date()
    }

    func start() {
        errorMessage = nil
        do {
            try controller.start(
                mode: selectedMode, duration: selectedDuration, keepDisplayAwake: settings.keepDisplayAwake,
                snapshot: PowerMonitor.snapshot(), policy: settings.cutoffPolicy)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop(_ reason: EndReason = .userStopped) {
        errorMessage = nil
        controller.stop(reason)
    }

    func extend() {
        controller.extend(by: Presets.extendStep)
    }

    func recoverStaleSession() {
        if controller.recoverStaleSession() {
            notifier.post(
                title: "Lid-closed awake turned off",
                body: "An earlier Wakeful session was still holding the Mac awake.")
        }
    }

    func openSettings() {
        onOpenSettings?()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        errorMessage = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            errorMessage = "Couldn't change launch at login: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: - Session events

    private func handle(_ event: SessionEvent) {
        switch event {
        case .started, .extended:
            startTicker()
        case .ended(_, let reason):
            stopTicker()
            if reason.isWorthNotifying {
                notifier.post(title: "Wakeful turned off", body: reason.message)
            }
        case .revertFailed(let detail):
            notifier.post(
                title: "Couldn't turn off lid-closed awake",
                body: "\(detail) The watchdog will keep retrying. To fix it now, run: sudo pmset -a disablesleep 0")
        }
        session = controller.session
        now = Date()
        onSessionChange?()
    }

    private func startTicker() {
        guard ticker == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // Lets macOS coalesce the wakeup with others.
        timer.tolerance = 0.2
        // `.common` keeps the countdown running while the popover is being interacted with.
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        now = Date()
        controller.tick(snapshot: PowerMonitor.snapshot(), policy: settings.cutoffPolicy)
        onSessionChange?()
    }
}
