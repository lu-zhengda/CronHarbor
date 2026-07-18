import Foundation
import Testing
@testable import CronHarbor

@Suite("Daemon run log parsing")
struct DaemonRunLogServiceTests {
    @Test("Parses CMD events for the requested user, newest first")
    func parsesEventsNewestFirst() throws {
        let ndjson = """
        {"timestamp":"2026-07-18 12:59:00.334894-0400","eventMessage":"(alice) CMD (\\/bin\\/echo one >\\/dev\\/null 2>&1)"}
        {"timestamp":"2026-07-18 13:00:00.389490-0400","eventMessage":"(alice) CMD (\\/bin\\/echo two)"}
        """
        let events = DaemonRunLogService.parseEvents(
            fromNDJSON: Data(ndjson.utf8),
            user: "alice"
        )

        #expect(events.count == 2)
        #expect(events[0].command == "/bin/echo two")
        #expect(events[1].command == "/bin/echo one >/dev/null 2>&1")
        #expect(events[0].date > events[1].date)
    }

    @Test("Other users' jobs and non-CMD messages are excluded")
    func filtersForeignAndUnrelatedMessages() {
        let ndjson = """
        {"timestamp":"2026-07-18 12:59:00.000000-0400","eventMessage":"(root) CMD (\\/usr\\/sbin\\/periodic daily)"}
        {"timestamp":"2026-07-18 12:59:00.000000-0400","eventMessage":"(alice) RELOAD (tabs\\/alice)"}
        {"timestamp":"2026-07-18 12:59:00.000000-0400","eventMessage":"activating connection"}
        not json at all
        """
        let events = DaemonRunLogService.parseEvents(
            fromNDJSON: Data(ndjson.utf8),
            user: "alice"
        )

        #expect(events.isEmpty)
    }

    @Test("Commands containing parentheses survive extraction")
    func commandsKeepInnerParentheses() {
        let message = "(alice) CMD (/bin/sh -c 'echo (nested) done')"
        #expect(
            DaemonRunLogService.command(fromEventMessage: message, user: "alice")
                == "/bin/sh -c 'echo (nested) done'"
        )
    }

    @Test("A user whose name prefixes another user's name never matches")
    func userMatchIsExact() {
        let message = "(alicesmith) CMD (/bin/echo hi)"
        #expect(DaemonRunLogService.command(fromEventMessage: message, user: "alice") == nil)
    }
}
