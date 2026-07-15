import Foundation

actor BootstrapCronService: CronServiceProtocol {
    private let useDemoData: Bool

    init(useDemoData: Bool) {
        self.useDemoData = useDemoData
    }

    func load() async throws -> CronLoadResult {
        CronLoadResult(
            jobs: useDemoData ? Self.demoJobs : [],
            revision: "bootstrap",
            diagnostics: [],
            runHistory: useDemoData ? Self.demoHistory : []
        )
    }

    func apply(changes: [JobChange], basedOn revision: String) async throws -> CronLoadResult {
        throw BootstrapError.liveServiceUnavailable
    }

    func run(job: JobPresentation) async throws -> RunRecord {
        try await Task.sleep(for: .milliseconds(450))
        return RunRecord(
            id: UUID(),
            jobID: job.id,
            jobName: job.name,
            startedAt: .now,
            duration: 0.45,
            exitCode: 0,
            standardOutput: "Demo run completed.\n",
            standardError: ""
        )
    }

    enum BootstrapError: LocalizedError {
        case liveServiceUnavailable

        var errorDescription: String? {
            "The live crontab service is still starting. Refresh and try again."
        }
    }

    static let demoJobs: [JobPresentation] = [
        JobPresentation(
            id: "demo-backup",
            name: "Nightly Backup",
            expression: "0 2 * * *",
            command: "/usr/local/bin/backup.sh --all --compress",
            isEnabled: true,
            nextRun: .now.addingTimeInterval(3 * 3_600 + 18 * 60),
            diagnostic: nil,
            isManaged: true
        ),
        JobPresentation(
            id: "demo-cleanup",
            name: "Cleanup Logs",
            expression: "30 1 * * *",
            command: "/usr/bin/find ~/Library/Logs -name '*.log' -mtime +14 -delete",
            isEnabled: true,
            nextRun: .now.addingTimeInterval(2 * 3_600 + 48 * 60),
            diagnostic: nil,
            isManaged: false
        ),
        JobPresentation(
            id: "demo-sync",
            name: "Sync Documents",
            expression: "*/15 * * * *",
            command: "/usr/local/bin/sync-documents",
            isEnabled: true,
            nextRun: .now.addingTimeInterval(11 * 60),
            diagnostic: nil,
            isManaged: true
        ),
        JobPresentation(
            id: "demo-homebrew",
            name: "Update Homebrew",
            expression: "0 9 * * 0",
            command: "/opt/homebrew/bin/brew update",
            isEnabled: false,
            nextRun: nil,
            diagnostic: nil,
            isManaged: true
        ),
        JobPresentation(
            id: "demo-opaque",
            name: "Legacy deploy task",
            expression: "0 8 * * MON-FRI",
            command: "/usr/local/bin/deploy-old",
            isEnabled: true,
            nextRun: nil,
            diagnostic: "This line uses syntax CronHarbor will preserve but cannot safely edit.",
            isManaged: false
        )
    ]

    static let demoHistory: [RunRecord] = [
        RunRecord(
            id: UUID(uuidString: "7ea2fc04-20ea-4b21-8ee8-30ae4d84f670")!,
            jobID: "demo-backup",
            jobName: "Nightly Backup",
            startedAt: .now.addingTimeInterval(-86_400),
            duration: 2.14,
            exitCode: 0,
            standardOutput: "Backup completed.\n",
            standardError: ""
        )
    ]
}
