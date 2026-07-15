import Foundation

public struct ManagedCronJob: Identifiable, Sendable, Hashable {
    public let id: CronJobID
    public let name: String
    public let schedule: CronSchedule
    public let command: String
    public let isEnabled: Bool
    public let isManaged: Bool
    public let appleNotOnBattery: Bool
    public let sourceLineIndex: Int
    public let metadataLineIndex: Int?
    public let metadataRawLine: RawLine?
    public let sourceRawLine: RawLine
    public let originalJobRawLine: RawLine

    public init(
        id: CronJobID,
        name: String,
        schedule: CronSchedule,
        command: String,
        isEnabled: Bool,
        isManaged: Bool,
        appleNotOnBattery: Bool,
        sourceLineIndex: Int,
        metadataLineIndex: Int?,
        metadataRawLine: RawLine?,
        sourceRawLine: RawLine,
        originalJobRawLine: RawLine
    ) {
        self.id = id
        self.name = name
        self.schedule = schedule
        self.command = command
        self.isEnabled = isEnabled
        self.isManaged = isManaged
        self.appleNotOnBattery = appleNotOnBattery
        self.sourceLineIndex = sourceLineIndex
        self.metadataLineIndex = metadataLineIndex
        self.metadataRawLine = metadataRawLine
        self.sourceRawLine = sourceRawLine
        self.originalJobRawLine = originalJobRawLine
    }

    public var cronJob: CronJob {
        CronJob(
            id: id,
            sourceLineIndex: sourceLineIndex,
            schedule: schedule,
            command: command,
            appleNotOnBattery: appleNotOnBattery
        )
    }
}

public struct ManagedCronJobDraft: Sendable, Hashable {
    public let name: String
    public let scheduleExpression: String
    public let command: String
    public let isEnabled: Bool
    public let appleNotOnBattery: Bool

    public init(
        name: String,
        scheduleExpression: String,
        command: String,
        isEnabled: Bool,
        appleNotOnBattery: Bool = false
    ) {
        self.name = name
        self.scheduleExpression = scheduleExpression
        self.command = command
        self.isEnabled = isEnabled
        self.appleNotOnBattery = appleNotOnBattery
    }
}

public enum ManagedCronMutation: Sendable, Hashable {
    case create(ManagedCronJobDraft)
    case update(id: CronJobID, draft: ManagedCronJobDraft)
    case delete(id: CronJobID)
}

public enum ManagedCrontabError: Error, Sendable, Hashable, CustomStringConvertible {
    case duplicateMutation(CronJobID)
    case ambiguousJobID(CronJobID)
    case jobNotFound(CronJobID)
    case emptyName
    case nameContainsNewline
    case emptyCommand
    case commandContainsNewline
    case commandContainsNUL
    case invalidSchedule(String)

    public var description: String {
        switch self {
        case .duplicateMutation(let id): "More than one pending change targets job \(id)."
        case .ambiguousJobID(let id): "More than one cron job uses the managed identity \(id)."
        case .jobNotFound(let id): "The cron job \(id) no longer exists."
        case .emptyName: "Job name cannot be empty."
        case .nameContainsNewline: "Job name cannot contain a newline."
        case .emptyCommand: "Command cannot be empty."
        case .commandContainsNewline: "Command cannot contain a literal newline."
        case .commandContainsNUL: "Command cannot contain a NUL byte."
        case .invalidSchedule(let value): "Invalid cron schedule: \(value)"
        }
    }
}

/// A semantic, lossless view over a user's crontab.
///
/// Existing lines remain authoritative `RawLine` values. CronHarbor markers
/// are added only around jobs the user creates, renames, edits, or pauses.
public struct ManagedCrontab: Sendable, Hashable {
    public let document: CrontabDocument
    public let jobs: [ManagedCronJob]
    public let opaqueLineIndices: [Int]
    public let ambiguousJobIDs: Set<CronJobID>

