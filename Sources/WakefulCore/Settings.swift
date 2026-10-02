import Foundation

public struct WakefulSettings: Equatable, Sendable {
    public var defaultDuration: TimeInterval = Presets.defaultDuration
    public var keepDisplayAwake = false
    public var batteryFloor = Presets.defaultBatteryFloor
    public var stopOnLowPowerMode = true
    public var stopOnThermalPressure = true

    public init() {}

    public var cutoffPolicy: CutoffPolicy {
        CutoffPolicy(
            batteryFloor: batteryFloor, stopOnLowPowerMode: stopOnLowPowerMode,
            stopOnThermalPressure: stopOnThermalPressure)
    }
}

public struct SettingsStore {
    private enum Key {
        static let defaultDuration = "defaultDuration"
        static let keepDisplayAwake = "keepDisplayAwake"
        static let batteryFloor = "batteryFloor"
        static let stopOnLowPowerMode = "stopOnLowPowerMode"
        static let stopOnThermalPressure = "stopOnThermalPressure"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Loads saved settings, falling back to the defaults for anything missing or out of range.
    public func load() -> WakefulSettings {
        var settings = WakefulSettings()
        if let duration = defaults.object(forKey: Key.defaultDuration) as? Double,
            Presets.durations.contains(duration)
        {
            settings.defaultDuration = duration
        }
        if let floor = defaults.object(forKey: Key.batteryFloor) as? Int, Presets.batteryFloors.contains(floor) {
            settings.batteryFloor = floor
        }
        if let value = defaults.object(forKey: Key.keepDisplayAwake) as? Bool {
            settings.keepDisplayAwake = value
        }
        if let value = defaults.object(forKey: Key.stopOnLowPowerMode) as? Bool {
            settings.stopOnLowPowerMode = value
        }
        if let value = defaults.object(forKey: Key.stopOnThermalPressure) as? Bool {
            settings.stopOnThermalPressure = value
        }
        return settings
    }

    public func save(_ settings: WakefulSettings) {
        defaults.set(settings.defaultDuration, forKey: Key.defaultDuration)
        defaults.set(settings.keepDisplayAwake, forKey: Key.keepDisplayAwake)
        defaults.set(settings.batteryFloor, forKey: Key.batteryFloor)
        defaults.set(settings.stopOnLowPowerMode, forKey: Key.stopOnLowPowerMode)
        defaults.set(settings.stopOnThermalPressure, forKey: Key.stopOnThermalPressure)
    }
}
