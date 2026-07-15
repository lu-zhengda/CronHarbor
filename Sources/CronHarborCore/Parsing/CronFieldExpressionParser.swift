import Foundation

enum CronFieldExpressionParser {
    private static let monthNames: [String: Int] = [
        "JAN": 1, "FEB": 2, "MAR": 3, "APR": 4, "MAY": 5, "JUN": 6,
        "JUL": 7, "AUG": 8, "SEP": 9, "OCT": 10, "NOV": 11, "DEC": 12,
    ]

    private static let weekdayNames: [String: Int] = [
        "SUN": 0, "MON": 1, "TUE": 2, "WED": 3,
        "THU": 4, "FRI": 5, "SAT": 6,
    ]

    static func parse(_ source: String, kind: CronFieldKind) throws -> CronField {
        guard !source.isEmpty else {
            throw error(kind, source, .emptyExpression, source)
        }

        let items = source.split(separator: ",", omittingEmptySubsequences: false)
        var resolvedValues = Set<Int>()

        for itemSlice in items {
            let item = String(itemSlice)
            guard !item.isEmpty else {
                throw error(kind, source, .emptyListItem, item)
            }
            for value in try values(
                for: item,
                source: source,
                kind: kind,
                allowsNamedValue: items.count == 1
            ) {
                resolvedValues.insert(normalize(value, for: kind))
            }
        }

        return CronField(
            source: source,
            kind: kind,
            values: resolvedValues,
            // Vixie cron sets the day-field wildcard flag when the expression
            // begins with `*`, including stepped forms such as `*/2`.
            isUnrestricted: source.first == "*"
        )
    }

    private static func values(
        for item: String,
        source: String,
        kind: CronFieldKind,
        allowsNamedValue: Bool
    ) throws -> [Int] {
        let stepParts = item.split(separator: "/", omittingEmptySubsequences: false)
        guard stepParts.count <= 2 else {
            throw error(kind, source, .malformedStep, item)
        }

        let base = String(stepParts[0])
        let step: Int
        if stepParts.count == 2 {
            let stepText = String(stepParts[1])
            guard !stepText.isEmpty, let parsedStep = Int(stepText), parsedStep > 0,
                  parsedStep <= kind.allowedRange.upperBound else {
                throw error(kind, source, .invalidStep, stepText)
            }
            step = parsedStep
        } else {
            step = 1
        }

        let lower: Int
        let upper: Int
        if base == "*" {
            lower = kind.allowedRange.lowerBound
            upper = kind.allowedRange.upperBound
        } else if base.contains("-") {
            let rangeParts = base.split(separator: "-", omittingEmptySubsequences: false)
            guard rangeParts.count == 2, !rangeParts[0].isEmpty, !rangeParts[1].isEmpty else {
                throw error(kind, source, .malformedRange, base)
            }
            // macOS accepts a month or weekday name only as the complete
            // field; named ranges are explicitly outside its crontab syntax.
            lower = try parseValue(
                String(rangeParts[0]),
                source: source,
                kind: kind,
                allowsNamedValue: false
            )
            upper = try parseValue(
                String(rangeParts[1]),
                source: source,
                kind: kind,
                allowsNamedValue: false
            )
            guard lower <= upper else {
                throw error(kind, source, .reversedRange, base)
            }
        } else {
            guard stepParts.count == 1 else {
                throw error(kind, source, .malformedStep, item)
            }
            let value = try parseValue(
                base,
                source: source,
                kind: kind,
                allowsNamedValue: allowsNamedValue
            )
            return [value]
        }

        return Array(stride(from: lower, through: upper, by: step))
    }

    private static func parseValue(
        _ text: String,
        source: String,
        kind: CronFieldKind,
        allowsNamedValue: Bool
    ) throws -> Int {
        let numericValue = Int(text)
        let namedValue: Int?
        switch kind {
        case .month:
            namedValue = monthNames[text.uppercased()]
        case .dayOfWeek:
            namedValue = weekdayNames[text.uppercased()]
        default:
            namedValue = nil
        }

        if numericValue == nil, namedValue != nil, !allowsNamedValue {
            throw error(kind, source, .invalidValue, text)
        }

        let value = numericValue ?? namedValue
        guard let value else {
            throw error(kind, source, .invalidValue, text)
        }
        guard kind.allowedRange.contains(value) else {
            throw error(kind, source, .valueOutOfRange, text)
        }
        return value
    }

    private static func normalize(_ value: Int, for kind: CronFieldKind) -> Int {
        kind == .dayOfWeek && value == 7 ? 0 : value
    }

    private static func error(
        _ kind: CronFieldKind,
        _ expression: String,
        _ reason: CronValidationError.Reason,
        _ fragment: String
    ) -> CronValidationError {
        CronValidationError(field: kind, expression: expression, reason: reason, fragment: fragment)
    }
}
