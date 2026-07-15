import Foundation
import Testing
@testable import CronHarborCore

@Suite("Cron parsing and scheduling")
struct CronParsingAndSchedulingTests {
    @Test("Raw lines preserve mixed endings and invalid UTF-8")
    func rawLinesRoundTripArbitraryBytes() {
        let source = Data([0x61, 0x0D, 0x0A, 0x62, 0x0A, 0xFF, 0x0D])
        let lines = RawLine.split(source)

        #expect(lines.count == 3)
        #expect(lines[0].terminator == .carriageReturnLineFeed)
        #expect(lines[1].terminator == .lineFeed)
        #expect(lines[2].terminator == .none)
        #expect(lines[2].utf8Content == nil)
        #expect(lines.reduce(into: Data()) { $0.append($1.renderedData) } == source)
    }

    @Test("Parser classifies supported syntax conservatively and round-trips exactly")
    func parserClassifiesWithoutNormalizing() throws {
        var source = Data("  \r\n\t# note\n PATH = '/opt/bin'\r\n@hourly\t@AppleNotOnBattery  /bin/echo hi\n0 2 * JAN MON @AppleNotOnBattery /bin/job # literal\r\n0 3 * * * /bin/echo @AppleNotOnBattery literal\n@AppleNotOnBattery 0 4 * * * /bin/wrong-prefix\n@AppleNotOnBattery @daily /bin/wrong-macro-prefix\n0 4 * * * @AppleNotOnBattery\n61 * * * * invalid\n".utf8)
        source.append(contentsOf: [0xFF, 0x0A])

        let document = CrontabDocument(data: source)

        #expect(document.lines.count == 11)
        guard case .blank = document.lines[0].kind else {
            Issue.record("Expected blank line")
            return
        }
        guard case let .comment(comment) = document.lines[1].kind else {
            Issue.record("Expected comment")
            return
        }
        #expect(comment.indentation == "\t")
        #expect(comment.text == " note")
        guard case let .environment(environment) = document.lines[2].kind else {
            Issue.record("Expected environment assignment")
            return
        }
        #expect(environment.name == "PATH")
        #expect(environment.value == " '/opt/bin'")
        #expect(document.jobs.count == 3)
        #expect(document.jobs[0].schedule == .macro(.hourly))
        #expect(document.jobs[0].requiresACPower)
        #expect(document.jobs[0].command == "/bin/echo hi")
        #expect(document.jobs[1].requiresACPower)
        #expect(document.jobs[1].command == "/bin/job # literal")
        #expect(!document.jobs[2].requiresACPower)
        #expect(document.jobs[2].command == "/bin/echo @AppleNotOnBattery literal")
        guard case .opaque = document.lines[6].kind,
              case .opaque = document.lines[7].kind,
              case .opaque = document.lines[8].kind,
              case .opaque = document.lines[9].kind,
              case .opaque = document.lines[10].kind else {
            Issue.record("Unsupported lines must remain opaque")
            return
        }
        #expect(document.renderedData() == source)
    }

    @Test("Duplicate unmanaged jobs receive stable distinct identifiers")
    func duplicateJobIDsAreStable() {
        let source = Data("0 1 * * * /bin/job\n0 1 * * * /bin/job\n".utf8)
        let first = CrontabDocument(data: source).jobs.map(\.id)
        let second = CrontabDocument(data: source).jobs.map(\.id)

        #expect(first.count == 2)
        #expect(first[0] != first[1])
        #expect(first == second)
    }

