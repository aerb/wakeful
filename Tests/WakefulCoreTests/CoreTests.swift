import Foundation
import Testing

@testable import WakefulCore

struct WatchdogTests {
    let now = Date(timeIntervalSince1970: 1_000_000)

    func record(expiresIn seconds: TimeInterval) -> LidSessionRead {
        .valid(LidSessionRecord(pid: 7, startedAt: now, expiresAt: now.addingTimeInterval(seconds)))
    }

    @Test func noRecordMeansNothing() {
        #expect(Watchdog.decide(record: .missing, sleepDisabled: true, now: now) { _ in false } == .nothing)
    }

    @Test func activeSessionIsLeftAlone() {
        #expect(Watchdog.decide(record: record(expiresIn: 60), sleepDisabled: true, now: now) { _ in true } == .nothing)
    }

    @Test func expiredSessionIsReverted() {
        let action = Watchdog.decide(record: record(expiresIn: 0), sleepDisabled: true, now: now) { _ in true }
        #expect(action == .revert(.expired))
    }

    @Test func deadOwnerIsReverted() {
        let action = Watchdog.decide(record: record(expiresIn: 60), sleepDisabled: true, now: now) { _ in false }
        #expect(action == .revert(.ownerGone))
    }

    @Test func invalidRecordIsReverted() {
        #expect(Watchdog.decide(record: .invalid, sleepDisabled: true, now: now) { _ in true } == .revert(.invalidRecord))
        #expect(Watchdog.decide(record: .invalid, sleepDisabled: false, now: now) { _ in true } == .clearRecord)
    }

    @Test func staleRecordWithFlagOffIsCleared() {
        #expect(Watchdog.decide(record: record(expiresIn: -5), sleepDisabled: false, now: now) { _ in true } == .clearRecord)
        #expect(Watchdog.decide(record: record(expiresIn: 60), sleepDisabled: false, now: now) { _ in false } == .clearRecord)
    }

    @Test func startingSessionIsLeftAlone() {
        // Record written, flag not set yet.
        #expect(Watchdog.decide(record: record(expiresIn: 60), sleepDisabled: false, now: now) { _ in true } == .nothing)
    }
}

struct CutoffPolicyTests {
    let policy = CutoffPolicy(batteryFloor: 15, stopOnLowPowerMode: true, stopOnThermalPressure: true)
    let base = PowerSnapshot(batteryPercent: 50, onBattery: true, lowPowerMode: false, thermal: .fair)

    @Test func healthyHasNoCutoff() {
        #expect(policy.reason(for: base) == nil)
    }

    @Test func batteryFloorOnlyOnBattery() {
        var low = base
        low.batteryPercent = 10
        #expect(policy.reason(for: low) == .batteryFloor(percent: 10))
        low.onBattery = false
        #expect(policy.reason(for: low) == nil)
    }

    @Test func noBatteryMeansNoFloor() {
        var desktop = base
        desktop.batteryPercent = nil
        #expect(policy.reason(for: desktop) == nil)
    }

    @Test func lowPowerAndThermalRespectToggles() {
        var snapshot = base
        snapshot.lowPowerMode = true
        snapshot.thermal = .serious
        #expect(policy.reason(for: snapshot) == .lowPowerMode)

        var relaxed = policy
        relaxed.stopOnLowPowerMode = false
        #expect(relaxed.reason(for: snapshot) == .thermalPressure)

        relaxed.stopOnThermalPressure = false
        #expect(relaxed.reason(for: snapshot) == nil)
    }
}

struct PmsetOutputTests {
    @Test func readsFlag() {
        let on = "System-wide power settings:\n SleepDisabled\t\t1\nCurrently in use:\n standby 1\n"
        #expect(PmsetOutput.sleepDisabled(in: on))
        #expect(!PmsetOutput.sleepDisabled(in: on.replacingOccurrences(of: "\t\t1", with: "\t\t0")))
        #expect(!PmsetOutput.sleepDisabled(in: "Currently in use:\n standby 1\n"))
    }
}

struct StoreAndFormatTests {
    @Test func recordRoundTrips() throws {
        let store = temporaryStore()
        #expect(store.read() == .missing)

        let record = LidSessionRecord(
            pid: 99, startedAt: Date(timeIntervalSince1970: 100), expiresAt: Date(timeIntervalSince1970: 200))
        try store.write(record)
        #expect(store.read() == .valid(record))

        try Data("garbage".utf8).write(to: store.url)
        #expect(store.read() == .invalid)

        store.delete()
        #expect(store.read() == .missing)
    }

    @Test func settingsRoundTripAndRejectOddValues() throws {
        let defaults = try #require(UserDefaults(suiteName: "wakeful-tests-\(UUID().uuidString)"))
        let store = SettingsStore(defaults: defaults)
        #expect(store.load() == WakefulSettings())

        var settings = WakefulSettings()
        settings.defaultDuration = 4 * 3600
        settings.batteryFloor = 30
        settings.keepDisplayAwake = true
        settings.stopOnThermalPressure = false
        store.save(settings)
        #expect(store.load() == settings)

        defaults.set(12345.0, forKey: "defaultDuration")
        defaults.set(3, forKey: "batteryFloor")
        #expect(store.load().defaultDuration == Presets.defaultDuration)
        #expect(store.load().batteryFloor == Presets.defaultBatteryFloor)
    }

    @Test func formatsDurations() {
        #expect(Presets.durations.map(DurationFormat.label) == [
            "15 minutes", "30 minutes", "1 hour", "2 hours", "4 hours", "8 hours",
        ])
        #expect(DurationFormat.countdown(3909) == "1:05:09")
        #expect(DurationFormat.countdown(723) == "12:03")
        #expect(DurationFormat.countdown(0.2) == "0:01")
        #expect(DurationFormat.countdown(-4) == "0:00")
    }
}
