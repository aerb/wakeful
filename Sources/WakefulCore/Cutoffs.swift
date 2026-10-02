import Foundation

public enum ThermalLevel: Sendable {
    case nominal, fair, serious, critical

    public init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .critical
        }
    }
}

/// The power conditions the safety cutoffs look at.
public struct PowerSnapshot: Equatable, Sendable {
    /// Battery charge in percent, or nil on a Mac without a battery.
    public var batteryPercent: Int?
    /// True when the Mac is running from its battery rather than AC.
    public var onBattery: Bool
    public var lowPowerMode: Bool
    public var thermal: ThermalLevel

    public init(batteryPercent: Int?, onBattery: Bool, lowPowerMode: Bool, thermal: ThermalLevel) {
        self.batteryPercent = batteryPercent
        self.onBattery = onBattery
        self.lowPowerMode = lowPowerMode
        self.thermal = thermal
    }
}

public enum CutoffReason: Equatable, Sendable {
    case batteryFloor(percent: Int)
    case lowPowerMode
    case thermalPressure

    public var message: String {
        switch self {
        case .batteryFloor(let percent): "The battery is down to \(percent)%."
        case .lowPowerMode: "Low Power Mode turned on."
        case .thermalPressure: "The Mac is running hot."
        }
    }
}

/// Conditions that end a lid-closed session early.
public struct CutoffPolicy: Equatable, Sendable {
    public var batteryFloor: Int
    public var stopOnLowPowerMode: Bool
    public var stopOnThermalPressure: Bool

    public init(batteryFloor: Int, stopOnLowPowerMode: Bool, stopOnThermalPressure: Bool) {
        self.batteryFloor = batteryFloor
        self.stopOnLowPowerMode = stopOnLowPowerMode
        self.stopOnThermalPressure = stopOnThermalPressure
    }

    /// The first cutoff that applies, or nil when the session may continue.
    /// The battery floor only applies while running on battery, so a charging Mac is left alone.
    public func reason(for snapshot: PowerSnapshot) -> CutoffReason? {
        if snapshot.onBattery, let percent = snapshot.batteryPercent, percent <= batteryFloor {
            return .batteryFloor(percent: percent)
        }
        if stopOnLowPowerMode && snapshot.lowPowerMode {
            return .lowPowerMode
        }
        if stopOnThermalPressure && (snapshot.thermal == .serious || snapshot.thermal == .critical) {
            return .thermalPressure
        }
        return nil
    }
}