    public init(data: Data) {
        let document = CrontabDocument(data: data)
        self.document = document

        var projectedJobs: [ManagedCronJob] = []
        var opaqueIndices: [Int] = []

        for (index, line) in document.lines.enumerated() {
            if case .opaque = line.kind {
                opaqueIndices.append(index)
            }

            let metadata = index > 0 ? Self.metadata(from: document.lines[index - 1].raw) : nil

            if case let .job(job) = line.kind {
                // A marker applies only to the immediately following job. The
                // parser has already validated its identifier before returning it.
                let matchingMetadata = metadata
                let id = matchingMetadata?.id ?? job.id
                projectedJobs.append(
                    ManagedCronJob(
                        id: id,
                        name: matchingMetadata?.name ?? Self.inferredName(for: job, lineIndex: index, document: document),
                        schedule: job.schedule,
                        command: job.command,
                        isEnabled: true,
                        isManaged: matchingMetadata != nil,
                        appleNotOnBattery: job.appleNotOnBattery,
                        sourceLineIndex: index,
                        metadataLineIndex: matchingMetadata == nil ? nil : index - 1,
                        metadataRawLine: matchingMetadata == nil ? nil : document.lines[index - 1].raw,
                        sourceRawLine: line.raw,
                        originalJobRawLine: line.raw
                    )
                )
                continue
            }

            guard let disabled = Self.disabledJob(from: line.raw, lineIndex: index) else {
                continue
            }
            let matchingMetadata = metadata.flatMap { $0.id == disabled.id ? $0 : nil }
            projectedJobs.append(
                ManagedCronJob(
                    id: disabled.id,
                    name: matchingMetadata?.name ?? Self.inferredName(for: disabled.job, lineIndex: index, document: document),
                    schedule: disabled.job.schedule,
                    command: disabled.job.command,
                    isEnabled: false,
                    isManaged: true,
                    appleNotOnBattery: disabled.job.appleNotOnBattery,
                    sourceLineIndex: index,
                    metadataLineIndex: matchingMetadata == nil ? nil : index - 1,
                    metadataRawLine: matchingMetadata == nil ? nil : document.lines[index - 1].raw,
                    sourceRawLine: line.raw,
                    originalJobRawLine: disabled.originalRaw
                )
            )
        }

        self.jobs = projectedJobs
        self.opaqueLineIndices = opaqueIndices
        let idCounts = projectedJobs.reduce(into: [CronJobID: Int]()) { counts, job in
            counts[job.id, default: 0] += 1
        }
        self.ambiguousJobIDs = Set(idCounts.compactMap { id, count in count > 1 ? id : nil })
    }

    public func renderedData() -> Data {
        document.renderedData()
    }

    public func applying(
        _ mutations: [ManagedCronMutation],
        generateID: @Sendable () -> UUID = { UUID() }
    ) throws -> Data {
        var targetedIDs = Set<CronJobID>()
        var edits: [LineEdit] = []
        var creations: [ManagedCronJobDraft] = []
        let jobsByID = Dictionary(
            uniqueKeysWithValues: jobs
                .filter { !ambiguousJobIDs.contains($0.id) }
                .map { ($0.id, $0) }
        )

        for mutation in mutations {
            switch mutation {
            case .create(let draft):
                _ = try Self.validatedSchedule(for: draft)
                creations.append(draft)
            case .update(let id, let draft):
                guard targetedIDs.insert(id).inserted else {
                    throw ManagedCrontabError.duplicateMutation(id)
                }
                guard !ambiguousJobIDs.contains(id) else {
                    throw ManagedCrontabError.ambiguousJobID(id)
                }
                guard let existing = jobsByID[id] else {
                    throw ManagedCrontabError.jobNotFound(id)
                }
                let schedule = try Self.validatedSchedule(for: draft)
                edits.append(Self.updateEdit(existing: existing, draft: draft, schedule: schedule, generateID: generateID))
            case .delete(let id):
                guard targetedIDs.insert(id).inserted else {
                    throw ManagedCrontabError.duplicateMutation(id)
                }
                guard !ambiguousJobIDs.contains(id) else {
                    throw ManagedCrontabError.ambiguousJobID(id)
                }
                guard let existing = jobsByID[id] else {
                    throw ManagedCrontabError.jobNotFound(id)
                }
                let lower = existing.metadataLineIndex ?? existing.sourceLineIndex
                edits.append(LineEdit(range: lower..<(existing.sourceLineIndex + 1), replacement: []))
            }
        }

        var lines = document.lines.map(\.raw)
        for edit in edits.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
            lines.replaceSubrange(edit.range, with: edit.replacement)
        }

