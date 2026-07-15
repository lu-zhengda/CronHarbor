import Foundation

/// The exact byte sequence that terminated a line in a crontab file.
public enum LineTerminator: Sendable, Hashable {
    case lineFeed
    case carriageReturnLineFeed
    case none

    public var data: Data {
        switch self {
        case .lineFeed:
            Data([0x0A])
        case .carriageReturnLineFeed:
            Data([0x0D, 0x0A])
        case .none:
            Data()
        }
    }
}

/// One physical line whose content and terminator are retained byte-for-byte.
///
/// `RawLine` deliberately uses `Data` rather than `String`. A crontab can then
/// be opened and saved without damaging an invalid UTF-8 line or changing its
/// line endings. Semantic parsing is only attempted when `utf8Content` exists.
public struct RawLine: Sendable, Hashable {
    public let content: Data
    public let terminator: LineTerminator

    public init(content: Data, terminator: LineTerminator) {
        self.content = content
        self.terminator = terminator
    }

    public init(utf8Content: String, terminator: LineTerminator = .lineFeed) {
        self.init(content: Data(utf8Content.utf8), terminator: terminator)
    }

    public var utf8Content: String? {
        String(data: content, encoding: .utf8)
    }

    public var renderedData: Data {
        var result = content
        result.append(terminator.data)
        return result
    }

    /// Splits data on LF while distinguishing LF, CRLF, and an unterminated
    /// final line. A bare CR is content, not a terminator.
    public static func split(_ data: Data) -> [RawLine] {
        let bytes = [UInt8](data)
        guard !bytes.isEmpty else { return [] }

        var lines: [RawLine] = []
        var start = 0

        for index in bytes.indices where bytes[index] == 0x0A {
            let hasCarriageReturn = index > start && bytes[index - 1] == 0x0D
            let contentEnd = hasCarriageReturn ? index - 1 : index
            lines.append(
                RawLine(
                    content: Data(bytes[start..<contentEnd]),
                    terminator: hasCarriageReturn ? .carriageReturnLineFeed : .lineFeed
                )
            )
            start = index + 1
        }

        if start < bytes.count {
            lines.append(RawLine(content: Data(bytes[start...]), terminator: .none))
        }

        return lines
    }
}
