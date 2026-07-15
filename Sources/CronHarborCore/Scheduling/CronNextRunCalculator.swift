import Foundation

/// Calculates calendar occurrences for validated cron schedules.
///
/// The calculator advances in real elapsed minutes and asks `Calendar` for the
/// local components of each candidate. That keeps DST gaps and repeated hours
/// under the caller's selected calendar and time-zone policy.
public struct CronNextRunCalculator: Sendable {
    public var calendar: Calendar
    public var searchLimitInMinutes: Int

    public init(
        calendar: Calendar = .current,
        searchLimitInMinutes: Int = 10 * 366 * 24 * 60
    ) {
        self.calendar = calendar
        self.searchLimitInMinutes = max(0, searchLimitInMinutes)
    }

    /// Returns the first scheduled minute strictly later than `date`.
    /// `@reboot` has no calendar occurrence and returns `nil`.
    public func nextRun(for schedule: CronSchedule, after date: Date) -> Date? {
        guard let fields = expandedFields(for: schedule), searchLimitInMinutes > 0 else {
            return nil
        }

        // Reconstructing a Date from local components is ambiguous during a
        // repeated DST hour and can move the search backwards to the first
        // occurrence. Advance from the caller's actual instant instead.
        let subminute = calendar.dateComponents([.second, .nanosecond], from: date)
        guard let second = subminute.second, let nanosecond = subminute.nanosecond else {
            return nil
        }
        let elapsedInMinute = TimeInterval(second) + TimeInterval(nanosecond) / 1_000_000_000
        var candidate = date.addingTimeInterval(60 - elapsedInMinute)

        for _ in 0..<searchLimitInMinutes {
            if matches(fields, at: candidate) {
                return candidate
            }
            candidate = candidate.addingTimeInterval(60)
        }
        return nil
    }

    public func nextRuns(
        for schedule: CronSchedule,
        after date: Date,
        count: Int
    ) -> [Date] {
        guard count > 0 else { return [] }
        var result: [Date] = []
        var cursor = date
        while result.count < count, let next = nextRun(for: schedule, after: cursor) {
            result.append(next)
            cursor = next
        }
        return result
    }

    public func matches(_ schedule: CronSchedule, at date: Date) -> Bool {
        guard let fields = expandedFields(for: schedule) else { return false }
        return matches(fields, at: date)
    }

    private func matches(_ fields: CronFields, at date: Date) -> Bool {
        let components = calendar.dateComponents(
            [.minute, .hour, .day, .month, .weekday],
            from: date
        )
        guard let minute = components.minute,
              let hour = components.hour,
              let day = components.day,
              let month = components.month,
              let calendarWeekday = components.weekday else {
            return false
        }

        guard fields.minute.contains(minute),
              fields.hour.contains(hour),
              fields.month.contains(month) else {
            return false
        }

        let dayOfMonthMatches = fields.dayOfMonth.contains(day)
        let cronWeekday = calendarWeekday - 1 // Calendar: Sunday=1; cron: Sunday=0.
        let dayOfWeekMatches = fields.dayOfWeek.contains(cronWeekday)

        // Vixie cron records a wildcard flag when either day expression
        // begins with `*`, including stepped forms. In that case both value
        // sets must match. When neither begins with `*`, the day fields use OR.
        if fields.dayOfMonth.isUnrestricted || fields.dayOfWeek.isUnrestricted {
            return dayOfMonthMatches && dayOfWeekMatches
        }
        return dayOfMonthMatches || dayOfWeekMatches
    }

    private func expandedFields(for schedule: CronSchedule) -> CronFields? {
        switch schedule {
        case let .fields(fields):
            return fields
        case .macro(.reboot):
            return nil
        case .macro(.yearly), .macro(.annually):
            return try? CronFields(minute: "0", hour: "0", dayOfMonth: "1", month: "1", dayOfWeek: "*")
        case .macro(.monthly):
            return try? CronFields(minute: "0", hour: "0", dayOfMonth: "1", month: "*", dayOfWeek: "*")
        case .macro(.weekly):
            return try? CronFields(minute: "0", hour: "0", dayOfMonth: "*", month: "*", dayOfWeek: "0")
        case .macro(.daily), .macro(.midnight):
            return try? CronFields(minute: "0", hour: "0", dayOfMonth: "*", month: "*", dayOfWeek: "*")
        case .macro(.hourly):
            return try? CronFields(minute: "0", hour: "*", dayOfMonth: "*", month: "*", dayOfWeek: "*")
        }
    }
}
