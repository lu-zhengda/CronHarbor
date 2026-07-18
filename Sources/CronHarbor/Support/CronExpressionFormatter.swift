import CronHarborCore
import Foundation

/// Produces human-readable descriptions for supported cron expressions.
///
/// The formatter is best-effort presentation only: any expression it cannot
/// describe confidently is returned verbatim so the UI never shows a wrong
/// paraphrase of a schedule the daemon will actually follow.
enum CronExpressionFormatter {
    static func describe(_ expression: String, locale: Locale = .current) -> String {
        let value = expression.trimmingCharacters(in: .whitespacesAndNewlines)

        if let macro = CronMacro(rawValue: value.lowercased()) {
            return describeMacro(macro)
        }

        let parts = value.split(whereSeparator: \Character.isWhitespace).map(String.init)
        guard parts.count == 5,
              let fields = try? CronFields(
                  minute: parts[0],
                  hour: parts[1],
                  dayOfMonth: parts[2],
                  month: parts[3],
                  dayOfWeek: parts[4]
              )
        else {
            return value
        }
        return describe(fields, locale: locale) ?? value
    }

    private static func describeMacro(_ macro: CronMacro) -> String {
        switch macro {
        case .reboot: "When the cron daemon starts"
        case .yearly, .annually: "Every year on Jan 1"
        case .monthly: "Every month on day 1"
        case .weekly: "Every Sunday at midnight"
        case .daily, .midnight: "Every day at midnight"
        case .hourly: "Every hour"
        }
    }

    // MARK: - Field composition

    private static func describe(_ fields: CronFields, locale: Locale) -> String? {
        // Vixie cron ORs day-of-month and day-of-week when both are
        // restricted. That semantic is easy to misread in prose, so fall
        // back to the raw expression.
        let dayOfMonthRestricted = !fields.dayOfMonth.isUnrestricted
        let dayOfWeekRestricted = !fields.dayOfWeek.isUnrestricted
        guard !(dayOfMonthRestricted && dayOfWeekRestricted) else { return nil }

        guard let months = monthPhrase(fields.month, locale: locale) else { return nil }
        guard let day = dayPhrase(fields, locale: locale) else { return nil }
        guard let time = timePattern(minute: fields.minute, hour: fields.hour) else { return nil }

        let monthSuffix = months.map { " in \($0)" } ?? ""

        switch time {
        case .interval(let base):
            return base + intervalDaySuffix(for: day, locale: locale) + monthSuffix
        case .clock(let times):
            let timeText = joinList(times.map { formatTime($0, locale: locale) })
            return clockPhrase(
                day: day,
                timeText: timeText,
                monthsRestricted: months != nil,
                locale: locale
            ) + monthSuffix
        }
    }

    private enum DayPhrase {
        case everyDay
        case weekdays
        case weekends
        case singleWeekday(Int)
        case weekdayList([Int])
        case daysOfMonth([Int])
    }

    private enum TimePattern {
        case interval(String)
        case clock([(hour: Int, minute: Int)])
    }

    private static func dayPhrase(_ fields: CronFields, locale: Locale) -> DayPhrase? {
        if !fields.dayOfWeek.isUnrestricted {
            let days = Set(fields.dayOfWeek.values.map { $0 == 7 ? 0 : $0 })
            if days == Set(1...5) { return .weekdays }
            if days == Set([0, 6]) { return .weekends }
            if days.count == 1, let only = days.first { return .singleWeekday(only) }
            guard days.count <= 4 else { return nil }
            return .weekdayList(days.sorted())
        }
        if !fields.dayOfMonth.isUnrestricted {
            let days = fields.dayOfMonth.values.sorted()
            guard days.count <= 4 else { return nil }
            return .daysOfMonth(days)
        }
        return .everyDay
    }

    /// Returns `.some(nil)` when every month matches, `.some(text)` for a
    /// small describable set, and `nil` when the set is too complex.
    private static func monthPhrase(_ field: CronField, locale: Locale) -> String?? {
        guard !field.isUnrestricted else { return .some(nil) }
        let months = field.values.sorted()
        guard months.count <= 4 else { return nil }
        let symbols = calendar(for: locale).shortMonthSymbols
        return .some(joinList(months.map { symbols[$0 - 1] }))
    }

