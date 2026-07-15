import Foundation
import Testing
@testable import CronHarbor

@Suite("Dashboard model", .serialized)
@MainActor
struct DashboardModelTests {
    @Test("Editing stages locally until explicit apply")
    func editRequiresExplicitApply() async throws {
        let original = Self.job()
        let fake = AppFakeCronService(loadResult: Self.result(jobs: [original]))
        let model = DashboardModel(service: fake)
        await model.refresh()

        var draft = JobDraft(job: original)
        draft.name = "Renamed"
        model.stage(draft)

        #expect(model.jobs.first?.name == "Renamed")
        #expect(model.pendingChanges == [.update(id: original.id, draft: draft)])
        #expect(await fake.appliedChanges().isEmpty)

        await fake.setApplyResult(Self.result(jobs: [Self.job(name: "Renamed")], revision: "r2"))
        await model.applyPendingChanges()

        #expect(model.pendingChanges.isEmpty)
        #expect(model.jobs.first?.name == "Renamed")
        let calls = await fake.appliedChanges()
        #expect(calls.count == 1)
        #expect(calls.first?.revision == "r1")
    }

    @Test("Apply failure keeps pending changes visible")
    func applyFailureKeepsDraft() async {
        let original = Self.job()
        let fake = AppFakeCronService(loadResult: Self.result(jobs: [original]))
        let model = DashboardModel(service: fake)
        await model.refresh()
        var draft = JobDraft(job: original)
        draft.isEnabled = false
        model.stage(draft)
        await fake.setApplyError(FakeServiceError.conflict)

        await model.applyPendingChanges()

        #expect(model.pendingChanges.count == 1)
        #expect(model.lastError == FakeServiceError.conflict.localizedDescription)
    }

    @Test("Run Now records only app-started execution")
    func runNowAddsHistory() async {
        let original = Self.job()
        let fake = AppFakeCronService(loadResult: Self.result(jobs: [original]))
        let model = DashboardModel(service: fake)
        await model.refresh()

        await model.runNow(original)

        #expect(model.runHistory.count == 1)
        #expect(model.runHistory.first?.jobID == original.id)
        #expect(model.runningJobID == nil)
    }

    @Test("Run Now refuses a staged version whose installed command may differ")
    func runNowRejectsPendingJob() async {
        let original = Self.job()
        let fake = AppFakeCronService(loadResult: Self.result(jobs: [original]))
        let model = DashboardModel(service: fake)
        await model.refresh()
        var draft = JobDraft(job: original)
        draft.command = "/bin/echo staged"
        model.stage(draft)

        let staged = model.jobs[0]
        await model.runNow(staged)

        #expect(model.hasPendingChange(for: staged))
        #expect(model.runHistory.isEmpty)
        #expect(await fake.runJobIDs().isEmpty)
        #expect(model.lastError == "Apply or discard this job’s pending changes before using Run Now.")
    }

    @Test("Refresh refuses to rebase pending changes onto a newer revision")
    func refreshRejectsPendingChanges() async {
        let original = Self.job()
        let fake = AppFakeCronService(loadResult: Self.result(jobs: [original]))
        let model = DashboardModel(service: fake)
        await model.refresh()
        var draft = JobDraft(job: original)
        draft.name = "Staged Name"
        model.stage(draft)

        await fake.setLoadResult(Self.result(jobs: [Self.job(name: "External Name")], revision: "r2"))
        await model.refresh()

        #expect(model.jobs.first?.name == "Staged Name")
        #expect(model.pendingChanges == [.update(id: original.id, draft: draft)])
        #expect(model.lastError == "Apply or discard pending changes before refreshing. This keeps them based on the crontab you reviewed.")
    }

    @Test("Discard restores the installed snapshot when reload fails")
    func discardFailureDoesNotExposeProjectedJobsAsInstalled() async {
        let original = Self.job()
        let fake = AppFakeCronService(loadResult: Self.result(jobs: [original]))
        let model = DashboardModel(service: fake)
        await model.refresh()
        var draft = JobDraft(job: original)
        draft.name = "Projected Only"
        draft.expression = "*/5 * * * *"
        model.stage(draft)
        await fake.setLoadError(FakeServiceError.conflict)

        await model.discardPendingChanges()

        #expect(model.pendingChanges.isEmpty)
        #expect(model.jobs == [original])
        #expect(model.lastError == FakeServiceError.conflict.localizedDescription)
    }

    @Test("Upcoming installed job ignores a staged pause projection")
    func installedUpcomingRunRemainsAuthoritativeWhileStaged() async {
        let original = Self.job()
        let fake = AppFakeCronService(loadResult: Self.result(jobs: [original]))
        let model = DashboardModel(service: fake)
        await model.refresh()

        model.stageToggle(original)

        #expect(model.nextJobs.isEmpty)
        #expect(model.installedNextJobs.map(\.id) == [original.id])
    }