    @Test("Field parser handles names, ranges, steps, and Sunday aliases")
    func validatesAndNormalizesFields() throws {
        let months = try CronField("1-3/2,12", kind: .month)
        let weekdays = try CronField("0,7,1-5/2", kind: .dayOfWeek)
        let namedMonth = try CronField("jan", kind: .month)
        let namedWeekday = try CronField("MON", kind: .dayOfWeek)

        #expect(months.values == [1, 3, 12])
        #expect(weekdays.values == [0, 1, 3, 5])
        #expect(weekdays.contains(7))
        #expect(namedMonth.values == [1])
        #expect(namedWeekday.values == [1])
        #expect(throws: CronValidationError.self) {
            _ = try CronField("*/0", kind: .minute)
        }
        #expect(throws: CronValidationError.self) {
            _ = try CronField("10-2", kind: .hour)
        }
        #expect(throws: CronValidationError.self) {
            _ = try CronField("JAN,MAR", kind: .month)
        }
        #expect(throws: CronValidationError.self) {
            _ = try CronField("MON-FRI", kind: .dayOfWeek)
        }
        #expect(throws: CronValidationError.self) {
            _ = try CronField("1,MON", kind: .dayOfWeek)
        }
    }

    @Test("Day-of-month and day-of-week use cron OR and wildcard semantics")
    func dayFieldsFollowVixieSemantics() throws {
        let calculator = CronNextRunCalculator(calendar: utcCalendar)
        let eitherDay = CronSchedule.fields(
            try CronFields(minute: "0", hour: "0", dayOfMonth: "1", month: "*", dayOfWeek: "MON")
        )
        let wildcardStep = CronSchedule.fields(
            try CronFields(minute: "0", hour: "0", dayOfMonth: "*/2", month: "*", dayOfWeek: "MON")
        )
        let bothWildcardSteps = CronSchedule.fields(
            try CronFields(minute: "0", hour: "0", dayOfMonth: "*/2", month: "*", dayOfWeek: "*/2")
        )

        #expect(calculator.matches(eitherDay, at: utcDate(2023, 1, 2))) // Monday
        #expect(calculator.matches(eitherDay, at: utcDate(2023, 2, 1))) // First of month
        #expect(!calculator.matches(eitherDay, at: utcDate(2023, 1, 3)))

        // Vixie (and macOS) cron sets the wildcard flag before parsing the
        // step. If either day field begins with `*`, both value sets must
        // match; the stepped values are never discarded.
        #expect(!calculator.matches(wildcardStep, at: utcDate(2023, 1, 2))) // Monday, even DOM
        #expect(calculator.matches(wildcardStep, at: utcDate(2023, 1, 9))) // Monday, odd DOM
        #expect(!calculator.matches(wildcardStep, at: utcDate(2023, 1, 3)))

        #expect(calculator.matches(bothWildcardSteps, at: utcDate(2023, 1, 1))) // Sunday, odd DOM
        #expect(calculator.matches(bothWildcardSteps, at: utcDate(2023, 1, 3))) // Tuesday, odd DOM
        #expect(!calculator.matches(bothWildcardSteps, at: utcDate(2023, 1, 8))) // Sunday, even DOM
        #expect(!calculator.matches(bothWildcardSteps, at: utcDate(2023, 1, 9))) // Monday, odd DOM
    }

    @Test("Next-run search is strict and macros expand predictably")
    func nextRunIsStrictlyLater() throws {
        let calculator = CronNextRunCalculator(calendar: utcCalendar)
        let hourly = CronSchedule.macro(.hourly)
        let start = utcDate(2026, 7, 14, 10, 0)

        #expect(calculator.nextRun(for: hourly, after: start) == utcDate(2026, 7, 14, 11, 0))
        #expect(calculator.nextRun(for: .macro(.reboot), after: start) == nil)
        #expect(calculator.nextRuns(for: hourly, after: start, count: 3) == [
            utcDate(2026, 7, 14, 11, 0),
            utcDate(2026, 7, 14, 12, 0),
            utcDate(2026, 7, 14, 13, 0),
        ])
    }

    @Test("Next-run search stays strict in the repeated DST hour")
    func nextRunAdvancesFromActualInstantAcrossFallBack() throws {
        var newYorkCalendar = Calendar(identifier: .gregorian)
        newYorkCalendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let calculator = CronNextRunCalculator(calendar: newYorkCalendar)
        let everyMinute = CronSchedule.fields(
            try CronFields(minute: "*", hour: "*", dayOfMonth: "*", month: "*", dayOfWeek: "*")
        )
        let formatter = ISO8601DateFormatter()
        let secondOneThirty = try #require(formatter.date(from: "2026-11-01T01:30:00-05:00"))
        let expected = try #require(formatter.date(from: "2026-11-01T01:31:00-05:00"))

        let next = calculator.nextRun(for: everyMinute, after: secondOneThirty)

        #expect(next == expected)
        #expect(try #require(next) > secondOneThirty)
    }

    @Test("Cron percent preprocessing separates command input and honors escapes")
    func preprocessesPercentSyntax() {
        #expect(
            CronPercentPreprocessor.preprocess("printf hello\\%world")
                == CronProcessedCommand(shellCommand: "printf hello%world", standardInput: nil)
        )
        #expect(
            CronPercentPreprocessor.preprocess("cat%first%second")
                == CronProcessedCommand(shellCommand: "cat", standardInput: "first\nsecond")
        )
        #expect(
            CronPercentPreprocessor.preprocess("cat%")
                == CronProcessedCommand(shellCommand: "cat", standardInput: "")
        )
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func utcDate(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int = 0,
        _ minute: Int = 0
    ) -> Date {
        utcCalendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }
}
