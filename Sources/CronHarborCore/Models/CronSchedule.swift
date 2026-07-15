import Foundation

public enum CronFieldKind: String, Sendable, Hashable, CaseIterable {
    case minute
    case hour
    case dayOfMonth
    case month
    case dayOfWeek

    public var allowedRange: ClosedRange<Int> {
        switch self {
        case .minute: 0...59
        case .hour: 0...23
        case .dayOfMonth: 1...31
        case .month: 1...12
        case .dayOfWeek: 0...7
        }
    }
}

public struct CronValidationError: Error, Sendable, Hashable, CustomStringConvertible {
    public enum Reason: String, Sendable, Hashable {
        case emptyExpression
        case emptyListItem
        case malformedStep
        case invalidStep
        case malformedRange
        case reversedRange
        case invalidValue
        case valueOutOfRange
    }

    public let field: CronFieldKind
    public let expression: String
    public let reason: Reason
    public let fragment: String

    public init(field: CronFieldKind, expression: String, reason: Reason, fragment: String) {
        self.field = field
        self.expression = expression
        self.reason = reason
        self.fragment = fragment
    }

    public var description: String {
        "Invalid \(field.rawValue) expression '\(expression)' (\(reason.rawValue): '\(fragment)')"
    }
}

/// A validated cron field. `source` retains the user's spelling while `values`
/// provides a normalized set suitable for scheduling and UI previews.
public struct CronField: Sendable, Hashable {
    public let source: String
    public let kind: CronFieldKind
    public let values: Set<Int>
    public let isUnrestricted: Bool

    public init(_ source: String, kind: CronFieldKind) throws {
        self = try CronFieldExpressionParser.parse(source, kind: kind)
    }

    init(source: String, kind: CronFieldKind, values: Set<Int>, isUnrestricted: Bool) {
        self.source = source
        self.kind = kind
        self.values = values
        self.isUnrestricted = isUnrestricted
    }

    public func contains(_ value: Int) -> Bool {
        if kind == .dayOfWeek && value == 7 {
            return values.contains(0)
        }
        return values.contains(value)
    }
}

public struct CronFields: Sendable, Hashable {
    public let minute: CronField
    public let hour: CronField
    public let dayOfMonth: CronField
    public let month: CronField
    public let dayOfWeek: CronField

    public init(
        minute: String,
        hour: String,
        dayOfMonth: String,
        month: String,
        dayOfWeek: String
    ) throws {
        self.minute = try CronField(minute, kind: .minute)
        self.hour = try CronField(hour, kind: .hour)
        self.dayOfMonth = try CronField(dayOfMonth, kind: .dayOfMonth)
        self.month = try CronField(month, kind: .month)
        self.dayOfWeek = try CronField(dayOfWeek, kind: .dayOfWeek)
    }

    public var source: String {
        [minute.source, hour.source, dayOfMonth.source, month.source, dayOfWeek.source]
            .joined(separator: " ")
    }
}

public enum CronMacro: String, Sendable, Hashable, CaseIterable {
    case reboot = "@reboot"
    case yearly = "@yearly"
    case annually = "@annually"
    case monthly = "@monthly"
    case weekly = "@weekly"
    case daily = "@daily"
    case midnight = "@midnight"
    case hourly = "@hourly"
}

public enum CronSchedule: Sendable, Hashable {
    case fields(CronFields)
    case macro(CronMacro)

    public var source: String {
        switch self {
        case let .fields(fields): fields.source
        case let .macro(macro): macro.rawValue
        }
    }
}
