// Run by launchd every 60 seconds. Turns off Wakeful's lid flag when its session has
// expired or the app is gone, so a crash or hang never leaves the Mac unable to sleep.

import Foundation
import WakefulCore

func log(_ message: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    FileHandle.standardError.write(Data("\(stamp) \(message)\n".utf8))
}

let store = LidSessionStore.default
let lidControl = PmsetLidControl()
let record = store.read()

if record == .missing {
    exit(0)
}

// If the flag can't be read, assume it is on: an unneeded revert is harmless, a missed one is not.
let sleepDisabled = (try? lidControl.isSleepDisabled()) ?? true

let action = Watchdog.decide(record: record, sleepDisabled: sleepDisabled, now: Date()) { pid in
    ProcessInspector.isRunning(pid: pid, executableName: "Wakeful")
}

switch action {
case .nothing:
    break
case .clearRecord:
    store.delete()
    log("Removed a stale session record.")
case .revert(let reason):
    do {
        try lidControl.setSleepDisabled(false)
        store.delete()
        log("Turned off lid-closed awake: \(reason.rawValue).")
    } catch {
        log("Failed to turn off lid-closed awake (\(reason.rawValue)): \(error.localizedDescription)")
        exit(1)
    }
}
