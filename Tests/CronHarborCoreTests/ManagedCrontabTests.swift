import Foundation
import Testing
@testable import CronHarborCore

@Suite("Managed crontab editing")
struct ManagedCrontabTests {
    private let fixedUUID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    @Test("Projection is lossless for untouched source")
    func projectionRoundTripsUntouchedSource() {
        var source = Data("# backup\r\nPATH=/opt/homebrew/bin:/usr/bin\r\n0\t2 * * * /bin/echo 'hello # world'\r\n".utf8)
        source.append(contentsOf: [0xFF, 0xFE, 0x0A])

        let managed = ManagedCrontab(data: source)

        #expect(managed.renderedData() == source)
        #expect(managed.jobs.count == 1)
        #expect(managed.jobs.first?.name == "backup")
        #expect(managed.opaqueLineIndices == [3])
    }

    @Test("Creating the first job emits transparent metadata")
    func createsFirstJob() throws {
        let managed = ManagedCrontab(data: Data())
        let draft = ManagedCronJobDraft(
            name: "Nightly Backup",
            scheduleExpression: "0 2 * * *",
            command: "/usr/local/bin/backup --all",
            isEnabled: true
        )

        let result = try managed.applying([.create(draft)], generateID: { fixedUUID })
        let expected = """
        # CronHarbor:job:11111111-2222-3333-4444-555555555555:TmlnaHRseSBCYWNrdXA=
        0 2 * * * /usr/local/bin/backup --all

        """

        #expect(result == Data(expected.utf8))
        let reparsed = ManagedCrontab(data: result)
        #expect(reparsed.jobs.first?.name == "Nightly Backup")
        #expect(reparsed.jobs.first?.isManaged == true)
    }

    @Test("Appending adds only the required line boundary")
    func appendsAfterUnterminatedLine() throws {
        let source = Data("MAILTO=me@example.com".utf8)
        let managed = ManagedCrontab(data: source)
        let draft = ManagedCronJobDraft(
            name: "Ping",
            scheduleExpression: "@hourly",
            command: "/bin/echo ping",
            isEnabled: true
        )

        let result = try managed.applying([.create(draft)], generateID: { fixedUUID })
        let string = String(decoding: result, as: UTF8.self)

        #expect(string.hasPrefix("MAILTO=me@example.com\n"))
        #expect(string.hasSuffix("@hourly /bin/echo ping\n"))
    }

    @Test("AC-power jobs use the documented macOS command prefix position")
    func writesAppleNotOnBatteryAfterSchedule() throws {
        let cases: [(draft: ManagedCronJobDraft, expectedJobLine: String)] = [
            (
                ManagedCronJobDraft(
                    name: "Field Schedule",
                    scheduleExpression: "0 2 * * *",
                    command: "/bin/field-job",
                    isEnabled: true,
                    appleNotOnBattery: true
                ),
                "0 2 * * * @AppleNotOnBattery /bin/field-job\n"
            ),
            (
                ManagedCronJobDraft(
                    name: "Macro Schedule",
                    scheduleExpression: "@hourly",
                    command: "/bin/macro-job",
                    isEnabled: true,
                    appleNotOnBattery: true
                ),
                "@hourly @AppleNotOnBattery /bin/macro-job\n"
            ),
        ]

        for testCase in cases {
            let result = try ManagedCrontab(data: Data()).applying(
                [.create(testCase.draft)],
                generateID: { fixedUUID }
            )
            let expectedJobLine = Data(testCase.expectedJobLine.utf8)
            #expect(result.suffix(expectedJobLine.count) == expectedJobLine)

            let reparsed = ManagedCrontab(data: result)
            let job = try #require(reparsed.jobs.first)
            #expect(job.schedule.source == testCase.draft.scheduleExpression)
            #expect(job.command == testCase.draft.command)
            #expect(job.appleNotOnBattery)
            #expect(reparsed.renderedData() == result)
        }
    }

    @Test("Pausing retains the exact original job bytes")
    func pausesLosslessly() throws {
        let source = Data("# Backup\r\n\t0\t2 * * *   /bin/echo 'hello # world'\r\n".utf8)
        let managed = ManagedCrontab(data: source)
        let job = try #require(managed.jobs.first)
        let draft = ManagedCronJobDraft(
            name: job.name,
            scheduleExpression: job.schedule.source,
            command: job.command,
            isEnabled: false
        )

        let result = try managed.applying([.update(id: job.id, draft: draft)], generateID: { fixedUUID })
        let reparsed = ManagedCrontab(data: result)
        let paused = try #require(reparsed.jobs.first)

        #expect(paused.isEnabled == false)
        #expect(paused.originalJobRawLine.content == Data("\t0\t2 * * *   /bin/echo 'hello # world'".utf8))
        #expect(result.starts(with: Data("# Backup\r\n# CronHarbor:job:".utf8)))
    }

    @Test("Enabling a paused job restores its original bytes")
    func enablesLosslessly() throws {
        let id = "11111111-2222-3333-4444-555555555555"
        let source = Data("# CronHarbor:job:\(id):QmFja3Vw\r\n# CronHarbor:disabled:\(id):\t0\t2 * * *   /bin/echo hello\r\n".utf8)
        let managed = ManagedCrontab(data: source)
        let job = try #require(managed.jobs.first)
        let draft = ManagedCronJobDraft(
            name: job.name,
            scheduleExpression: job.schedule.source,
            command: job.command,
            isEnabled: true
        )

        let result = try managed.applying([.update(id: job.id, draft: draft)])
        let expected = Data("# CronHarbor:job:\(id):QmFja3Vw\r\n\t0\t2 * * *   /bin/echo hello\r\n".utf8)

        #expect(result == expected)
    }

