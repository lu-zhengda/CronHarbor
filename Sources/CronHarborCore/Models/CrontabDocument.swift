import Foundation

public struct CrontabComment: Sendable, Hashable {
    /// Leading spaces or tabs before the comment marker.
    public let indentation: String
    /// Text after `#`, retained exactly as UTF-8 text.
    public let text: String

    public init(indentation: String, text: String) {
        self.indentation = indentation
        self.text = text
    }
}

public struct CrontabEnvironmentAssignment: Sendable, Hashable {
    public let name: String
    /// The exact UTF-8 text after `=`; surrounding whitespace is not normalized.
    public let value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

public struct CronJobID: RawRepresentable, Sendable, Hashable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }
}

/// A semantic projection of a valid job line. The owning `CrontabLine` still
/// carries the authoritative bytes used when the document is rendered.
public struct CronJob: Identifiable, Sendable, Hashable {
    public let id: CronJobID
    public let sourceLineIndex: Int
    public let schedule: CronSchedule
    public let command: String
    public let appleNotOnBattery: Bool

    public init(
        id: CronJobID,
        sourceLineIndex: Int,
        schedule: CronSchedule,
        command: String,
        appleNotOnBattery: Bool
    ) {
        self.id = id
        self.sourceLineIndex = sourceLineIndex
        self.schedule = schedule
        self.command = command
        self.appleNotOnBattery = appleNotOnBattery
    }

    public var requiresACPower: Bool { appleNotOnBattery }
}

public enum CrontabLineKind: Sendable, Hashable {
    case blank
    case comment(CrontabComment)
    case environment(CrontabEnvironmentAssignment)
    case job(CronJob)
    case opaque
}

public struct CrontabLine: Sendable, Hashable {
    public let raw: RawLine
    public let kind: CrontabLineKind

    public init(raw: RawLine, kind: CrontabLineKind) {
        self.raw = raw
        self.kind = kind
    }
}

public struct CrontabDocument: Sendable, Hashable {
    public let lines: [CrontabLine]

    public init(lines: [CrontabLine]) {
        self.lines = lines
    }

    public init(data: Data) {
        self = CrontabParser.parse(data)
    }

    public var jobs: [CronJob] {
        lines.compactMap { line in
            guard case let .job(job) = line.kind else { return nil }
            return job
        }
    }

    public func renderedData() -> Data {
        var result = Data()
        for line in lines {
            result.append(line.raw.renderedData)
        }
        return result
    }
}
