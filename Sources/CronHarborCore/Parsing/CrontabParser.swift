import Foundation

public enum CrontabParser {
    private static let appleQualifier = Array("@AppleNotOnBattery".utf8)

    public static func parse(_ data: Data) -> CrontabDocument {
        var duplicateCounts: [UInt64: Int] = [:]
        let parsedLines = RawLine.split(data).enumerated().map { index, raw in
            let provisionalKind = classify(raw, lineIndex: index)
            guard case let .job(provisionalJob) = provisionalKind else {
                return CrontabLine(raw: raw, kind: provisionalKind)
            }

            let fingerprint = stableFingerprint(raw.renderedData)
            let occurrence = duplicateCounts[fingerprint, default: 0]
            duplicateCounts[fingerprint] = occurrence + 1
            let job = CronJob(
                id: CronJobID(rawValue: "\(hex(fingerprint))-\(occurrence)"),
                sourceLineIndex: index,
                schedule: provisionalJob.schedule,
                command: provisionalJob.command,
                appleNotOnBattery: provisionalJob.appleNotOnBattery
            )
            return CrontabLine(raw: raw, kind: .job(job))
        }
        return CrontabDocument(lines: parsedLines)
    }

    private static func classify(_ raw: RawLine, lineIndex: Int) -> CrontabLineKind {
        let bytes = [UInt8](raw.content)
        guard let text = raw.utf8Content else { return .opaque }

        if bytes.allSatisfy(isHorizontalWhitespace) {
            return .blank
        }

        let indentationEnd = bytes.firstIndex(where: { !isHorizontalWhitespace($0) }) ?? bytes.endIndex
        if indentationEnd < bytes.endIndex, bytes[indentationEnd] == UInt8(ascii: "#") {
            let indentation = String(decoding: bytes[..<indentationEnd], as: UTF8.self)
            let commentText = String(decoding: bytes[(indentationEnd + 1)...], as: UTF8.self)
            return .comment(CrontabComment(indentation: indentation, text: commentText))
        }

        if let assignment = parseEnvironment(bytes) {
            return .environment(assignment)
        }

        guard let job = parseJob(bytes, lineIndex: lineIndex) else {
            _ = text // Establish that semantic parsing only happens for valid UTF-8.
            return .opaque
        }
        return .job(job)
    }

    private static func parseEnvironment(_ bytes: [UInt8]) -> CrontabEnvironmentAssignment? {
        guard let equals = bytes.firstIndex(of: UInt8(ascii: "=")) else { return nil }
        let nameBytes = trimHorizontalWhitespace(bytes[..<equals])
        guard !nameBytes.isEmpty, isEnvironmentName(nameBytes) else { return nil }

        return CrontabEnvironmentAssignment(
            name: String(decoding: nameBytes, as: UTF8.self),
            value: String(decoding: bytes[(equals + 1)...], as: UTF8.self)
        )
    }

    private static func parseJob(_ bytes: [UInt8], lineIndex: Int) -> CronJob? {
        var cursor = 0
        skipWhitespace(bytes, cursor: &cursor)
        guard cursor < bytes.count else { return nil }

        guard let firstToken = consumeToken(bytes, cursor: &cursor) else { return nil }
        let schedule: CronSchedule

        if firstToken.first == UInt8(ascii: "@") {
            let macroText = String(decoding: firstToken, as: UTF8.self)
            guard let macro = CronMacro(rawValue: macroText) else { return nil }
            schedule = .macro(macro)
        } else {
            var fields = [firstToken]
            for _ in 0..<4 {
                guard consumeWhitespace(bytes, cursor: &cursor),
                      let token = consumeToken(bytes, cursor: &cursor) else { return nil }
                fields.append(token)
            }

            do {
                schedule = .fields(
                    try CronFields(
                        minute: String(decoding: fields[0], as: UTF8.self),
                        hour: String(decoding: fields[1], as: UTF8.self),
                        dayOfMonth: String(decoding: fields[2], as: UTF8.self),
                        month: String(decoding: fields[3], as: UTF8.self),
                        dayOfWeek: String(decoding: fields[4], as: UTF8.self)
                    )
                )
            } catch {
                return nil
            }
        }

        // On macOS, @AppleNotOnBattery is a prefix in the command field. It
        // therefore follows either the five schedule fields or an @macro.
        guard consumeWhitespace(bytes, cursor: &cursor), cursor < bytes.count else { return nil }

        var appleNotOnBattery = false
        let commandStart = cursor
        if let commandPrefix = consumeToken(bytes, cursor: &cursor),
           commandPrefix.elementsEqual(appleQualifier) {
            guard consumeWhitespace(bytes, cursor: &cursor), cursor < bytes.count else { return nil }
            appleNotOnBattery = true
        } else {
            cursor = commandStart
        }

        let command = String(decoding: bytes[cursor...], as: UTF8.self)
        return CronJob(
            id: CronJobID(rawValue: "provisional"),
            sourceLineIndex: lineIndex,
            schedule: schedule,
            command: command,
            appleNotOnBattery: appleNotOnBattery
        )
    }

    private static func skipWhitespace(_ bytes: [UInt8], cursor: inout Int) {
        while cursor < bytes.count, isHorizontalWhitespace(bytes[cursor]) {
            cursor += 1
        }
    }

    @discardableResult
    private static func consumeWhitespace(_ bytes: [UInt8], cursor: inout Int) -> Bool {
        let start = cursor
        skipWhitespace(bytes, cursor: &cursor)
        return cursor > start
    }

    private static func consumeToken(_ bytes: [UInt8], cursor: inout Int) -> ArraySlice<UInt8>? {
        let start = cursor
        while cursor < bytes.count, !isHorizontalWhitespace(bytes[cursor]) {
            cursor += 1
        }
        return cursor > start ? bytes[start..<cursor] : nil
    }

    private static func trimHorizontalWhitespace(_ bytes: ArraySlice<UInt8>) -> ArraySlice<UInt8> {
        var lower = bytes.startIndex
        var upper = bytes.endIndex
        while lower < upper, isHorizontalWhitespace(bytes[lower]) { lower += 1 }
        while upper > lower, isHorizontalWhitespace(bytes[upper - 1]) { upper -= 1 }
        return bytes[lower..<upper]
    }

    private static func isEnvironmentName(_ bytes: ArraySlice<UInt8>) -> Bool {
        guard let first = bytes.first, isASCIILetter(first) || first == UInt8(ascii: "_") else {
            return false
        }
        return bytes.dropFirst().allSatisfy {
            isASCIILetter($0) || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) || $0 == UInt8(ascii: "_")
        }
    }

    private static func isASCIILetter(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
            || (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte)
    }

    private static func isHorizontalWhitespace(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t")
    }

    private static func stableFingerprint(_ data: Data) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return hash
    }

    private static func hex(_ value: UInt64) -> String {
        let digits = String(value, radix: 16)
        return String(repeating: "0", count: max(0, 16 - digits.count)) + digits
    }
}
