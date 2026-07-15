import Darwin
import Foundation

/// Raw access to the current user's crontab.
public protocol CrontabClient: Sendable {
    func read() async throws -> Data
    func install(_ contents: Data) async throws
}

public enum CrontabClientOperation: String, Sendable, Equatable {
    case read
    case install
}

public struct CrontabCommandError: Error, Sendable, Equatable {
    public let operation: CrontabClientOperation
    public let terminationStatus: Int32
    public let standardOutput: Data
    public let standardError: Data

    public init(
        operation: CrontabClientOperation,
        terminationStatus: Int32,
        standardOutput: Data,
        standardError: Data
    ) {
        self.operation = operation
        self.terminationStatus = terminationStatus
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

public enum CrontabReadSafetyError: LocalizedError, Sendable, Equatable {
    case outputExceededLimit(bytes: Int)

    public var errorDescription: String? {
        switch self {
        case .outputExceededLimit(let bytes):
            let mebibytes = bytes / (1_024 * 1_024)
            return "The installed crontab exceeds CronHarbor's \(mebibytes) MiB safety limit. Nothing was changed."
        }
    }
}

/// The current-user-only `/usr/bin/crontab` adapter.
///
/// It deliberately has no API for selecting another user and never invokes a
/// shell. Installing uses a private, exclusively-created file whose mode is
/// verified as 0600 before its path is passed as the sole argument.
public actor SystemCrontabClient: CrontabClient {
    public static let executableURL = URL(fileURLWithPath: "/usr/bin/crontab")
    public static let maximumCrontabBytes = 16 * 1_024 * 1_024

    private let executor: any ProcessExecuting
    private let temporaryDirectoryURL: URL
    private let currentUserName: String

    public init(
        executor: any ProcessExecuting = FoundationProcessExecutor(),
        temporaryDirectoryURL: URL = FileManager.default.temporaryDirectory,
        currentUserName: String = NSUserName()
    ) {
        self.executor = executor
        self.temporaryDirectoryURL = temporaryDirectoryURL
        self.currentUserName = currentUserName
    }

    public func read() async throws -> Data {
        let result = try await executor.execute(
            ProcessRequest(
                executableURL: Self.executableURL,
                arguments: ["-l"],
                environment: ["LC_ALL": "C"],
                maximumCapturedBytesPerStream: Self.maximumCrontabBytes
            )
        )

        if result.terminationStatus == 0 {
            guard !result.standardOutputWasTruncated else {
                throw CrontabReadSafetyError.outputExceededLimit(
                    bytes: Self.maximumCrontabBytes
                )
            }
            return result.standardOutput
        }

        if isStandardNoCrontabResult(result) {
            return Data()
        }

        throw CrontabCommandError(
            operation: .read,
            terminationStatus: result.terminationStatus,
            standardOutput: result.standardOutput,
            standardError: result.standardError
        )
    }

    public func install(_ contents: Data) async throws {
        let temporaryFile = try makeSecureTemporaryFile(containing: contents)
        defer {
            try? FileManager.default.removeItem(at: temporaryFile.directoryURL)
        }

        let result = try await executor.execute(
            ProcessRequest(
                executableURL: Self.executableURL,
                arguments: [temporaryFile.fileURL.path],
                environment: ["LC_ALL": "C"]
            )
        )

        guard result.terminationStatus == 0 else {
            throw CrontabCommandError(
                operation: .install,
                terminationStatus: result.terminationStatus,
                standardOutput: result.standardOutput,
                standardError: result.standardError
            )
        }
    }

    private func isStandardNoCrontabResult(_ result: ProcessResult) -> Bool {
        guard result.terminationStatus == 1,
              result.standardOutput.isEmpty,
              var message = String(data: result.standardError, encoding: .utf8)
        else {
            return false
        }

        if message.hasSuffix("\n") {
            message.removeLast()
            if message.hasSuffix("\r") {
                message.removeLast()
            }
        }

        return message == "crontab: no crontab for \(currentUserName)"
    }

    private func makeSecureTemporaryFile(containing contents: Data) throws -> SecureTemporaryFile {
        guard temporaryDirectoryURL.isFileURL,
              temporaryDirectoryURL.path.hasPrefix("/")
        else {
            throw SecureTemporaryFileError.temporaryDirectoryMustBeAbsolute
        }

        let fileManager = FileManager.default
        let directoryURL = temporaryDirectoryURL.appendingPathComponent(
            "CronHarbor-\(UUID().uuidString)",
            isDirectory: true
        )

        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: NSNumber(value: 0o700)]
        )

        do {
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: 0o700)],
                ofItemAtPath: directoryURL.path
            )

            let directoryAttributes = try fileManager.attributesOfItem(atPath: directoryURL.path)
            let directoryPermissions = (directoryAttributes[.posixPermissions] as? NSNumber)?.intValue
            guard directoryAttributes[.type] as? FileAttributeType == .typeDirectory else {
                throw SecureTemporaryFileError.temporaryPathIsNotDirectory
            }
            guard directoryPermissions.map({ $0 & 0o777 }) == 0o700 else {
                throw SecureTemporaryFileError.directoryPermissionsWereNot0700
            }

            let fileURL = directoryURL.appendingPathComponent("crontab", isDirectory: false)
            try Self.writeExclusivePrivateFile(contents, to: fileURL)

            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
            guard attributes[.type] as? FileAttributeType == .typeRegular else {
                throw SecureTemporaryFileError.temporaryFileIsNotRegular
            }
            guard permissions.map({ $0 & 0o777 }) == 0o600 else {
                throw SecureTemporaryFileError.permissionsWereNot0600
            }

            return SecureTemporaryFile(fileURL: fileURL, directoryURL: directoryURL)
        } catch {
            try? fileManager.removeItem(at: directoryURL)
            throw error
        }
    }

    private static func writeExclusivePrivateFile(_ contents: Data, to fileURL: URL) throws {
        let descriptor = try fileURL.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else {
                throw SecureTemporaryFileError.invalidFileSystemPath
            }

            let descriptor = Darwin.open(
                path,
                O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
                mode_t(S_IRUSR | S_IWUSR)
            )
            guard descriptor >= 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            return descriptor
        }

        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            guard Darwin.fchmod(descriptor, mode_t(S_IRUSR | S_IWUSR)) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            try handle.write(contentsOf: contents)
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
    }
}

private struct SecureTemporaryFile {
    let fileURL: URL
    let directoryURL: URL
}

private enum SecureTemporaryFileError: Error {
    case temporaryDirectoryMustBeAbsolute
    case temporaryPathIsNotDirectory
    case directoryPermissionsWereNot0700
    case temporaryFileIsNotRegular
    case invalidFileSystemPath
    case permissionsWereNot0600
}
