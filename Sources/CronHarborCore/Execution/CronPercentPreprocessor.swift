import Foundation

public struct CronProcessedCommand: Sendable, Hashable {
    public let shellCommand: String
    /// `nil` means the source contained no unescaped percent delimiter. An
    /// empty string means it ended with a delimiter and supplies empty stdin.
    public let standardInput: String?

    public init(shellCommand: String, standardInput: String?) {
        self.shellCommand = shellCommand
        self.standardInput = standardInput
    }
}

public struct CronProcessedCommandData: Sendable, Hashable {
    public let shellCommand: Data
    public let standardInput: Data?

    public init(shellCommand: Data, standardInput: Data?) {
        self.shellCommand = shellCommand
        self.standardInput = standardInput
    }
}

/// Implements crontab's command-percent preprocessing before invoking a shell.
///
/// The first unescaped `%` separates the shell command from stdin. Later
/// unescaped percents become newlines. A percent preceded by an odd run of
/// backslashes is literal, and only the escaping backslash is removed.
public enum CronPercentPreprocessor {
    public static func preprocess(_ source: String) -> CronProcessedCommand {
        let processed = preprocess(Data(source.utf8))
        return CronProcessedCommand(
            shellCommand: String(decoding: processed.shellCommand, as: UTF8.self),
            standardInput: processed.standardInput.map { String(decoding: $0, as: UTF8.self) }
        )
    }

    public static func preprocess(_ source: Data) -> CronProcessedCommandData {
        let bytes = [UInt8](source)
        var command: [UInt8] = []
        var input: [UInt8] = []
        var hasInput = false
        var index = 0

        func append(_ byte: UInt8) {
            if hasInput {
                input.append(byte)
            } else {
                command.append(byte)
            }
        }

        while index < bytes.count {
            if bytes[index] != UInt8(ascii: "\\") {
                if bytes[index] == UInt8(ascii: "%") {
                    if hasInput {
                        input.append(UInt8(ascii: "\n"))
                    } else {
                        hasInput = true
                    }
                } else {
                    append(bytes[index])
                }
                index += 1
                continue
            }

            let slashStart = index
            while index < bytes.count, bytes[index] == UInt8(ascii: "\\") {
                index += 1
            }
            let slashCount = index - slashStart

            if index < bytes.count, bytes[index] == UInt8(ascii: "%") {
                if slashCount.isMultiple(of: 2) {
                    for _ in 0..<slashCount { append(UInt8(ascii: "\\")) }
                    if hasInput {
                        input.append(UInt8(ascii: "\n"))
                    } else {
                        hasInput = true
                    }
                } else {
                    for _ in 0..<(slashCount - 1) { append(UInt8(ascii: "\\")) }
                    append(UInt8(ascii: "%"))
                }
                index += 1
            } else {
                for _ in 0..<slashCount { append(UInt8(ascii: "\\")) }
            }
        }

        return CronProcessedCommandData(
            shellCommand: Data(command),
            standardInput: hasInput ? Data(input) : nil
        )
    }
}

public extension CronJob {
    var processedCommand: CronProcessedCommand {
        CronPercentPreprocessor.preprocess(command)
    }
}
