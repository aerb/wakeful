import Foundation

/// What a session keeps awake.
public enum SessionMode: String, Codable, Sendable, CaseIterable {
    /// Stops idle sleep through an IOKit assertion. Closing the lid still sleeps.
    case awake
    /// Also sets the kernel's `SleepDisabled` flag, so the Mac stays awake with the lid shut.
    case awakeLidClosed

    public var displayName: String {
        switch self {
        case .awake: "Awake"
        case .awakeLidClosed: "Awake, lid closed"
        }
    }
}

public struct Session: Equatable, Sendable {
    public let mode: SessionMode
    public let startedAt: Date
    public let expiresAt: Date
    public let keepDisplayAwake: Bool

    public init(mode: SessionMode, startedAt: Date, expiresAt: Date, keepDisplayAwake: Bool) {
        self.mode = mode
        self.startedAt = startedAt
        self.expiresAt = expiresAt
        self.keepDisplayAwake = keepDisplayAwake
    }

    public func remaining(at now: Date) -> TimeInterval {
        max(0, expiresAt.timeIntervalSince(now))
    }
}

/// Why a session ended.
public enum EndReason: Equatable, Sendable {
    case userStopped
    case expired
    case cutoff(CutoffReason)
    case systemSleep
    case appQuit
    case replaced

    public var message: String {
        switch self {
        case .userStopped: "Stopped."
        case .expired: "The timer ran out."
        case .cutoff(let reason): reason.message
        case .systemSleep: "The Mac is going to sleep."
        case .appQuit: "Wakeful quit."
        case .replaced: "A new session started."
        }
    }

    /// Whether the user should get a notification: only for endings they did not cause.
    public var isWorthNotifying: Bool {
        switch self {
        case .expired, .cutoff: true
        case .userStopped, .systemSleep, .appQuit, .replaced: false
        }
    }
}

public enum Presets {
    public static let durations: [TimeInterval] = [
        15 * 60, 30 * 60, 60 * 60, 2 * 3600, 4 * 3600, 8 * 3600,
    ]

    public static let defaultDuration: TimeInterval = 3600

    public static let extendStep: TimeInterval = 15 * 60

    public static let batteryFloors: [Int] = [5, 10, 15, 20, 25, 30, 40, 50]

    public static let defaultBatteryFloor = 15
}

public enum DurationFormat {
    /// "15 minutes", "1 hour", "8 hours".
    public static func label(_ duration: TimeInterval) -> String {
        let minutes = Int(duration.rounded()) / 60
        if minutes < 60 || minutes % 60 != 0 {
            return minutes == 1 ? "1 minute" : "\(minutes) minutes"
        }
        let hours = minutes / 60
        return hours == 1 ? "1 hour" : "\(hours) hours"
    }

    /// "1:05:09" or "12:03".
    public static func countdown(_ remaining: TimeInterval) -> String {
        let total = max(0, Int(remaining.rounded(.up)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
