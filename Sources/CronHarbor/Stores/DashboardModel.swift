import AppKit
import Combine
import CronHarborCore
import Foundation

@MainActor
final class DashboardModel: ObservableObject {
    @Published var jobs: [JobPresentation] = []
    @Published var selectedJobID: String?
    @Published var selectedFilter: SidebarFilter = .all
    @Published var searchText = ""
    @Published var pendingChanges: [JobChange] = []
    @Published var runHistory: [RunRecord] = []
    @Published var isLoading = false
    @Published var isApplying = false
    @Published var runningJobID: String?
    @Published var lastError: String?
    @Published var diagnostics: [String] = []
    @Published var editorDraft: JobDraft?
    @Published var isEditorPresented = false

    private let service: any CronServiceProtocol
    private var revision = ""

    init(service: any CronServiceProtocol) {
        self.service = service
    }

    static func makeDefault() -> DashboardModel {
        let isDemo = ProcessInfo.processInfo.environment["CRONHARBOR_DEMO"] == "1"
        let service: any CronServiceProtocol = isDemo
            ? BootstrapCronService(useDemoData: true)
            : LiveCronService()
        let model = DashboardModel(service: service)
        Task { await model.refresh() }
        return model
    }

    var menuBarSymbol: String {
        if lastError != nil || jobs.contains(where: { $0.health == .warning }) {
            return "exclamationmark.anchor"
        }
        return runningJobID == nil ? "anchor.circle" : "arrow.trianglehead.2.clockwise.rotate.90.circle.fill"
    }

