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
            } catch {
                return "One or more cron fields contain an invalid value, range, or step."
            }
        }
        return nil
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
}
