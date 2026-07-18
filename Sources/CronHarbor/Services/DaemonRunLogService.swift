import Foundation

/// A cron start observed in the macOS unified log.
///
/// The cron daemon logs `(user) CMD (command)` at the moment it launches a
/// job. That gives reliable *start* evidence, but macOS cron logs neither
/// completion nor exit status, so an event proves only that the daemon ran
/// the command.
struct DaemonRunEvent: Identifiable, Hashable, Sendable {
    let date: Date
    let command: String

    var id: String { "\(date.timeIntervalSinceReferenceDate):\(command)" }
}

/// Reads recent cron daemon starts for the current user from the unified log
/// via `/usr/bin/log show`. Read-only: this service never modifies any system
/// state and shells out to Apple's own log tool with a fixed argument list.
///
/// macOS keeps cron's Info-level messages only briefly in the log's ring
/// buffer, so each query may see just the last few starts. Observed events
/// are therefore accumulated for the app session: every fetch unions new
/// events into what was already seen.
actor DaemonRunLogService {
    /// The log's Info ring buffer rarely holds more than minutes of cron
    /// chatter, so a short window keeps each query cheap without losing data.
    static let lookbackHours = 1
    private static let maximumRetainedEvents = 500

    private var observedEvents: [DaemonRunEvent] = []
    private var cacheDate: Date?
    private let cacheLifetime: TimeInterval = 60

    enum ServiceError: LocalizedError {
        case logToolFailed(Int32)
        case timedOut

        var errorDescription: String? {
            switch self {
            case .logToolFailed(let status):
                "The system log tool exited with status \(status)."
            case .timedOut:
                "Reading the system log took too long and was cancelled."
            }
        }
    }

    func recentRuns(now: Date = .now) async throws -> [DaemonRunEvent] {
        if let cacheDate, now.timeIntervalSince(cacheDate) < cacheLifetime {
            return observedEvents
        }
        let data = try await Self.readLog()
        let fresh = Self.parseEvents(fromNDJSON: data, user: NSUserName())
        let known = Set(observedEvents.map(\.id))
        observedEvents.append(contentsOf: fresh.filter { !known.contains($0.id) })
        observedEvents.sort { $0.date > $1.date }
        observedEvents = Array(observedEvents.prefix(Self.maximumRetainedEvents))
        cacheDate = now
        return observedEvents
    }

    // MARK: - log invocation

    private static func readLog() async throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = [
            "show",
            "--last", "\(lookbackHours)h",
            "--info",
            "--style", "ndjson",
            "--predicate", "process == \"cron\" AND eventMessage CONTAINS \" CMD (\"",
        ]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                let watchdog = DispatchWorkItem {
                    if process.isRunning {
                        process.terminate()
                    }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: watchdog)

                // Drain until EOF before waiting so a large log stream can
                // never fill the pipe and deadlock the child.
                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                watchdog.cancel()

                if process.terminationReason == .uncaughtSignal {
                    continuation.resume(throwing: ServiceError.timedOut)
                } else if process.terminationStatus != 0 {
                    continuation.resume(throwing: ServiceError.logToolFailed(process.terminationStatus))
                } else {
                    continuation.resume(returning: data)
                }
            }
        }
    }

    // MARK: - parsing

    private struct LogLine: Decodable {
        let timestamp: String
        let eventMessage: String
    }

    static func parseEvents(fromNDJSON data: Data, user: String) -> [DaemonRunEvent] {
        let decoder = JSONDecoder()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSZZZZZ"

        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .compactMap { line -> DaemonRunEvent? in
                guard let lineData = line.data(using: .utf8),
                      let entry = try? decoder.decode(LogLine.self, from: lineData),
                      let command = command(fromEventMessage: entry.eventMessage, user: user),
                      let date = formatter.date(from: entry.timestamp)
                else {
                    return nil
                }
                return DaemonRunEvent(date: date, command: command)
            }
            .sorted { $0.date > $1.date }
    }

    /// Extracts the command from a `(user) CMD (command)` message, requiring
    /// an exact match on the requesting user so other accounts' jobs are
    /// never surfaced.
    static func command(fromEventMessage message: String, user: String) -> String? {
        let prefix = "(\(user)) CMD ("
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(prefix), trimmed.hasSuffix(")") else { return nil }
        return String(trimmed.dropFirst(prefix.count).dropLast())
    }
}