    var filteredJobs: [JobPresentation] {
        jobs.filter { job in
            let filterMatches: Bool
            switch selectedFilter {
            case .all: filterMatches = true
            case .active: filterMatches = job.isEnabled && job.diagnostic == nil
            case .paused: filterMatches = !job.isEnabled && job.diagnostic == nil
            case .attention: filterMatches = job.diagnostic != nil
            case .history: filterMatches = runHistory.contains(where: { $0.jobID == job.id })
            }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let searchMatches = query.isEmpty
                || job.name.localizedCaseInsensitiveContains(query)
                || job.command.localizedCaseInsensitiveContains(query)
                || job.expression.localizedCaseInsensitiveContains(query)
            return filterMatches && searchMatches
        }
        .sorted { lhs, rhs in
            switch (lhs.nextRun, rhs.nextRun) {
            case let (left?, right?): left < right
            case (.some, .none): true
            case (.none, .some): false
            case (.none, .none): lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }
    }

    var selectedJob: JobPresentation? {
        guard let selectedJobID else { return nil }
        return jobs.first(where: { $0.id == selectedJobID })
    }

    var activeJobs: [JobPresentation] {
        jobs.filter { $0.isEnabled && $0.diagnostic == nil }
    }

    var nextJobs: [JobPresentation] {
        upcomingJobs(after: .now)
    }

    var attentionCount: Int { jobs.count(where: { $0.diagnostic != nil }) }
    var healthSummary: String {
        attentionCount == 0 ? "\(activeJobs.count) active · All clear" : "\(attentionCount) need attention"
    }

    var isSourceBusy: Bool { isLoading || isApplying }

    func hasPendingChange(for job: JobPresentation) -> Bool {
        pendingChanges.contains { $0.targetID == job.id }
    }

    func count(for filter: SidebarFilter) -> Int {
        switch filter {
        case .all: jobs.count
        case .active: activeJobs.count
        case .paused: jobs.count(where: { !$0.isEnabled && $0.diagnostic == nil })
        case .attention: attentionCount
        case .history: runHistory.count
        }
    }

    /// Keeps time-derived presentation state current without rereading or
    /// modifying the installed crontab. Expired occurrences are recalculated;
    /// @reboot schedules and entries without a safe schedule remain nil.
    func refreshUpcomingRuns(at now: Date = .now) {
        for index in jobs.indices {
            guard jobs[index].isEnabled, jobs[index].diagnostic == nil else {
                jobs[index].nextRun = nil
                continue
            }
            if let nextRun = jobs[index].nextRun, nextRun > now {
                continue
            }
            jobs[index].nextRun = calculatedNextRun(
                for: jobs[index].expression,
                after: now
            )
        }
    }

    func upcomingJobs(after now: Date) -> [JobPresentation] {
        activeJobs
            .filter { job in
                guard let nextRun = job.nextRun else { return false }
                return nextRun > now
            }
            .sorted { ($0.nextRun ?? .distantFuture) < ($1.nextRun ?? .distantFuture) }
    }

    func refresh() async {
        guard !isLoading else { return }
        guard !isApplying else {
            lastError = "Wait for the current apply to finish before refreshing."
            return
        }
        guard pendingChanges.isEmpty else {
            lastError = "Apply or discard pending changes before refreshing. This keeps them based on the crontab you reviewed."
            return
        }
        guard !isEditorPresented else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await service.load()
            jobs = result.jobs
            revision = result.revision
            diagnostics = result.diagnostics
            runHistory = result.runHistory
            lastError = nil
            if selectedJobID == nil || !jobs.contains(where: { $0.id == selectedJobID }) {
                selectedJobID = filteredJobs.first?.id
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func beginCreatingJob() {
        guard !isSourceBusy else { return }
        editorDraft = JobDraft()
        isEditorPresented = true
        openDashboard()
    }

    func beginEditing(_ job: JobPresentation) {
        guard !isSourceBusy, job.diagnostic == nil else { return }
        editorDraft = JobDraft(job: job)
        isEditorPresented = true
    }

    func stage(_ draft: JobDraft) {
        guard !isSourceBusy else { return }
        if let id = draft.id {
            if let pendingCreateIndex = pendingChanges.firstIndex(where: { change in
                guard case .create(let pendingID, _) = change else { return false }
                return pendingID == id
            }) {
                pendingChanges[pendingCreateIndex] = .create(id: id, draft: draft)
            } else {
                pendingChanges.removeAll { $0.targetID == id }
                pendingChanges.append(.update(id: id, draft: draft))
            }
            if let index = jobs.firstIndex(where: { $0.id == id }) {
                jobs[index].name = draft.name
                jobs[index].expression = draft.expression
                jobs[index].command = draft.command
                jobs[index].isEnabled = draft.isEnabled
                jobs[index].requiresACPower = draft.requiresACPower
                jobs[index].nextRun = draft.isEnabled ? calculatedNextRun(for: draft.expression) : nil
            }
        } else {
            let temporaryID = "cronharbor-pending:\(UUID().uuidString)"
            var identifiedDraft = draft
            identifiedDraft.id = temporaryID
            pendingChanges.append(.create(id: temporaryID, draft: identifiedDraft))
            jobs.append(
                JobPresentation(
                    id: temporaryID,
                    name: identifiedDraft.name,
                    expression: identifiedDraft.expression,
                    command: identifiedDraft.command,
                    isEnabled: identifiedDraft.isEnabled,
                    nextRun: identifiedDraft.isEnabled ? calculatedNextRun(for: identifiedDraft.expression) : nil,
                    diagnostic: nil,
                    isManaged: true,
                    requiresACPower: identifiedDraft.requiresACPower
                )
            )
            selectedJobID = temporaryID
        }
        isEditorPresented = false
        editorDraft = nil
    }

    func stageToggle(_ job: JobPresentation) {
        guard !isSourceBusy else { return }
        var draft = JobDraft(job: job)
        draft.isEnabled.toggle()
        stage(draft)
    }

    func stageDelete(_ job: JobPresentation) {
        guard !isSourceBusy else { return }
        if pendingChanges.contains(where: { change in
            guard case .create(let id, _) = change else { return false }
            return id == job.id
        }) {
            pendingChanges.removeAll { $0.targetID == job.id }
            jobs.removeAll { $0.id == job.id }
            selectedJobID = filteredJobs.first?.id
            return
        }
        pendingChanges.removeAll { $0.targetID == job.id }
        pendingChanges.append(.delete(id: job.id))
        jobs.removeAll { $0.id == job.id }
        selectedJobID = filteredJobs.first?.id
    }

    func discardPendingChanges() async {
        guard !isSourceBusy else { return }
        pendingChanges.removeAll()
        await refresh()
    }

    func applyPendingChanges() async {
        guard !pendingChanges.isEmpty, !isSourceBusy else { return }
        let submittedChanges = pendingChanges
        let submittedRevision = revision
        isApplying = true
        defer { isApplying = false }
        do {
            let result = try await service.apply(changes: submittedChanges, basedOn: submittedRevision)
            guard pendingChanges == submittedChanges else {
                lastError = "Pending changes changed while apply was running. Refresh and review the installed crontab before continuing."
                return
            }
            jobs = result.jobs
            revision = result.revision
            diagnostics = result.diagnostics
            runHistory = result.runHistory
            pendingChanges.removeAll()
            lastError = nil
            selectedJobID = jobs.contains(where: { $0.id == selectedJobID }) ? selectedJobID : jobs.first?.id
        } catch {
            lastError = error.localizedDescription
        }
    }

    func runNow(_ job: JobPresentation) async {
        guard !isSourceBusy else { return }
        guard runningJobID == nil else { return }
        guard job.diagnostic == nil else {
            lastError = job.diagnostic
            return
        }
        guard !hasPendingChange(for: job) else {
            lastError = "Apply or discard this job’s pending changes before using Run Now."
            return
        }
        runningJobID = job.id
        defer { runningJobID = nil }
        do {
            let record = try await service.run(job: job)
            runHistory.insert(record, at: 0)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func openDashboard() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.title == "CronHarbor" }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func calculatedNextRun(
        for expression: String,
        after date: Date = .now
    ) -> Date? {
        let normalized = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        let schedule: CronSchedule

        if let macro = CronMacro(rawValue: normalized) {
            schedule = .macro(macro)
        } else {
            let parts = normalized.split(whereSeparator: \Character.isWhitespace).map(String.init)
            guard parts.count == 5,
                  let fields = try? CronFields(
                    minute: parts[0],
                    hour: parts[1],
                    dayOfMonth: parts[2],
                    month: parts[3],
                    dayOfWeek: parts[4]
                  )
            else {
                return nil
            }
            schedule = .fields(fields)
        }

        return CronNextRunCalculator().nextRun(for: schedule, after: date)
    }
}
