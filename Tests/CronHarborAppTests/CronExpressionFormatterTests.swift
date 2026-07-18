import Foundation
import Testing
@testable import CronHarbor

@Suite("Cron expression formatter")
struct CronExpressionFormatterTests {
    private let posix = Locale(identifier: "en_US_POSIX")

    private func describe(_ expression: String) -> String {
        CronExpressionFormatter.describe(expression, locale: posix)
    }

    @Test("Minute intervals")
    func minuteIntervals() {
        #expect(describe("* * * * *") == "Every minute")
        #expect(describe("*/5 * * * *") == "Every 5 minutes")
        #expect(describe("*/15 * * * *") == "Every 15 minutes")
    }

    @Test("Hourly patterns")
    func hourlyPatterns() {
        #expect(describe("0 * * * *") == "Every hour")
        #expect(describe("30 * * * *") == "Every hour at :30")
        #expect(describe("0,30 * * * *") == "Every hour at :00 and :30")
        #expect(describe("15 */2 * * *") == "Every 2 hours at :15")
    }

    @Test("Daily clock times")
    func dailyClockTimes() {
        #expect(describe("0 9 * * *") == "Every day at 9:00 AM")
        #expect(describe("30 18 * * *") == "Every day at 6:30 PM")
        #expect(describe("0 9,18 * * *") == "Every day at 9:00 AM and 6:00 PM")
    }

    @Test("Weekday restrictions")
    func weekdayRestrictions() {
        #expect(describe("0 9 * * 1-5") == "Weekdays at 9:00 AM")
        #expect(describe("0 9 * * 0,6") == "Weekends at 9:00 AM")
        #expect(describe("0 9 * * 1") == "Every Monday at 9:00 AM")
        #expect(describe("30 18 * * 1,3,5") == "Mon, Wed and Fri at 6:30 PM")
        #expect(describe("*/10 * * * 1-5") == "Every 10 minutes on weekdays")
    }

    @Test("Sunday spelled as 7 matches Sunday spelled as 0")
    func sundayNormalization() {
        #expect(describe("0 9 * * 7") == describe("0 9 * * 0"))
    }

    @Test("Day-of-month restrictions")
    func dayOfMonthRestrictions() {
        #expect(describe("0 0 1 * *") == "Every month on day 1 of the month at 12:00 AM")
        #expect(describe("0 0 1,15 * *") == "Every month on days 1 and 15 of the month at 12:00 AM")
        #expect(describe("*/30 * 1 * *") == "Every 30 minutes on day 1 of the month")
    }

    @Test("Month restrictions")
    func monthRestrictions() {
        #expect(describe("0 12 * 6,7,8 *") == "Every day at 12:00 PM in Jun, Jul and Aug")
        #expect(describe("0 0 1 1 *") == "On day 1 of the month at 12:00 AM in Jan")
    }

    @Test("Macros")
    func macros() {
        #expect(describe("@hourly") == "Every hour")
        #expect(describe("@daily") == "Every day at midnight")
        #expect(describe("@reboot") == "When the cron daemon starts")
        #expect(describe("@yearly") == "Every year on Jan 1")
    }

    @Test("Ambiguous or complex expressions fall back to the raw source")
    func fallbacks() {
        // Both day fields restricted: vixie cron ORs them; prose would mislead.
        #expect(describe("0 9 1 * 1") == "0 9 1 * 1")
        // Too many list values to phrase.
        #expect(describe("1,2,3,4,5,6 * * * *") == "1,2,3,4,5,6 * * * *")
        // Unsupported syntax is returned untouched.
        #expect(describe("not cron") == "not cron")
        #expect(describe("0 8 * * MON-FRI") == "0 8 * * MON-FRI")
    }
}
