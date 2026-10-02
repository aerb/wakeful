import Foundation
import Testing

@testable import WakefulCore

@MainActor
final class FakePreventer: IdleSleepPreventing {
    var active = false
    var displayAwake = false
    var failBegin = false

    func begin(keepDisplayAwake: Bool) throws {
        if failBegin { throw CommandError(command: "assert", status: 1, stderr: "nope") }
        active = true
        displayAwake = keepDisplayAwake
    }

    func end() {
        active = false
        displayAwake = false
    }
}

final class FakeLidControl: LidSleepControlling, @unchecked Sendable {
    var disabled = false
    var failSet = false
    var setCalls: [Bool] = []

    func isSleepDisabled() throws -> Bool { disabled }

    func setSleepDisabled(_ value: Bool) throws {
        setCalls.append(value)
        if failSet { throw CommandError(command: "pmset", status: 1, stderr: "sudo: a password is required") }
        disabled = value
    }
}

final class Clock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_000_000)
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

func temporaryStore() -> LidSessionStore {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wakeful-tests-\(UUID().uuidString)")
    return LidSessionStore(url: dir.appendingPathComponent("lid-session.json"))
}

let noCutoffs = CutoffPolicy(batteryFloor: 15, stopOnLowPowerMode: true, stopOnThermalPressure: true)
let healthy = PowerSnapshot(batteryPercent: 80, onBattery: true, lowPowerMode: false, thermal: .nominal)

@MainActor
struct SessionControllerTests {
    let preventer = FakePreventer()
    let lid = FakeLidControl()
    let store = temporaryStore()
    let clock = Clock()

    func makeController() -> SessionController {
        let clock = self.clock
        return SessionController(preventer: preventer, lidControl: lid, store: store, pid: 4242) { clock.now }
    }

    @Test func awakeSessionHoldsAssertionOnly() throws {
        let controller = makeController()
        try controller.start(
            mode: .awake, duration: 900, keepDisplayAwake: true, snapshot: healthy, policy: noCutoffs)

        #expect(preventer.active)
        #expect(preventer.displayAwake)
        #expect(lid.setCalls.isEmpty)
        #expect(store.read() == .missing)
        #expect(controller.session?.expiresAt == clock.now.addingTimeInterval(900))
    }

    @Test func lidSessionWritesRecordAndSetsFlag() throws {
        let controller = makeController()
        try controller.start(
            mode: .awakeLidClosed, duration: 3600, keepDisplayAwake: false, snapshot: healthy, policy: noCutoffs)

        #expect(lid.disabled)
        guard case .valid(let record) = store.read() else {
            Issue.record("expected a session record")
            return
        }
        #expect(record.pid == 4242)
        #expect(record.expiresAt == clock.now.addingTimeInterval(3600))
    }

    @Test func expiryRevertsEverything() throws {
        let controller = makeController()
        var ended: EndReason?
        controller.onEvent = { if case .ended(_, let reason) = $0 { ended = reason } }
        try controller.start(
            mode: .awakeLidClosed, duration: 60, keepDisplayAwake: false, snapshot: healthy, policy: noCutoffs)

        clock.advance(59)
        controller.tick(snapshot: healthy, policy: noCutoffs)
        #expect(controller.session != nil)

        clock.advance(1)
        controller.tick(snapshot: healthy, policy: noCutoffs)
        #expect(controller.session == nil)
        #expect(ended == .expired)
        #expect(!lid.disabled)
        #expect(!preventer.active)
        #expect(store.read() == .missing)
    }

    @Test func cutoffEndsLidSession() throws {
        let controller = makeController()
        var ended: EndReason?
        controller.onEvent = { if case .ended(_, let reason) = $0 { ended = reason } }
        try controller.start(
            mode: .awakeLidClosed, duration: 3600, keepDisplayAwake: false, snapshot: healthy, policy: noCutoffs)

        var low = healthy
        low.batteryPercent = 15
        controller.tick(snapshot: low, policy: noCutoffs)

        #expect(ended == .cutoff(.batteryFloor(percent: 15)))
        #expect(!lid.disabled)
    }

