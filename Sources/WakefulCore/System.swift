import Darwin
import Foundation
import IOKit.ps
import IOKit.pwr_mgt

/// Idle-sleep prevention through IOKit power assertions, the same mechanism Caffeine uses.
@MainActor
public final class IOKitSleepPreventer: IdleSleepPreventing {
    private var assertions: [IOPMAssertionID] = []

    public init() {}

    public func begin(keepDisplayAwake: Bool) throws {
        end()
        var types = [kIOPMAssertionTypePreventUserIdleSystemSleep]
        if keepDisplayAwake {
            types.append(kIOPMAssertionTypePreventUserIdleDisplaySleep)
        }
        for type in types {
            var id = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(
                type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Wakeful session" as CFString, &id)
            guard result == kIOReturnSuccess else {
                end()
                throw CommandError(command: "IOPMAssertionCreateWithName", status: result, stderr: "")
            }
            assertions.append(id)
        }
    }

    public func end() {
        for id in assertions {
            IOPMAssertionRelease(id)
        }
        assertions.removeAll()
    }
}

public enum PowerMonitor {
    public static func snapshot() -> PowerSnapshot {
        var percent: Int?
        var onBattery = false

        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() {
            if let providing = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() {
                onBattery = (providing as String) == kIOPSBatteryPowerValue
            }
            let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] ?? []
            for source in sources {
                guard
                    let description = IOPSGetPowerSourceDescription(info, source)?
                        .takeUnretainedValue() as? [String: Any],
                    description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                    let current = description[kIOPSCurrentCapacityKey] as? Int,
                    let max = description[kIOPSMaxCapacityKey] as? Int, max > 0
                else { continue }
                percent = current * 100 / max
            }
        }

        return PowerSnapshot(
            batteryPercent: percent,
            onBattery: onBattery,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            thermal: ThermalLevel(ProcessInfo.processInfo.thermalState))
    }
}

public enum ProcessInspector {
    /// True when `pid` is running and its executable is named `executableName`,
    /// so a recycled pid is not mistaken for Wakeful.
    public static func isRunning(pid: Int32, executableName: String) -> Bool {
        guard pid > 0, kill(pid, 0) == 0 || errno == EPERM else { return false }
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return false }
        let path = String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return (path as NSString).lastPathComponent == executableName
    }
}