        if !creations.isEmpty {
            let terminator = Self.preferredTerminator(in: lines)
            if let last = lines.indices.last, lines[last].terminator == .none {
                lines[last] = RawLine(content: lines[last].content, terminator: terminator)
            }

            for draft in creations {
                let schedule = try Self.validatedSchedule(for: draft)
                let id = CronJobID(rawValue: generateID().uuidString.lowercased())
                lines.append(Self.metadataRaw(id: id, name: draft.name, terminator: terminator))
                let jobRaw = Self.jobRaw(draft: draft, schedule: schedule, terminator: terminator)
                lines.append(draft.isEnabled ? jobRaw : Self.disabledRaw(id: id, original: jobRaw))
            }
        }

        var result = Data()
        for line in lines {
            result.append(line.renderedData)
        }
        return result
    }

    private static func updateEdit(
        existing: ManagedCronJob,
        draft: ManagedCronJobDraft,
        schedule: CronSchedule,
        generateID: @Sendable () -> UUID
    ) -> LineEdit {
        let id = existing.isManaged
            ? existing.id
            : CronJobID(rawValue: generateID().uuidString.lowercased())
        let lower = existing.metadataLineIndex ?? existing.sourceLineIndex
        let range = lower..<(existing.sourceLineIndex + 1)

        let nameIsUnchanged = draft.name == existing.name
        let jobFieldsAreUnchanged = draft.scheduleExpression == existing.schedule.source
            && draft.command == existing.command
            && draft.appleNotOnBattery == existing.appleNotOnBattery

        let metadataRaw: RawLine
        if existing.isManaged, nameIsUnchanged, let existingMetadata = existing.metadataRawLine {
            metadataRaw = existingMetadata
        } else {
            let terminator = existing.sourceRawLine.terminator == .none ? .lineFeed : existing.sourceRawLine.terminator
            metadataRaw = Self.metadataRaw(id: id, name: draft.name, terminator: terminator)
        }

        let originalRaw: RawLine
        if jobFieldsAreUnchanged {
            originalRaw = existing.originalJobRawLine
        } else {
            originalRaw = Self.jobRaw(
                draft: draft,
                schedule: schedule,
                terminator: existing.sourceRawLine.terminator
            )
        }

        let jobRaw = draft.isEnabled ? originalRaw : Self.disabledRaw(id: id, original: originalRaw)
        return LineEdit(range: range, replacement: [metadataRaw, jobRaw])
    }

    private static func validatedSchedule(for draft: ManagedCronJobDraft) throws -> CronSchedule {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ManagedCrontabError.emptyName }
        guard !draft.name.contains("\n"), !draft.name.contains("\r") else {
            throw ManagedCrontabError.nameContainsNewline
        }
        guard !draft.command.isEmpty else { throw ManagedCrontabError.emptyCommand }
        guard !draft.command.contains("\n"), !draft.command.contains("\r") else {
            throw ManagedCrontabError.commandContainsNewline
        }
        guard !draft.command.contains("\0") else { throw ManagedCrontabError.commandContainsNUL }

        let expression = draft.scheduleExpression.trimmingCharacters(in: .whitespacesAndNewlines)
        if let macro = CronMacro(rawValue: expression) {
            return .macro(macro)
        }

        let fields = expression.split(whereSeparator: \Character.isWhitespace).map(String.init)
        guard fields.count == 5 else {
            throw ManagedCrontabError.invalidSchedule(expression)
        }
        do {
            return .fields(
                try CronFields(
                    minute: fields[0],
                    hour: fields[1],
                    dayOfMonth: fields[2],
                    month: fields[3],
                    dayOfWeek: fields[4]
                )
            )
        } catch {
            throw ManagedCrontabError.invalidSchedule(expression)
        }
    }

    private static func jobRaw(
        draft: ManagedCronJobDraft,
        schedule: CronSchedule,
        terminator: LineTerminator
    ) -> RawLine {
        let commandPrefix = draft.appleNotOnBattery ? "@AppleNotOnBattery " : ""
        return RawLine(
            utf8Content: "\(schedule.source) \(commandPrefix)\(draft.command)",
            terminator: terminator
        )
    }

    private static func metadataRaw(id: CronJobID, name: String, terminator: LineTerminator) -> RawLine {
        let encodedName = Data(name.utf8).base64EncodedString()
        return RawLine(
            utf8Content: "# CronHarbor:job:\(id.rawValue):\(encodedName)",
            terminator: terminator
        )
    }

    private static func disabledRaw(id: CronJobID, original: RawLine) -> RawLine {
        var content = Data("# CronHarbor:disabled:\(id.rawValue):".utf8)
        content.append(original.content)
        return RawLine(content: content, terminator: original.terminator)
    }

    private static func metadata(from raw: RawLine) -> Metadata? {
        let prefix = "# CronHarbor:job:"
        guard let value = raw.utf8Content, value.hasPrefix(prefix) else { return nil }
        let remainder = value.dropFirst(prefix.count)
        guard let separator = remainder.firstIndex(of: ":") else { return nil }
        let idValue = String(remainder[..<separator])
        let encodedName = String(remainder[remainder.index(after: separator)...])
        guard Self.isValidManagedID(idValue),
              let nameData = Data(base64Encoded: encodedName),
              let name = String(data: nameData, encoding: .utf8),
              !name.isEmpty,
              !name.contains("\n"),
              !name.contains("\r")
        else {
            return nil
        }
        return Metadata(id: CronJobID(rawValue: idValue), name: name)
    }

    private static func disabledJob(from raw: RawLine, lineIndex: Int) -> DisabledProjection? {
        let prefix = Data("# CronHarbor:disabled:".utf8)
        guard raw.content.starts(with: prefix) else { return nil }
        let remainder = raw.content.dropFirst(prefix.count)
        guard let separator = remainder.firstIndex(of: UInt8(ascii: ":")) else { return nil }
        let idData = Data(remainder[..<separator])
        guard let idValue = String(data: idData, encoding: .utf8), Self.isValidManagedID(idValue) else {
            return nil
        }

        let originalContent = Data(remainder[remainder.index(after: separator)...])
        let originalRaw = RawLine(content: originalContent, terminator: raw.terminator)
        let parsed = CrontabDocument(data: originalRaw.renderedData)
        guard let parsedJob = parsed.jobs.first else { return nil }
        let job = CronJob(
            id: CronJobID(rawValue: idValue),
            sourceLineIndex: lineIndex,
            schedule: parsedJob.schedule,
            command: parsedJob.command,
            appleNotOnBattery: parsedJob.appleNotOnBattery
        )
        return DisabledProjection(id: job.id, job: job, originalRaw: originalRaw)
    }

    private static func isValidManagedID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { byte in
            (48...57).contains(byte)
                || (65...90).contains(byte)
                || (97...122).contains(byte)
                || byte == UInt8(ascii: "-")
        }
    }

    private static func inferredName(for job: CronJob, lineIndex: Int, document: CrontabDocument) -> String {
        if lineIndex > 0 {
            nameSearch: for priorIndex in stride(from: lineIndex - 1, through: 0, by: -1) {
                switch document.lines[priorIndex].kind {
                case .comment(let comment):
                    let text = comment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty, !text.hasPrefix("CronHarbor:") {
                        return String(text.prefix(80))
                    }
                case .blank, .environment:
                    continue
                case .job, .opaque:
                    break nameSearch
                }
            }
        }

        let command = job.command.trimmingCharacters(in: .whitespaces)
        if let token = command.split(whereSeparator: \Character.isWhitespace).first {
            let component = URL(fileURLWithPath: String(token)).lastPathComponent
            if !component.isEmpty {
                return String(component.prefix(80))
            }
        }
        return "Cron Job \(lineIndex + 1)"
    }

    private static func preferredTerminator(in lines: [RawLine]) -> LineTerminator {
        for line in lines.reversed() {
            if line.terminator != .none { return line.terminator }
        }
        return .lineFeed
    }
}

private struct Metadata {
    let id: CronJobID
    let name: String
}

private struct DisabledProjection {
    let id: CronJobID
    let job: CronJob
    let originalRaw: RawLine
}

private struct LineEdit {
    let range: Range<Int>
    let replacement: [RawLine]
}
