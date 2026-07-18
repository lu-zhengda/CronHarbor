import CronHarborCore
import Foundation

actor LiveCronService: CronServiceProtocol {
    private let repository: CrontabRepository
    private let runExecutor: RunNowExecutor
    private let invocationBuilder: CronRunInvocationBuilder
    private let historyStore: RunHistoryStore
    private let nextRunCalculator: CronNextRunCalculator

    init() {
        repository = CrontabRepository(
            client: SystemCrontabClient(),
            backupDirectoryURL: AppSupportPaths.backupsDirectory
        )
        runExecutor = RunNowExecutor()
        invocationBuilder = CronRunInvocationBuilder()
        historyStore = RunHistoryStore(fileURL: AppSupportPaths.runHistoryFile)
        nextRunCalculator = CronNextRunCalculator()
    }

    func load() async throws -> CronLoadResult {
        do {
            let snapshot = try await repository.read()
            return await makeResult(from: snapshot)
        } catch {
            throw LiveCronServiceError.readFailed(Self.message(for: error))
        }
    }

    func apply(changes: [JobChange], basedOn revision: String) async throws -> CronLoadResult {
        guard !changes.isEmpty else { return try await load() }

        do {
            let snapshot = try await repository.read()
            guard snapshot.digest.description == revision else {
                throw LiveCronServiceError.externalConflict
            }

            let document = ManagedCrontab(data: snapshot.contents)
            let mutations = changes.map(Self.mutation(from:))
            let candidate = try document.applying(mutations)
            let receipt = try await repository.install(
                contents: candidate,
                expectedDigest: snapshot.digest
            )
            return await makeResult(from: receipt.snapshot)
        } catch let error as LiveCronServiceError {
            throw error
        } catch CrontabRepositoryError.conflict {
            throw LiveCronServiceError.externalConflict
        } catch CrontabRepositoryError.installedStateUnknown(let backupURL) {
            throw LiveCronServiceError.installedStateUnknown(backupURL)
        } catch CrontabRepositoryError.readbackMismatch(_, _, let backupURL) {
            throw LiveCronServiceError.readbackMismatch(backupURL)
        } catch {
            throw LiveCronServiceError.applyFailed(Self.message(for: error))
        }
    }

    func run(job: JobPresentation) async throws -> RunRecord {
        do {
            let snapshot = try await repository.read()
            let managed = ManagedCrontab(data: snapshot.contents)
            let managedJob: ManagedCronJob
            do {
                managedJob = try Self.resolveInstalledJob(
                    job,
                    in: managed,
                    currentRevision: snapshot.digest.description
                )
            } catch InstalledJobResolutionError.missing {
                throw LiveCronServiceError.jobNoLongerExists
            } catch InstalledJobResolutionError.ambiguous {
                throw LiveCronServiceError.jobIdentityIsAmbiguous
            } catch InstalledJobResolutionError.changed {
                throw LiveCronServiceError.jobChangedSinceConfirmation
            }

            let invocation = try invocationBuilder.makeInvocation(
                for: managedJob.cronJob,
                in: managed.document
            )
            let startedAt = Date()
            let result = try await runExecutor.execute(invocation)
            let record = RunRecord(
                id: UUID(),
                jobID: job.id,
                jobName: job.name,
                startedAt: startedAt,
                duration: Date().timeIntervalSince(startedAt),
                exitCode: result.terminationStatus,
                standardOutput: Self.recordedOutput(
                    result.standardOutput,
                    wasTruncated: result.standardOutputWasTruncated
                ),
                standardError: Self.recordedOutput(
                    result.standardError,
                    wasTruncated: result.standardErrorWasTruncated
                )
            )
            try await historyStore.append(record)
            return record
        } catch let error as LiveCronServiceError {
            throw error
        } catch {
            throw LiveCronServiceError.runFailed(Self.message(for: error))
        }
    }

    func clearRunHistory() async throws {
        try await historyStore.clear()
    }

    /// Restores a private backup through the same digest-checked install path
    /// as a normal apply, so the current crontab is itself backed up first and
    /// the write is refused if the source changes mid-flight.
    func restoreBackup(from url: URL) async throws -> CronLoadResult {
        let backupContents: Data
        do {
            backupContents = try Data(contentsOf: url)
        } catch {
            throw LiveCronServiceError.backupUnreadable(url)
        }

        do {
            let snapshot = try await repository.read()
            let receipt = try await repository.install(
                contents: backupContents,
                expectedDigest: snapshot.digest
            )
            return await makeResult(from: receipt.snapshot)
        } catch CrontabRepositoryError.conflict {
            throw LiveCronServiceError.externalConflict
        } catch CrontabRepositoryError.installedStateUnknown(let backupURL) {
            throw LiveCronServiceError.installedStateUnknown(backupURL)
        } catch CrontabRepositoryError.readbackMismatch(_, _, let backupURL) {
            throw LiveCronServiceError.readbackMismatch(backupURL)
        } catch let error as LiveCronServiceError {
            throw error
        } catch {
            throw LiveCronServiceError.restoreFailed(Self.message(for: error))
        }
    }

    private func makeResult(from snapshot: CrontabSnapshot) async -> CronLoadResult {
        let managed = ManagedCrontab(data: snapshot.contents)
        let jobs = Self.presentations(
            from: managed,
            now: Date(),
            nextRunCalculator: nextRunCalculator,
            sourceRevision: snapshot.digest.description
        )
        var diagnostics = managed.opaqueLineIndices.map { lineIndex in
            "Line \(lineIndex + 1) is preserved exactly because its syntax is not safe to edit."
        }
        diagnostics.append(contentsOf: managed.ambiguousJobIDs.map { id in
            "Managed identity \(id.rawValue) appears more than once. Those entries are protected from editing and Run Now."
        })
        return CronLoadResult(
            jobs: jobs,
            revision: snapshot.digest.description,
            diagnostics: diagnostics,
            runHistory: await historyStore.load()
        )
    }

    static func presentations(
        from managed: ManagedCrontab,
        now: Date,
        nextRunCalculator: CronNextRunCalculator,
        sourceRevision: String
    ) -> [JobPresentation] {
        let jobs = managed.jobs.map { job in
            let isAmbiguous = managed.ambiguousJobIDs.contains(job.id)
            return JobPresentation(
                id: isAmbiguous
                    ? "cronharbor-protected-identity:\(job.id.rawValue):line:\(job.sourceLineIndex + 1)"
                    : job.id.rawValue,
                name: job.name,
                expression: job.schedule.source,
                command: job.command,
                isEnabled: job.isEnabled,
                nextRun: job.isEnabled && !isAmbiguous
                    ? nextRunCalculator.nextRun(for: job.schedule, after: now)
                    : nil,
                diagnostic: isAmbiguous
                    ? "Duplicate CronHarbor identity. This entry is preserved and cannot be edited or run."
                    : nil,
                isManaged: job.isManaged,
                requiresACPower: job.appleNotOnBattery,
                sourceRevision: sourceRevision
            )
        }
        let protectedSource = managed.opaqueLineIndices.map { lineIndex in
            JobPresentation(
                id: "cronharbor-protected-source-line:\(lineIndex + 1)",
                name: "Protected Source Line \(lineIndex + 1)",
                expression: "Opaque source",
                command: "Preserved exactly; content is not displayed.",
                isEnabled: false,
                nextRun: nil,
                diagnostic: "This line uses syntax CronHarbor cannot edit safely.",
                isManaged: false,
                requiresACPower: false,
                sourceRevision: sourceRevision
            )
        }
        return jobs + protectedSource
    }

    private static func mutation(from change: JobChange) -> ManagedCronMutation {
        switch change {
        case .create(_, let draft):
            return .create(coreDraft(from: draft))
        case .update(let id, let draft):
            return .update(id: CronJobID(rawValue: id), draft: coreDraft(from: draft))
        case .delete(let id, _):
            return .delete(id: CronJobID(rawValue: id))
        }
    }

    static func resolveInstalledJob(
        _ presented: JobPresentation,
        in managed: ManagedCrontab,
        currentRevision: String? = nil
    ) throws -> ManagedCronJob {
        if let currentRevision,
           presented.sourceRevision != currentRevision {
            throw InstalledJobResolutionError.changed
        }
        let matches = managed.jobs.filter { $0.id.rawValue == presented.id }
        guard !matches.isEmpty else { throw InstalledJobResolutionError.missing }
        guard matches.count == 1, let installed = matches.first else {
            throw InstalledJobResolutionError.ambiguous
        }
        guard installed.name == presented.name,
              installed.schedule.source == presented.expression,
              installed.command == presented.command,
              installed.isEnabled == presented.isEnabled,
              installed.isManaged == presented.isManaged,
              installed.appleNotOnBattery == presented.requiresACPower
        else {
            throw InstalledJobResolutionError.changed
        }
        return installed
    }

    static func recordedOutput(_ data: Data, wasTruncated: Bool) -> String {
        var output = String(decoding: data, as: UTF8.self)
        if wasTruncated {
            if !output.isEmpty, !output.hasSuffix("\n") { output.append("\n") }
            output.append("[CronHarbor stopped retaining additional output after the 1 MiB capture limit.]\n")
        }
        return output
    }

    private static func coreDraft(from draft: JobDraft) -> ManagedCronJobDraft {
        ManagedCronJobDraft(
            name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            scheduleExpression: draft.expression,
            command: draft.command,
            isEnabled: draft.isEnabled,
            appleNotOnBattery: draft.requiresACPower
        )
    }

    private static func message(for error: any Error) -> String {
        if let localized = error as? any LocalizedError,
           let description = localized.errorDescription {
            return description
        }
        return String(describing: error)
    }
}

