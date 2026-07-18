import CronHarborCore
import Foundation

enum JobHealth: String, Sendable {
    case healthy
    case paused
    case warning

    var symbol: String {
        switch self {
        case .healthy: "checkmark.circle.fill"
        case .paused: "pause.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        }
    }
}

struct JobPresentation: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var expression: String
    var command: String
    var isEnabled: Bool
    var nextRun: Date?
    var diagnostic: String?
    var isManaged: Bool
    var requiresACPower = false
    /// Digest of the complete installed crontab from which this presentation
    /// was derived. Live Run Now requires it to remain current so preceding
    /// environment assignments cannot change silently.
    var sourceRevision: String? = nil

    var health: JobHealth {
        if diagnostic != nil { return .warning }
        return isEnabled ? .healthy : .paused
    }

    var scheduleDescription: String {
        CronExpressionFormatter.describe(expression)
    }

    var shortCommand: String {
        guard command.count > 42 else { return command }
        return String(command.prefix(39)) + "…"
    }

    var runConfirmationMessage: String {
        var ignored = ["schedule"]
        if !isEnabled { ignored.append("paused state") }
        if requiresACPower { ignored.append("AC-power restriction") }
        return "CronHarbor will execute this command with cron-like shell and environment settings, ignoring its \(ignored.joined(separator: ", ")):\n\n\(command)"
    }
}

struct JobDraft: Equatable, Sendable {
    var id: String?
    var name = ""
    var expression = "0 9 * * *"
    var command = ""
    var isEnabled = true
    var requiresACPower = false

    init() {}

    init(job: JobPresentation) {
        id = job.id
        name = job.name
        expression = job.expression
        command = job.command
        isEnabled = job.isEnabled
        requiresACPower = job.requiresACPower
    }

    var validationMessage: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Give this job a short, recognizable name."
        }
        if command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Command cannot be empty."
        }
        if expression.contains("\n") || command.contains("\n") || name.contains("\n") {
            return "Cron jobs must stay on one line."
        }
        let normalizedExpression = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedExpression.hasPrefix("@") {
            guard CronMacro(rawValue: normalizedExpression) != nil else {
                return "Use a supported shortcut such as @hourly, @daily, or @reboot."
            }
        } else {
            let parts = normalizedExpression.split(whereSeparator: \Character.isWhitespace).map(String.init)
            guard parts.count == 5 else {
                return "Use five cron schedule fields or one supported @shortcut."
            }
            do {
                _ = try CronFields(
                    minute: parts[0],
                    hour: parts[1],
                    dayOfMonth: parts[2],
                    month: parts[3],
                    dayOfWeek: parts[4]
                )
            } catch let error as CronValidationError {
                return Self.message(for: error)
            } catch {
                return "One or more cron fields contain an invalid value, range, or step."
            }
        }
        return nil
    }

    private static func message(for error: CronValidationError) -> String {
        let fieldName: String = switch error.field {
        case .minute: "minute"
        case .hour: "hour"
        case .dayOfMonth: "day-of-month"
        case .month: "month"
        case .dayOfWeek: "weekday"
        }
        let range = error.field.allowedRange
        let problem: String = switch error.reason {
        case .emptyExpression: "is empty"
        case .emptyListItem: "has an empty list item"
        case .malformedStep, .invalidStep: "has an invalid step — use a form like */5"
        case .malformedRange: "has an invalid range — use a form like 1-5"
        case .reversedRange: "has a reversed range ('\(error.fragment)')"
        case .invalidValue: "contains an unrecognized value ('\(error.fragment)')"
        case .valueOutOfRange:
            "has a value outside \(range.lowerBound)–\(range.upperBound) ('\(error.fragment)')"
        }
        return "The \(fieldName) field \(problem)."
    }
}

struct JobDeletionSnapshot: Equatable, Sendable {
    let name: String
    let expression: String
    let command: String
    let isEnabled: Bool
    let requiresACPower: Bool

    init(job: JobPresentation) {
        name = job.name
        expression = job.expression
        command = job.command
        isEnabled = job.isEnabled
        requiresACPower = job.requiresACPower
    }
}

enum JobChange: Equatable, Sendable {
    case create(id: String, draft: JobDraft)
    case update(id: String, draft: JobDraft)
    case delete(id: String, snapshot: JobDeletionSnapshot)

    var targetID: String? {
        switch self {
        case .create(let id, _), .update(let id, _), .delete(let id, _): id
        }
    }
}

struct RunRecord: Identifiable, Hashable, Sendable, Codable {
    let id: UUID
    let jobID: String
    let jobName: String
    let startedAt: Date
    let duration: TimeInterval
    let exitCode: Int32
    let standardOutput: String
    let standardError: String

    var succeeded: Bool { exitCode == 0 }
}

struct CronLoadResult: Sendable {
    let jobs: [JobPresentation]
    let revision: String
    let diagnostics: [String]
    let runHistory: [RunRecord]
}

protocol CronServiceProtocol: Sendable {
    func load() async throws -> CronLoadResult
    func apply(changes: [JobChange], basedOn revision: String) async throws -> CronLoadResult
    func run(job: JobPresentation) async throws -> RunRecord
    func clearRunHistory() async throws
    func restoreBackup(from url: URL) async throws -> CronLoadResult
}

/// Default implementations keep lightweight service doubles source-compatible
/// while the live service opts into the full capability set.
extension CronServiceProtocol {
    func clearRunHistory() async throws {
        throw CronServiceCapabilityError.unsupported
    }

    func restoreBackup(from url: URL) async throws -> CronLoadResult {
        throw CronServiceCapabilityError.unsupported
    }
}

enum CronServiceCapabilityError: LocalizedError, Sendable {
    case unsupported

    var errorDescription: String? {
        "This action is not available right now."
    }
}

struct CrontabBackupInfo: Identifiable, Hashable, Sendable {
    let url: URL
    let createdAt: Date
    let sizeInBytes: Int

    var id: URL { url }
}