    @Test func cutoffsDoNotApplyToAwakeMode() throws {
        let controller = makeController()
        try controller.start(
            mode: .awake, duration: 3600, keepDisplayAwake: false, snapshot: healthy, policy: noCutoffs)

        var hot = healthy
        hot.thermal = .critical
        controller.tick(snapshot: hot, policy: noCutoffs)

        #expect(controller.session != nil)
    }

    @Test func lidStartRefusedWhileCutoffActive() {
        let controller = makeController()
        var lowPower = healthy
        lowPower.lowPowerMode = true

        #expect(throws: SessionStartError.cutoffActive(.lowPowerMode)) {
            try controller.start(
                mode: .awakeLidClosed, duration: 900, keepDisplayAwake: false, snapshot: lowPower,
                policy: noCutoffs)
        }
        #expect(!preventer.active)
        #expect(lid.setCalls.isEmpty)
    }

    @Test func failedLidStartCleansUp() {
        let controller = makeController()
        lid.failSet = true

        #expect(throws: SessionStartError.self) {
            try controller.start(
                mode: .awakeLidClosed, duration: 900, keepDisplayAwake: false, snapshot: healthy,
                policy: noCutoffs)
        }
        #expect(controller.session == nil)
        #expect(!preventer.active)
        #expect(store.read() == .missing)
    }

    @Test func failedRevertKeepsRecordForWatchdog() throws {
        let controller = makeController()
        var failures = 0
        controller.onEvent = { if case .revertFailed = $0 { failures += 1 } }
        try controller.start(
            mode: .awakeLidClosed, duration: 900, keepDisplayAwake: false, snapshot: healthy, policy: noCutoffs)

        lid.failSet = true
        controller.stop(.userStopped)

        #expect(failures == 1)
        #expect(controller.session == nil)
        if case .valid = store.read() {} else { Issue.record("record should stay for the watchdog") }
    }

    @Test func switchingFromLidToAwakeTurnsFlagOff() throws {
        let controller = makeController()
        try controller.start(
            mode: .awakeLidClosed, duration: 900, keepDisplayAwake: false, snapshot: healthy, policy: noCutoffs)
        try controller.start(
            mode: .awake, duration: 900, keepDisplayAwake: false, snapshot: healthy, policy: noCutoffs)

        #expect(controller.session?.mode == .awake)
        #expect(!lid.disabled)
        #expect(preventer.active)
        #expect(store.read() == .missing)
    }

    @Test func extendMovesExpiryAndRecord() throws {
        let controller = makeController()
        try controller.start(
            mode: .awakeLidClosed, duration: 900, keepDisplayAwake: false, snapshot: healthy, policy: noCutoffs)

        #expect(controller.extend(by: Presets.extendStep))
        let expected = clock.now.addingTimeInterval(1800)
        #expect(controller.session?.expiresAt == expected)
        guard case .valid(let record) = store.read() else {
            Issue.record("expected a session record")
            return
        }
        #expect(record.expiresAt == expected)
    }

    @Test func extendIsCappedAtLongestPreset() throws {
        let controller = makeController()
        try controller.start(
            mode: .awake, duration: 8 * 3600 - 60, keepDisplayAwake: false, snapshot: healthy, policy: noCutoffs)

        #expect(controller.extend(by: Presets.extendStep))
        #expect(controller.session?.remaining(at: clock.now) == TimeInterval(8 * 3600))
        #expect(!controller.extend(by: Presets.extendStep))
        #expect(!makeController().extend(by: 60))
    }

    @Test func recoversFlagLeftByEarlierProcess() throws {
        try store.write(LidSessionRecord(pid: 1111, startedAt: clock.now, expiresAt: clock.now.addingTimeInterval(60)))
        lid.disabled = true

        #expect(makeController().recoverStaleSession())
        #expect(!lid.disabled)
        #expect(store.read() == .missing)
    }

    @Test func leavesForeignFlagAlone() {
        lid.disabled = true

        #expect(!makeController().recoverStaleSession())
        #expect(lid.disabled)
        #expect(lid.setCalls.isEmpty)
    }
}