    @Test("Creating and cancelling is a pure editor state transition")
    func createCancelDoesNotMutateJobs() async {
        let original = Self.job()
        let fake = AppFakeCronService(loadResult: Self.result(jobs: [original]))
        let model = DashboardModel(service: fake)
        await model.refresh()

        model.beginCreatingJob()
        model.editorDraft?.name = "Unstaged scratch"
        model.editorDraft?.command = "/bin/echo scratch"

        #expect(model.isEditorPresented)
        #expect(model.jobs == [original])
        #expect(model.pendingChanges.isEmpty)

        model.cancelEditing()

        #expect(!model.isEditorPresented)
        #expect(model.editorDraft == nil)
        #expect(model.jobs == [original])
        #expect(model.pendingChanges.isEmpty)
    }

    @Test("Cancelling an edit leaves the source presentation unchanged")
    func editCancelDoesNotMutateJob() async {
        let original = Self.job()
        let fake = AppFakeCronService(loadResult: Self.result(jobs: [original]))
        let model = DashboardModel(service: fake)
        await model.refresh()

        model.beginEditing(original)
        model.editorDraft?.name = "Never staged"
        model.editorDraft?.expression = "*/5 * * * *"
        model.cancelEditing()

        #expect(model.jobs == [original])
        #expect(model.pendingChanges.isEmpty)
    }

    @Test("Refresh does not overwrite a model-backed editor draft")
    func refreshPreservesEditorSession() async {
        let original = Self.job()
        let fake = AppFakeCronService(loadResult: Self.result(jobs: [original]))
        let model = DashboardModel(service: fake)
        await model.refresh()
        model.beginEditing(original)
        model.editorDraft?.name = "Work in progress"
        await fake.setLoadResult(Self.result(jobs: [Self.job(name: "External Name")], revision: "r2"))

        await model.refresh()

        #expect(model.editorDraft?.name == "Work in progress")
        #expect(model.jobs == [original])
        #expect(model.pendingChanges.isEmpty)
    }