    @Test("Editing changes only the target block")
    func editsOnlyTarget() throws {
        let id = "11111111-2222-3333-4444-555555555555"
        let untouched = "# leave this exactly\nMAILTO=dev@example.com\n"
        let source = Data((untouched + "# CronHarbor:job:\(id):T2xkIE5hbWU=\n0 1 * * * /bin/old\n# trailing\n").utf8)
        let managed = ManagedCrontab(data: source)
        let draft = ManagedCronJobDraft(
            name: "New Name",
            scheduleExpression: "30 3 * * *",
            command: "/bin/new --flag",
            isEnabled: true
        )

        let result = try managed.applying([.update(id: CronJobID(rawValue: id), draft: draft)])
        let text = String(decoding: result, as: UTF8.self)

        #expect(text.hasPrefix(untouched))
        #expect(text.hasSuffix("# trailing\n"))
        #expect(text.contains("30 3 * * * /bin/new --flag\n"))
        #expect(!text.contains("/bin/old"))
    }

    @Test("Unchanged managed metadata retains its exact bytes")
    func preservesUnchangedMetadataBytes() throws {
        let id = "11111111-2222-3333-4444-555555555555"
        let marker = "# CronHarbor:job:\(id):Sm9i\r\n"
        let source = Data((marker + "0 1 * * * /bin/old\r\n").utf8)
        let managed = ManagedCrontab(data: source)
        let job = try #require(managed.jobs.first)
        let draft = ManagedCronJobDraft(
            name: "Job",
            scheduleExpression: "30 2 * * *",
            command: "/bin/new",
            isEnabled: true
        )

        let result = try managed.applying([.update(id: job.id, draft: draft)])

        #expect(result.starts(with: Data(marker.utf8)))
        #expect(result == Data((marker + "30 2 * * * /bin/new\r\n").utf8))
    }

    @Test("Deleting removes only marker and target")
    func deletesManagedBlock() throws {
        let id = CronJobID(rawValue: "11111111-2222-3333-4444-555555555555")
        let source = Data("before\n# CronHarbor:job:\(id.rawValue):Sm9i\n0 1 * * * /bin/job\nafter\n".utf8)
        let managed = ManagedCrontab(data: source)

        let result = try managed.applying([.delete(id: id)])

        #expect(result == Data("before\nafter\n".utf8))
    }

    @Test("Invalid drafts never produce candidate bytes", arguments: [
        ManagedCronJobDraft(name: "", scheduleExpression: "0 1 * * *", command: "/bin/job", isEnabled: true),
        ManagedCronJobDraft(name: "Job", scheduleExpression: "*/0 * * * *", command: "/bin/job", isEnabled: true),
        ManagedCronJobDraft(name: "Job", scheduleExpression: "0 1 * * *", command: "", isEnabled: true),
        ManagedCronJobDraft(name: "Job", scheduleExpression: "0 1 * * *", command: "/bin/echo hi\n/bin/rm", isEnabled: true)
    ])
    func rejectsInvalidDraft(draft: ManagedCronJobDraft) {
        #expect(throws: (any Error).self) {
            try ManagedCrontab(data: Data()).applying([.create(draft)], generateID: { fixedUUID })
        }
    }

    @Test("Duplicate target mutations are rejected")
    func rejectsDuplicateTargets() throws {
        let managed = ManagedCrontab(data: Data("0 1 * * * /bin/job\n".utf8))
        let job = try #require(managed.jobs.first)
        let draft = ManagedCronJobDraft(
            name: job.name,
            scheduleExpression: job.schedule.source,
            command: job.command,
            isEnabled: false
        )

        #expect(throws: ManagedCrontabError.duplicateMutation(job.id)) {
            try managed.applying([
                .update(id: job.id, draft: draft),
                .delete(id: job.id)
            ])
        }
    }

    @Test("Duplicate managed identities are protected without trapping unrelated edits")
    func protectsDuplicateManagedIDs() throws {
        let id = CronJobID(rawValue: "11111111-2222-3333-4444-555555555555")
        let source = Data("""
        # CronHarbor:job:\(id.rawValue):Rmlyc3Q=
        0 1 * * * /bin/first
        # CronHarbor:job:\(id.rawValue):U2Vjb25k
        0 2 * * * /bin/second

        """.utf8)
        let managed = ManagedCrontab(data: source)

        #expect(managed.jobs.count == 2)
        #expect(managed.ambiguousJobIDs == [id])
        #expect(throws: ManagedCrontabError.ambiguousJobID(id)) {
            try managed.applying([.delete(id: id)])
        }

        let newJob = ManagedCronJobDraft(
            name: "Third",
            scheduleExpression: "0 3 * * *",
            command: "/bin/third",
            isEnabled: true
        )
        let result = try managed.applying([.create(newJob)], generateID: { fixedUUID })
        #expect(result.starts(with: source))
        #expect(String(decoding: result, as: UTF8.self).contains("0 3 * * * /bin/third"))
    }
}
