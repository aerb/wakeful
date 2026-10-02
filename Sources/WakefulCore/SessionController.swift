import Foundation

/// Holds a system-wide "don't idle-sleep" assertion.
@MainActor
public protocol IdleSleepPreventing: AnyObject {
    func begin(keepDisplayAwake: Bool) throws
    func end()
}

/// Reads and sets the kernel's `SleepDisabled` flag.
public protocol LidSleepControlling: Sendable {
    func isSleepDisabled() throws -> Bool
    func setSleepDisabled(_ disabled: Bool) throws
}

public enum SessionEvent: Equatable, Sendable {
    case started(Session)
    case extended(Session)
    case ended(Session, EndReason)
    /// The session ended but the lid flag could not be turned off. The record stays
    /// on disk so the watchdog keeps retrying.
    case revertFailed(String)
}

public enum SessionStartError: Error, Equatable, LocalizedError {
    case cutoffActive(CutoffReason)
    case assertionFailed(String)
    case lidControlFailed(String)

    public var errorDescription: String? {
        switch self {
        case .cutoffActive(let reason): "A safety cutoff is active. \(reason.message)"
        case .assertionFailed(let detail): "Could not stop idle sleep: \(detail)"
        case .lidControlFailed(let detail): "Could not keep the Mac awake with the lid closed: \(detail)"
        }
    }
}

/// Runs at most one session at a time and makes sure every session ends.
@MainActor
public final class SessionController {
    public private(set) var session: Session?
    public var onEvent: ((SessionEvent) -> Void)?

    private let preventer: IdleSleepPreventing
    private let lidControl: LidSleepControlling
    private let store: LidSessionStore
    private let pid: Int32
    private let now: () -> Date

    public init(
        preventer: IdleSleepPreventing,
        lidControl: LidSleepControlling,
        store: LidSessionStore,
        pid: Int32 = ProcessInfo.processInfo.processIdentifier,
        now: @escaping () -> Date = Date.init
    ) {
        self.preventer = preventer
        self.lidControl = lidControl
        self.store = store
        self.pid = pid
        self.now = now
    }

    public func start(
        mode: SessionMode,
        duration: TimeInterval,
        keepDisplayAwake: Bool,
        snapshot: PowerSnapshot?,
        policy: CutoffPolicy
    ) throws {
        if mode == .awakeLidClosed, let snapshot, let reason = policy.reason(for: snapshot) {
            throw SessionStartError.cutoffActive(reason)
        }
        if session != nil {
            stop(.replaced)
        }

        let startedAt = now()
        let next = Session(
            mode: mode, startedAt: startedAt, expiresAt: startedAt.addingTimeInterval(duration),
            keepDisplayAwake: keepDisplayAwake)

        do {
            try preventer.begin(keepDisplayAwake: keepDisplayAwake)
        } catch {
            throw SessionStartError.assertionFailed(error.localizedDescription)
        }

        if mode == .awakeLidClosed {
            do {
                // The record goes down before the flag, so a crash in between still
                // leaves the watchdog something to act on.
                try store.write(LidSessionRecord(pid: pid, startedAt: startedAt, expiresAt: next.expiresAt))
                try lidControl.setSleepDisabled(true)
            } catch {
                store.delete()
                preventer.end()
                throw SessionStartError.lidControlFailed(error.localizedDescription)
            }
        }

        session = next
        onEvent?(.started(next))
    }

    public func stop(_ reason: EndReason) {
        guard let ending = session else { return }
        session = nil
        preventer.end()

        if ending.mode == .awakeLidClosed {
            do {
                try lidControl.setSleepDisabled(false)
                store.delete()
            } catch {
                onEvent?(.revertFailed(error.localizedDescription))
            }
        }
        onEvent?(.ended(ending, reason))
    }

    /// Pushes the running session's expiry back by `seconds`, keeping the time left within
    /// `maxRemaining`. Returns false when there is no session or it is already at the cap.
    @discardableResult
    public func extend(by seconds: TimeInterval, maxRemaining: TimeInterval = Presets.durations.max()!) -> Bool {
        guard let current = session else { return false }
        let cap = now().addingTimeInterval(maxRemaining)
        let expiresAt = min(current.expiresAt.addingTimeInterval(seconds), cap)
        guard expiresAt > current.expiresAt else { return false }

        if current.mode == .awakeLidClosed {
            // The watchdog must see the new expiry, or it would end the session early.
            guard (try? store.write(LidSessionRecord(pid: pid, startedAt: current.startedAt, expiresAt: expiresAt)))
                != nil
            else { return false }
        }
        let extended = Session(
            mode: current.mode, startedAt: current.startedAt, expiresAt: expiresAt,
            keepDisplayAwake: current.keepDisplayAwake)
        session = extended
        onEvent?(.extended(extended))
        return true
    }

    /// Ends the session when its timer has run out or a cutoff applies. Call about once a second.
    public func tick(snapshot: PowerSnapshot?, policy: CutoffPolicy) {
        guard let current = session else { return }
        if now() >= current.expiresAt {
            stop(.expired)
        } else if current.mode == .awakeLidClosed, let snapshot, let reason = policy.reason(for: snapshot) {
            stop(.cutoff(reason))
        }
    }

    /// Turns off a lid flag left behind by an earlier Wakeful process, such as one that crashed.
    /// A flag with no Wakeful record belongs to someone else and is left alone.
    /// Returns true when it cleaned something up.
    @discardableResult
    public func recoverStaleSession() -> Bool {
        switch store.read() {
        case .missing:
            return false
        case .valid(let record) where record.pid == pid:
            return false
        case .valid, .invalid:
            if (try? lidControl.isSleepDisabled()) != false {
                do {
                    try lidControl.setSleepDisabled(false)
                } catch {
                    onEvent?(.revertFailed(error.localizedDescription))
                    return false
                }
            }
            store.delete()
            return true
        }
    }
}