private enum LiveCronServiceError: LocalizedError, Sendable {
    case externalConflict
    case installedStateUnknown(URL)
    case readbackMismatch(URL)
    case jobNoLongerExists
    case jobIdentityIsAmbiguous
    case jobChangedSinceConfirmation
    case readFailed(String)
    case applyFailed(String)
    case runFailed(String)
    case backupUnreadable(URL)
    case restoreFailed(String)

    var errorDescription: String? {
        switch self {
        case .externalConflict:
            "Your crontab changed in another app. CronHarbor did not overwrite it. Discard the pending changes, refresh, then stage them again against the current source."
        case .installedStateUnknown(let backupURL):
            "CronHarbor submitted the new crontab, but macOS could not confirm what is installed. Discard pending changes and refresh before making another change. Your previous crontab is backed up at \(backupURL.path)."
        case .readbackMismatch(let backupURL):
            "The installed crontab did not match the candidate CronHarbor submitted. Discard pending changes and refresh to inspect the live state. Your previous crontab is backed up at \(backupURL.path)."
        case .jobNoLongerExists:
            "This job no longer exists in the current crontab. Refresh before running it."
        case .jobIdentityIsAmbiguous:
            "More than one installed job uses this CronHarbor identity. Nothing was run. Repair the duplicate metadata before trying again."
        case .jobChangedSinceConfirmation:
            "This installed job changed after it was displayed. Nothing was run. Refresh and confirm the current command."
        case .readFailed(let message):
            "CronHarbor could not read your user crontab: \(message)"
        case .applyFailed(let message):
            "CronHarbor could not complete the apply: \(message). Pending changes remain staged; discard them before refreshing the installed state."
        case .runFailed(let message):
            "The job could not be started: \(message)"
        case .backupUnreadable(let url):
            "CronHarbor could not read the backup at \(url.path). Nothing was changed."
        case .restoreFailed(let message):
            "CronHarbor could not restore the backup: \(message). Refresh to inspect the installed crontab."
        }
    }
}

enum InstalledJobResolutionError: Error, Equatable {
    case missing
    case ambiguous
    case changed
}
