import Foundation

public enum WatchdogAction: Equatable, Sendable {
    case nothing
    /// The record is stale but the flag is already off: just remove the record.
    case clearRecord
    /// Turn the lid flag off, then remove the record.
    case revert(WatchdogReason)
}

public enum WatchdogReason: String, Equatable, Sendable {
    case expired = "session expired"
    case ownerGone = "Wakeful is no longer running"
    case invalidRecord = "session record is unreadable"
}

/// The watchdog's decision, kept free of side effects so it can be tested.
///
/// It only ever acts on a Wakeful record. A `SleepDisabled` flag with no record was set by
/// something else (another app, or `pmset` by hand) and is left alone.
public enum Watchdog {
    public static func decide(
        record: LidSessionRead,
        sleepDisabled: Bool,
        now: Date,
        ownerAlive: (Int32) -> Bool
    ) -> WatchdogAction {
        switch record {
        case .missing:
            return .nothing
        case .invalid:
            return sleepDisabled ? .revert(.invalidRecord) : .clearRecord
        case .valid(let record):
            let expired = now >= record.expiresAt
            let alive = ownerAlive(record.pid)
            if sleepDisabled {
                if expired { return .revert(.expired) }
                if !alive { return .revert(.ownerGone) }
                return .nothing
            }
            // Flag off with a live, unexpired owner: the app may be between writing the
            // record and setting the flag, so leave it.
            return (expired || !alive) ? .clearRecord : .nothing
        }
    }
}
