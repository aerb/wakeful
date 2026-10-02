import Foundation

/// The on-disk record of a lid-closed session. The watchdog reads it to decide whether
/// Wakeful's `SleepDisabled` flag has outlived its session.
public struct LidSessionRecord: Codable, Equatable, Sendable {
    public var version: Int
    public var pid: Int32
    public var startedAt: Date
    public var expiresAt: Date

    public init(pid: Int32, startedAt: Date, expiresAt: Date) {
        self.version = 1
        self.pid = pid
        self.startedAt = startedAt
        self.expiresAt = expiresAt
    }
}

public enum LidSessionRead: Equatable, Sendable {
    case missing
    case invalid
    case valid(LidSessionRecord)
}

public struct LidSessionStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// `~/Library/Application Support/Wakeful/lid-session.json`
    public static var `default`: LidSessionStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return LidSessionStore(url: base.appendingPathComponent("Wakeful/lid-session.json"))
    }

    public func read() -> LidSessionRead {
        guard let data = try? Data(contentsOf: url) else {
            return FileManager.default.fileExists(atPath: url.path) ? .invalid : .missing
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let record = try? decoder.decode(LidSessionRecord.self, from: data), record.version == 1 else {
            return .invalid
        }
        return .valid(record)
    }

    public func write(_ record: LidSessionRecord) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(record).write(to: url, options: .atomic)
    }

    public func delete() {
        try? FileManager.default.removeItem(at: url)
    }
}