    @Test("Deleting an updated job reviews the installed target snapshot")
    func updateThenDeleteRetainsInstalledSnapshot() async throws {
        let original = Self.job()
        let fake = AppFakeCronService(loadResult: Self.result(jobs: [original]))
        let model = DashboardModel(service: fake)
        await model.refresh()

        var draft = JobDraft(job: original)
        draft.name = "Renamed Before Delete"
        model.stage(draft)
        model.stageDelete(try #require(model.jobs.first))

        #expect(model.pendingChanges == [
            .delete(id: original.id, snapshot: JobDeletionSnapshot(job: original))
        ])
        #expect(model.jobs.isEmpty)
    }

    @Test("A pending create can be edited, toggled, and deleted before apply")
    func pendingCreateReducesLocally() async throws {
        let fake = AppFakeCronService(loadResult: Self.result(jobs: []))
        let model = DashboardModel(service: fake)
        await model.refresh()

        var draft = JobDraft()
        draft.name = "New Job"
        draft.command = "/bin/echo first"
        model.stage(draft)
        let temporaryID = try #require(model.jobs.first?.id)

        var edited = JobDraft(job: try #require(model.jobs.first))
        edited.command = "/bin/echo edited"
        model.stage(edited)
        #expect(model.pendingChanges == [.create(id: temporaryID, draft: edited)])
        #expect(model.jobs.first?.command == "/bin/echo edited")

        model.stageToggle(try #require(model.jobs.first))
        guard case let .create(id, toggledDraft) = try #require(model.pendingChanges.first) else {
            Issue.record("Expected one reduced create change")
            return
        }
        #expect(id == temporaryID)
        #expect(!toggledDraft.isEnabled)
        #expect(model.pendingChanges.count == 1)

        model.stageDelete(try #require(model.jobs.first))
        #expect(model.pendingChanges.isEmpty)
        #expect(model.jobs.isEmpty)
    }

    @Test("Mutation entry points refuse changes while apply is in flight")
    func mutationsAreGuardedDuringApply() async {
        let original = Self.job()
        let fake = AppFakeCronService(loadResult: Self.result(jobs: [original]))
        let model = DashboardModel(service: fake)
        await model.refresh()
        model.isApplying = true

        var draft = JobDraft(job: original)
        draft.name = "Must Not Stage"
        model.stage(draft)
        model.stageToggle(original)
        model.stageDelete(original)
        model.beginCreatingJob()

        #expect(model.pendingChanges.isEmpty)
        #expect(model.jobs == [original])
        #expect(!model.isEditorPresented)
    }

    @Test("Filters remain deterministic")
    func filtersJobs() async {
        let jobs = [
            Self.job(id: "active", name: "Active"),
            Self.job(id: "paused", name: "Paused", isEnabled: false),
            Self.job(id: "warning", name: "Warning", diagnostic: "Protected")
        ]
        let fake = AppFakeCronService(loadResult: Self.result(jobs: jobs))
        let model = DashboardModel(service: fake)
        await model.refresh()

        model.selectedFilter = .paused
        #expect(model.filteredJobs.map(\.id) == ["paused"])
        model.selectedFilter = .attention
        #expect(model.filteredJobs.map(\.id) == ["warning"])
        model.selectedFilter = .all
        model.searchText = "act"
        #expect(model.filteredJobs.map(\.id) == ["active"])
    }

    @Test("Expired upcoming occurrences are hidden and recalculated")
    func refreshesUpcomingRuns() async throws {
        let now = Date(timeIntervalSince1970: 1_735_689_660)
        var stale = Self.job()
        stale.expression = "0 * * * *"
        stale.nextRun = now.addingTimeInterval(-1)
        let fake = AppFakeCronService(loadResult: Self.result(jobs: [stale]))
        let model = DashboardModel(service: fake)
        await model.refresh()

        #expect(model.upcomingJobs(after: now).isEmpty)

        model.refreshUpcomingRuns(at: now)

        let nextRun = try #require(model.jobs.first?.nextRun)
        #expect(nextRun > now)
        #expect(model.upcomingJobs(after: now).map(\.id) == [stale.id])
    }

    @Test("Run history store is private and bounded")
    func runHistoryStorePermissionsAndRetention() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CronHarborHistoryTests-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("history.json")

        // Simulate storage created by an older version with permissive modes.
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o777)],
            ofItemAtPath: directory.path
        )
        try Data("[]".utf8).write(to: fileURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o666)],
            ofItemAtPath: fileURL.path
        )

        let store = RunHistoryStore(fileURL: fileURL, maximumRecords: 2)

        for index in 0..<3 {
            try await store.append(
                RunRecord(
                    id: UUID(),
                    jobID: "job",
                    jobName: "Job",
                    startedAt: Date(timeIntervalSince1970: TimeInterval(index)),
                    duration: 1,
                    exitCode: 0,
                    standardOutput: "",
                    standardError: ""
                )
            )
        }

        #expect(await store.load().count == 2)
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
        #expect(permissions.intValue & 0o777 == 0o600)

        let directoryAttributes = try FileManager.default.attributesOfItem(
            atPath: directory.path
        )
        let directoryPermissions = try #require(
            directoryAttributes[.posixPermissions] as? NSNumber
        )
        #expect(directoryPermissions.intValue & 0o777 == 0o700)

        let storedItems = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        #expect(storedItems.map(\.lastPathComponent) == ["history.json"])
    }

    private static func job(
        id: String = "job-1",
        name: String = "Nightly Backup",
        isEnabled: Bool = true,
        diagnostic: String? = nil
    ) -> JobPresentation {
        JobPresentation(
            id: id,
            name: name,
            expression: "0 2 * * *",
            command: "/bin/echo backup",
            isEnabled: isEnabled,
            nextRun: Date(timeIntervalSince1970: 2_000_000_000),
            diagnostic: diagnostic,
            isManaged: true
        )
    }

    private static func result(
        jobs: [JobPresentation],
        revision: String = "r1"
    ) -> CronLoadResult {
        CronLoadResult(jobs: jobs, revision: revision, diagnostics: [], runHistory: [])
    }
}

private actor AppFakeCronService: CronServiceProtocol {
    struct ApplyCall: Sendable {
        let changes: [JobChange]
        let revision: String
    }

    private var loadResult: CronLoadResult
    private var loadError: (any Error & Sendable)?
    private var applyResult: CronLoadResult
    private var applyError: (any Error & Sendable)?
    private var applyCalls: [ApplyCall] = []
    private var runCalls: [String] = []

    init(loadResult: CronLoadResult) {
        self.loadResult = loadResult
        self.applyResult = loadResult
    }

    func load() async throws -> CronLoadResult {
        if let loadError { throw loadError }
        return loadResult
    }

    func apply(changes: [JobChange], basedOn revision: String) async throws -> CronLoadResult {
        applyCalls.append(ApplyCall(changes: changes, revision: revision))
        if let applyError { throw applyError }
        loadResult = applyResult
        return applyResult
    }

    func run(job: JobPresentation) async throws -> RunRecord {
        runCalls.append(job.id)
        return RunRecord(
            id: UUID(),
            jobID: job.id,
            jobName: job.name,
            startedAt: .now,
            duration: 0.1,
            exitCode: 0,
            standardOutput: "ok",
            standardError: ""
        )
    }

    func setApplyResult(_ result: CronLoadResult) {
        applyResult = result
    }

    func setLoadResult(_ result: CronLoadResult) {
        loadResult = result
    }

    func setLoadError(_ error: any Error & Sendable) {
        loadError = error
    }

    func setApplyError(_ error: any Error & Sendable) {
        applyError = error
    }

    func appliedChanges() -> [ApplyCall] { applyCalls }

    func runJobIDs() -> [String] { runCalls }
}

private enum FakeServiceError: LocalizedError, Sendable {
    case conflict

    var errorDescription: String? { "External conflict" }
}
