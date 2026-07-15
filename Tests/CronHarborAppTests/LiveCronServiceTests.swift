import Foundation
import Testing
@testable import CronHarbor
@testable import CronHarborCore

@Suite("Live cron service safety")
struct LiveCronServiceTests {
    private let id = "11111111-2222-3333-4444-555555555555"

    @Test("Run resolution refuses a command changed under the same managed ID")
    func rejectsChangedCommand() throws {
        let presented = presentation(command: "/bin/echo reviewed")
        let installed = managed(command: "/bin/echo substituted")

        #expect(throws: InstalledJobResolutionError.changed) {
            try LiveCronService.resolveInstalledJob(presented, in: installed)
        }
    }

    @Test("Run resolution refuses duplicate managed IDs")
    func rejectsAmbiguousIdentity() throws {
        let source = """
        # CronHarbor:job:\(id):Sm9i
        0 2 * * * /bin/echo reviewed
        # CronHarbor:job:\(id):Sm9i
        30 3 * * * /bin/echo another

        """

        #expect(throws: InstalledJobResolutionError.ambiguous) {
            try LiveCronService.resolveInstalledJob(
                presentation(command: "/bin/echo reviewed"),
                in: ManagedCrontab(data: Data(source.utf8))
            )
        }
    }

    @Test("Run resolution returns only an exact installed job")
    func acceptsExactInstalledJob() throws {
        let presented = presentation(command: "/bin/echo reviewed")

        let resolved = try LiveCronService.resolveInstalledJob(
            presented,
            in: managed(command: presented.command)
        )

        #expect(resolved.id.rawValue == presented.id)
        #expect(resolved.command == presented.command)
    }

    @Test("Opaque lines and duplicate identities become visible protected rows")
    func protectedSourceIsVisibleAndUnique() {
        let source = """
        # CronHarbor:job:\(id):Sm9i
        0 2 * * * /bin/one
        # CronHarbor:job:\(id):Sm9i
        0 3 * * * /bin/two
        invalid cron source

        """
        let rows = LiveCronService.presentations(
            from: ManagedCrontab(data: Data(source.utf8)),
            now: Date(timeIntervalSince1970: 0),
            nextRunCalculator: CronNextRunCalculator(),
            sourceRevision: "revision"
        )

        #expect(rows.count == 3)
        #expect(Set(rows.map(\.id)).count == 3)
        #expect(rows.allSatisfy { $0.diagnostic != nil })
        #expect(rows.contains { $0.name == "Protected Source Line 5" })
    }

    @Test("Truncated process output is explicit in persisted history text")
    func marksTruncatedOutput() {
        #expect(LiveCronService.recordedOutput(Data("partial".utf8), wasTruncated: false) == "partial")
        #expect(
            LiveCronService.recordedOutput(Data("partial".utf8), wasTruncated: true)
                == "partial\n[CronHarbor stopped retaining additional output after the 1 MiB capture limit.]\n"
        )
    }

    @Test("Run resolution binds preceding environment to the displayed revision")
    func rejectsChangedEffectiveEnvironment() throws {
        let original = Data("SHELL=/bin/sh\n0 2 * * * /bin/echo reviewed\n".utf8)
        let changed = Data("SHELL=/bin/zsh\n0 2 * * * /bin/echo reviewed\n".utf8)
        let originalManaged = ManagedCrontab(data: original)
        let originalJob = try #require(originalManaged.jobs.first)
        let originalRevision = CrontabDigest(contents: original).description
        let changedRevision = CrontabDigest(contents: changed).description
        let presented = JobPresentation(
            id: originalJob.id.rawValue,
            name: originalJob.name,
            expression: originalJob.schedule.source,
            command: originalJob.command,
            isEnabled: true,
            nextRun: nil,
            diagnostic: nil,
            isManaged: false,
            sourceRevision: originalRevision
        )

        #expect(throws: InstalledJobResolutionError.changed) {
            try LiveCronService.resolveInstalledJob(
                presented,
                in: ManagedCrontab(data: changed),
                currentRevision: changedRevision
            )
        }
    }

    private func managed(command: String) -> ManagedCrontab {
        let source = """
        # CronHarbor:job:\(id):Sm9i
        0 2 * * * \(command)

        """
        return ManagedCrontab(data: Data(source.utf8))
    }

    private func presentation(command: String) -> JobPresentation {
        JobPresentation(
            id: id,
            name: "Job",
            expression: "0 2 * * *",
            command: command,
            isEnabled: true,
            nextRun: nil,
            diagnostic: nil,
            isManaged: true
        )
    }
}
