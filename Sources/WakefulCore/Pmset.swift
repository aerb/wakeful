import Foundation

public enum PmsetOutput {
    /// Reads `SleepDisabled` from `pmset -g` output. A missing key means the flag is off.
    public static func sleepDisabled(in output: String) -> Bool {
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace)
            if fields.count >= 2, fields[0] == "SleepDisabled" {
                return fields[1] == "1"
            }
        }
        return false
    }
}

public struct CommandError: Error, LocalizedError, Sendable {
    public let command: String
    public let status: Int32
    public let stderr: String

    public var errorDescription: String? {
        let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return detail.isEmpty ? "\(command) exited with status \(status)." : detail
    }
}

struct CommandResult {
    let status: Int32
    let stdout: String
    let stderr: String
}

func runCommand(_ path: String, _ arguments: [String]) throws -> CommandResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    let out = Pipe()
    let err = Pipe()
    process.standardOutput = out
    process.standardError = err
    process.standardInput = FileHandle.nullDevice
    try process.run()
    let stdout = out.fileHandleForReading.readDataToEndOfFile()
    let stderr = err.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return CommandResult(
        status: process.terminationStatus,
        stdout: String(decoding: stdout, as: UTF8.self),
        stderr: String(decoding: stderr, as: UTF8.self))
}

/// Toggles `SleepDisabled` through the scoped sudoers rule the install script adds.
/// `sudo -n` never prompts: without the rule it fails straight away.
public struct PmsetLidControl: LidSleepControlling {
    static let sudo = "/usr/bin/sudo"
    static let pmset = "/usr/bin/pmset"

    public init() {}

    public func isSleepDisabled() throws -> Bool {
        let result = try runCommand(Self.pmset, ["-g"])
        guard result.status == 0 else {
            throw CommandError(command: "pmset -g", status: result.status, stderr: result.stderr)
        }
        return PmsetOutput.sleepDisabled(in: result.stdout)
    }

    public func setSleepDisabled(_ disabled: Bool) throws {
        let arguments = ["-n", Self.pmset, "-a", "disablesleep", disabled ? "1" : "0"]
        let result = try runCommand(Self.sudo, arguments)
        guard result.status == 0 else {
            throw CommandError(
                command: "pmset -a disablesleep \(disabled ? 1 : 0)", status: result.status, stderr: result.stderr)
        }
    }

    /// True when the sudoers rule lets this user run the command without a password.
    public func hasPermission() -> Bool {
        let arguments = ["-n", "-l", Self.pmset, "-a", "disablesleep", "1"]
        return (try? runCommand(Self.sudo, arguments).status) == 0
    }
}
