import CronHarborCore
import Foundation

/// Shared parsing and preview helpers for user-entered schedule expressions.
enum ScheduleExpression {
    static func schedule(from expression: String) -> CronSchedule? {
        let normalized = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        if let macro = CronMacro(rawValue: normalized) {
            return .macro(macro)
        }
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
        return .fields(fields)
    }

    static func nextRun(for expression: String, after date: Date = .now) -> Date? {
        guard let schedule = schedule(from: expression) else { return nil }
        return CronNextRunCalculator().nextRun(for: schedule, after: date)
    }

    /// Upcoming occurrences for interactive previews. The shorter search
    /// window keeps impossible dates (such as day 31 in February-only
    /// schedules) from stalling the UI while still covering real schedules.
    static func upcomingRuns(
        for expression: String,
        count: Int,
        after date: Date = .now
    ) -> [Date] {
        guard let schedule = schedule(from: expression) else { return [] }
        let calculator = CronNextRunCalculator(searchLimitInMinutes: 2 * 366 * 24 * 60)
        return calculator.nextRuns(for: schedule, after: date, count: count)
    }
}
