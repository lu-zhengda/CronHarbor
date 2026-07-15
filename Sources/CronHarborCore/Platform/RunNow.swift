import CryptoKit
import Foundation

public struct RunNowInvocationID: Sendable, Hashable, CustomStringConvertible {
    public let rawValue: Data

    init(request: ProcessRequest) {
        var fingerprint = Data()

        func append(_ value: String) {
            fingerprint.append(contentsOf: value.utf8)
            fingerprint.append(0)
        }

        append(request.executableURL.path)
        request.arguments.forEach(append)
        append(request.currentDirectoryURL?.path ?? "")
        if let standardInput = request.standardInput {
            fingerprint.append(standardInput)
        }
        fingerprint.append(0)
        request.environment?.sorted(by: { $0.key < $1.key }).forEach { key, value in
            append(key)
            append(value)
        }

        rawValue = Data(SHA256.hash(data: fingerprint))
    }

    public var description: String {
        rawValue.map { String(format: "%02x", $0) }.joined()
    }
}

public struct CronRunInvocation: Sendable, Equatable {
    public let request: ProcessRequest
    public let id: RunNowInvocationID

    public init(request: ProcessRequest) {
        self.request = request
        id = RunNowInvocationID(request: request)
    }
}

public enum CronRunInvocationError: Error, Sendable, Equatable {
    case commandContainsNUL
    case invalidEnvironmentVariableName(String)
    case environmentValueContainsNUL(name: String)
    case shellMustBeAnAbsolutePath(String)
    case homeMustBeAnAbsolutePath(String)
}

/// Builds a cron-like invocation without inheriting the host app's complete
/// environment. Explicit crontab assignments are preserved, while identity
/// defaults and a minimal PATH are supplied deterministically.
public struct CronRunInvocationBuilder: Sendable {
    public let defaultShellPath: String
    public let defaultPATH: String
    public let fallbackHomeDirectoryURL: URL
    public let currentUserName: String

    public init(
        defaultShellPath: String = "/bin/sh",
        defaultPATH: String = "/usr/bin:/bin",
        fallbackHomeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        currentUserName: String = NSUserName()
    ) {
        self.defaultShellPath = defaultShellPath
        self.defaultPATH = defaultPATH
        self.fallbackHomeDirectoryURL = fallbackHomeDirectoryURL
        self.currentUserName = currentUserName
    }

    public func makeInvocation(
        command: String,
        cronEnvironment: [String: String] = [:],
        inheritedEnvironment _: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> CronRunInvocation {
        guard !command.contains("\0") else {
            throw CronRunInvocationError.commandContainsNUL
        }

        for (name, value) in cronEnvironment {
            guard Self.isValidEnvironmentName(name) else {
                throw CronRunInvocationError.invalidEnvironmentVariableName(name)
            }
            guard !value.contains("\0") else {
                throw CronRunInvocationError.environmentValueContainsNUL(name: name)
            }
        }

        let configuredShell = cronEnvironment["SHELL"]
        let shellPath = configuredShell.flatMap { $0.isEmpty ? nil : $0 } ?? defaultShellPath
        guard shellPath.hasPrefix("/"), !shellPath.contains("\0") else {
            throw CronRunInvocationError.shellMustBeAnAbsolutePath(shellPath)
        }

        let homePath = cronEnvironment["HOME"]
            ?? fallbackHomeDirectoryURL.path
        guard homePath.hasPrefix("/"), !homePath.contains("\0") else {
            throw CronRunInvocationError.homeMustBeAnAbsolutePath(homePath)
        }

        let userName = currentUserName

        // Only explicit cron assignments cross the boundary. In particular,
        // app secrets, XPC variables, and loader variables are not inherited.
        var environment = cronEnvironment
        environment["SHELL"] = shellPath
        environment["HOME"] = homePath
        environment["LOGNAME"] = userName
        environment["USER"] = userName
        if environment["PATH"] == nil {
            environment["PATH"] = defaultPATH
        }

        let processedCommand = CronPercentPreprocessor.preprocess(command)
        let request = ProcessRequest(
            executableURL: URL(fileURLWithPath: shellPath, isDirectory: false),
            arguments: ["-c", processedCommand.shellCommand],
            environment: environment,
            currentDirectoryURL: URL(fileURLWithPath: homePath, isDirectory: true),
            standardInput: processedCommand.standardInput.map { Data($0.utf8) }
        )
        return CronRunInvocation(request: request)
    }

    /// Builds a job invocation with the environment assignments effective at
    /// that job's source line.
    public func makeInvocation(
        for job: CronJob,
        in document: CrontabDocument,
        inheritedEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> CronRunInvocation {
        var environment: [String: String] = [:]
        for line in document.lines.prefix(job.sourceLineIndex) {
            guard case let .environment(assignment) = line.kind else {
                continue
            }
            environment[assignment.name] = Self.semanticValue(of: assignment.value)
        }

        return try makeInvocation(
            command: job.command,
            cronEnvironment: environment,
            inheritedEnvironment: inheritedEnvironment
        )
    }

    private static func isValidEnvironmentName(_ name: String) -> Bool {
        guard let first = name.utf8.first,
              isASCIILetter(first) || first == 95
        else {
            return false
        }

        return name.utf8.dropFirst().allSatisfy { byte in
            isASCIILetter(byte) || (48 ... 57).contains(byte) || byte == 95
        }
    }

    private static func isASCIILetter(_ byte: UInt8) -> Bool {
        (65 ... 90).contains(byte) || (97 ... 122).contains(byte)
    }

    private static func semanticValue(of source: String) -> String {
        let leadingTrimmed = source.drop(while: { $0 == " " || $0 == "\t" })
        guard leadingTrimmed.count >= 2,
              let first = leadingTrimmed.first,
              (first == "\"" || first == "'"),
              leadingTrimmed.last == first
        else {
            return String(leadingTrimmed)
        }
        return String(leadingTrimmed.dropFirst().dropLast())
    }
}

public enum RunNowExecutionError: Error, Sendable, Equatable {
    case duplicateRun(RunNowInvocationID)
}

public protocol RunNowExecuting: Sendable {
    func execute(_ invocation: CronRunInvocation) async throws -> ProcessResult
}

/// Executes Run Now requests and suppresses a duplicate while the same exact
/// invocation is still active.
public actor RunNowExecutor: RunNowExecuting {
    private let processExecutor: any ProcessExecuting
    private var activeInvocationIDs: Set<RunNowInvocationID> = []

    public init(processExecutor: any ProcessExecuting = FoundationProcessExecutor()) {
        self.processExecutor = processExecutor
    }

    public func execute(_ invocation: CronRunInvocation) async throws -> ProcessResult {
        guard activeInvocationIDs.insert(invocation.id).inserted else {
            throw RunNowExecutionError.duplicateRun(invocation.id)
        }
        defer {
            activeInvocationIDs.remove(invocation.id)
        }

        return try await processExecutor.execute(invocation.request)
    }
}