    private static func timePattern(minute: CronField, hour: CronField) -> TimePattern? {
        if hour.isUnrestricted, hour.source.hasPrefix("*"), !hour.source.contains("/") {
            if minute.source == "*" { return .interval("Every minute") }
            if let step = stepValue(of: minute.source) {
                return .interval(step == 1 ? "Every minute" : "Every \(step) minutes")
            }
            let minutes = minute.values.sorted()
            guard minutes.count <= 4 else { return nil }
            if minutes == [0] { return .interval("Every hour") }
            let stops = minutes.map { String(format: ":%02d", $0) }
            return .interval("Every hour at \(joinList(stops))")
        }

        if let hourStep = stepValue(of: hour.source), hour.isUnrestricted {
            let minutes = minute.values.sorted()
            guard !minute.isUnrestricted, minutes.count == 1, let minuteValue = minutes.first else {
                return nil
            }
            let base = hourStep == 1 ? "Every hour" : "Every \(hourStep) hours"
            return .interval("\(base) at :\(String(format: "%02d", minuteValue))")
        }

        guard !minute.isUnrestricted, !hour.isUnrestricted else { return nil }
        let minutes = minute.values.sorted()
        let hours = hour.values.sorted()
        guard minutes.count * hours.count <= 4 else { return nil }
        var times: [(hour: Int, minute: Int)] = []
        for hourValue in hours {
            for minuteValue in minutes {
                times.append((hour: hourValue, minute: minuteValue))
            }
        }
        return .clock(times)
    }

    private static func intervalDaySuffix(for day: DayPhrase, locale: Locale) -> String {
        let calendar = calendar(for: locale)
        switch day {
        case .everyDay:
            return ""
        case .weekdays:
            return " on weekdays"
        case .weekends:
            return " on weekends"
        case .singleWeekday(let weekday):
            return " on \(calendar.weekdaySymbols[weekday])"
        case .weekdayList(let weekdays):
            return " on \(joinList(weekdays.map { calendar.shortWeekdaySymbols[$0] }))"
        case .daysOfMonth(let days):
            return " on \(daysOfMonthText(days))"
        }
    }

    private static func clockPhrase(
        day: DayPhrase,
        timeText: String,
        monthsRestricted: Bool,
        locale: Locale
    ) -> String {
        let calendar = calendar(for: locale)
        switch day {
        case .everyDay:
            return "Every day at \(timeText)"
        case .weekdays:
            return "Weekdays at \(timeText)"
        case .weekends:
            return "Weekends at \(timeText)"
        case .singleWeekday(let weekday):
            return "Every \(calendar.weekdaySymbols[weekday]) at \(timeText)"
        case .weekdayList(let weekdays):
            return "\(joinList(weekdays.map { calendar.shortWeekdaySymbols[$0] })) at \(timeText)"
        case .daysOfMonth(let days):
            let prefix = monthsRestricted ? "On" : "Every month on"
            return "\(prefix) \(daysOfMonthText(days)) at \(timeText)"
        }
    }

    private static func daysOfMonthText(_ days: [Int]) -> String {
        days.count == 1
            ? "day \(days[0]) of the month"
            : "days \(joinList(days.map(String.init))) of the month"
    }

    // MARK: - Primitive helpers

    private static func stepValue(of source: String) -> Int? {
        guard source.hasPrefix("*/") else { return nil }
        return Int(source.dropFirst(2))
    }

    private static func joinList(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        default: return items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
        }
    }

    private static func calendar(for locale: Locale) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        return calendar
    }

    private static func formatTime(_ time: (hour: Int, minute: Int), locale: Locale) -> String {
        var components = DateComponents()
        components.hour = time.hour
        components.minute = time.minute
        guard let date = Calendar.current.date(from: components) else {
            return String(format: "%02d:%02d", time.hour, time.minute)
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        // ICU inserts narrow/no-break spaces before day-period markers;
        // normalize them so descriptions compare and copy as plain text.
        return formatter.string(from: date)
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }
}
