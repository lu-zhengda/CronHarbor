import Foundation

enum CronExpressionFormatter {
    static func describe(_ expression: String) -> String {
        let value = expression.trimmingCharacters(in: .whitespaces)
        let shortcuts: [String: String] = [
            "@reboot": "When the cron daemon starts",
            "@yearly": "Every year",
            "@annually": "Every year",
            "@monthly": "Every month",
            "@weekly": "Every week",
            "@daily": "Every day",
            "@midnight": "Every day at midnight",
            "@hourly": "Every hour"
        ]
        if let description = shortcuts[value.lowercased()] { return description }

        let fields = value.split(whereSeparator: \Character.isWhitespace).map(String.init)
        guard fields.count == 5 else { return value }

        let minute = fields[0]
        let hour = fields[1]
        let dayOfMonth = fields[2]
        let month = fields[3]
        let weekday = fields[4]

        if minute.hasPrefix("*/"), hour == "*", dayOfMonth == "*", month == "*", weekday == "*" {
            return "Every \(minute.dropFirst(2)) minutes"
        }
        if let minuteValue = Int(minute), hour == "*", dayOfMonth == "*", month == "*", weekday == "*" {
            return minuteValue == 0 ? "Every hour" : "Hourly at :\(String(format: "%02d", minuteValue))"
        }
        if let minuteValue = Int(minute), let hourValue = Int(hour), dayOfMonth == "*", month == "*" {
            let time = displayTime(hour: hourValue, minute: minuteValue)
            if weekday == "*" { return "Every day at \(time)" }
            if weekday == "1-5" { return "Weekdays at \(time)" }
            let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            if let value = Int(weekday), value >= 0, value <= 7 {
                return "Every \(names[value == 7 ? 0 : value]) at \(time)"
            }
        }
        return value
    }

    private static func displayTime(hour: Int, minute: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        guard let date = Calendar.current.date(from: components) else {
            return String(format: "%02d:%02d", hour, minute)
        }
        return date.formatted(date: .omitted, time: .shortened)
    }
}
