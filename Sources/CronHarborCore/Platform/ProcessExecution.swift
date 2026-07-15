import Foundation

/// A complete, shell-free description of a child process invocation.
public struct ProcessRequest: Sendable, Equatable {
    public let executableURL: URL
    public let arguments: [String]
    public let environment: [String: String]?
    public let currentDirectoryURL: URL?
    public let standardInput: Data?
    /// Overrides the executor's retained-byte limit for this request. Readers
    /// must still reject a result whose truncation flag is set when bytes are
    /// authoritative rather than diagnostic output.
    public let maximumCapturedBytesPerStream: Int?

    public init(
        executableURL: URL,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        currentDirectoryURL: URL? = nil,
        standardInput: Data? = nil,
        maximumCapturedBytesPerStream: Int? = nil
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.environment = environment
        self.currentDirectoryURL = currentDirectoryURL
        self.standardInput = standardInput
        self.maximumCapturedBytesPerStream = maximumCapturedBytesPerStream
    }
}

/// The bytes and exit status produced by a child process.
public struct ProcessResult: Sendable, Equatable {
    public let terminationStatus: Int32
    public let standardOutput: Data
    public let standardError: Data
    public let standardOutputWasTruncated: Bool
    public let standardErrorWasTruncated: Bool

    public init(
        terminationStatus: Int32,
        standardOutput: Data = Data(),
        standardError: Data = Data(),
        standardOutputWasTruncated: Bool = false,
        standardErrorWasTruncated: Bool = false
    ) {
        self.terminationStatus = terminationStatus
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.standardOutputWasTruncated = standardOutputWasTruncated
        self.standardErrorWasTruncated = standardErrorWasTruncated
    }
}

public enum ProcessExecutionError: Error, Sendable, Equatable {
    case executableMustBeAnAbsoluteFileURL(URL)
}

/// An injectable process boundary. Tests can implement this protocol without
/// launching any system executable.
public protocol ProcessExecuting: Sendable {
    func execute(_ request: ProcessRequest) async throws -> ProcessResult
}

/// Foundation-backed process execution with independent stdout/stderr drains.
public struct FoundationProcessExecutor: ProcessExecuting, Sendable {
    public static let defaultMaximumCapturedBytesPerStream = 1_048_576

    private let maximumCapturedBytesPerStream: Int

    public init(
        maximumCapturedBytesPerStream: Int = Self.defaultMaximumCapturedBytesPerStream
    ) {
        precondition(
            maximumCapturedBytesPerStream >= 0,
            "The process output capture limit cannot be negative."
        )
        self.maximumCapturedBytesPerStream = maximumCapturedBytesPerStream
    }

    public func execute(_ request: ProcessRequest) async throws -> ProcessResult {
        guard request.executableURL.isFileURL,
              request.executableURL.path.hasPrefix("/")
        else {
            throw ProcessExecutionError.executableMustBeAnAbsoluteFileURL(
                request.executableURL
            )
        }
        let captureLimit = request.maximumCapturedBytesPerStream
            ?? maximumCapturedBytesPerStream
        precondition(captureLimit >= 0, "The per-request process output capture limit cannot be negative.")

        let process = Process()
        let standardOutputPipe = Pipe()
        let standardErrorPipe = Pipe()
        // Cron jobs start with EOF on stdin unless an unescaped `%` supplied
        // input. Always using a pipe also prevents accidental inheritance of
        // the host app's standard input.
        let standardInputPipe = Pipe()
        let termination = ProcessTermination()

        process.executableURL = request.executableURL
        process.arguments = request.arguments
        process.environment = request.environment
        process.currentDirectoryURL = request.currentDirectoryURL
        process.standardOutput = standardOutputPipe
        process.standardError = standardErrorPipe
        process.standardInput = standardInputPipe
        process.terminationHandler = { process in
            let status = process.terminationStatus
            Task {
                await termination.finish(with: status)
            }
        }

        do {
            try process.run()
        } catch {
            process.terminationHandler = nil
            try? standardOutputPipe.fileHandleForWriting.close()
            try? standardErrorPipe.fileHandleForWriting.close()
            try? standardInputPipe.fileHandleForWriting.close()
            throw error
        }

        // Process has duplicated the write descriptors. Closing the parent's
        // copies lets the asynchronous readers observe EOF when the child exits.
        try? standardOutputPipe.fileHandleForWriting.close()
        try? standardErrorPipe.fileHandleForWriting.close()

        // Drain both streams independently for the entire process lifetime. We
        // keep only the configured prefix in memory, but continue reading and
        // discarding excess bytes so a noisy child can never block on a full
        // pipe.
        async let standardOutput = Self.capture(
            from: standardOutputPipe.fileHandleForReading,
            retainingAtMost: captureLimit
        )
        async let standardError = Self.capture(
            from: standardErrorPipe.fileHandleForReading,
            retainingAtMost: captureLimit
        )
        async let standardInputWrite: Void = Self.write(
            request.standardInput,
            to: standardInputPipe.fileHandleForWriting
        )

        let terminationStatus = await termination.wait()
        let (capturedOutput, capturedError, _) = try await (
            standardOutput,
            standardError,
            standardInputWrite
        )

        return ProcessResult(
            terminationStatus: terminationStatus,
            standardOutput: capturedOutput.data,
            standardError: capturedError.data,
            standardOutputWasTruncated: capturedOutput.wasTruncated,
            standardErrorWasTruncated: capturedError.wasTruncated
        )
    }

    private static func capture(
        from fileHandle: FileHandle,
        retainingAtMost maximumBytes: Int
    ) async throws -> LimitedProcessCapture {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                var retained = Data()
                retained.reserveCapacity(maximumBytes)
                var wasTruncated = false

                do {
                    while let chunk = try fileHandle.read(upToCount: 64 * 1_024),
                          !chunk.isEmpty
                    {
                        let remainingCapacity = max(0, maximumBytes - retained.count)
                        if remainingCapacity > 0 {
                            retained.append(contentsOf: chunk.prefix(remainingCapacity))
                        }
                        if chunk.count > remainingCapacity {
                            wasTruncated = true
                        }
                    }
                    try? fileHandle.close()
                    continuation.resume(
                        returning: LimitedProcessCapture(
                            data: retained,
                            wasTruncated: wasTruncated
                        )
                    )
                } catch {
                    try? fileHandle.close()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func write(_ data: Data?, to fileHandle: FileHandle) throws {
        defer {
            try? fileHandle.close()
        }

        if let data {
            try fileHandle.write(contentsOf: data)
        }
    }
}

private struct LimitedProcessCapture: Sendable {
    let data: Data
    let wasTruncated: Bool
}

private actor ProcessTermination {
    private var status: Int32?
    private var continuation: CheckedContinuation<Int32, Never>?

    func wait() async -> Int32 {
        if let status {
            return status
        }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func finish(with status: Int32) {
        if let continuation {
            self.continuation = nil
            continuation.resume(returning: status)
        } else {
            self.status = status
        }
    }
}
