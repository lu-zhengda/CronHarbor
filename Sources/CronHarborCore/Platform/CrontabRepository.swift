import CryptoKit
import Darwin
import Foundation

public struct CrontabDigest: Sendable, Hashable, CustomStringConvertible {
    public let rawValue: Data

    public init(contents: Data) {
        rawValue = Data(SHA256.hash(data: contents))
    }

    public var description: String {
        rawValue.map { String(format: "%02x", $0) }.joined()
    }
}

public struct CrontabSnapshot: Sendable, Equatable {
    public let contents: Data
    public let digest: CrontabDigest

    public init(contents: Data) {
        self.contents = contents
        digest = CrontabDigest(contents: contents)
    }
}

public struct CrontabWriteReceipt: Sendable, Equatable {
    public let snapshot: CrontabSnapshot
    public let backupURL: URL

    public init(snapshot: CrontabSnapshot, backupURL: URL) {
        self.snapshot = snapshot
        self.backupURL = backupURL
    }
}

public enum CrontabRepositoryError: Error, Sendable, Equatable {
    case conflict(expected: CrontabDigest, actual: CrontabDigest)
    case installedStateUnknown(backupURL: URL)
    case readbackMismatch(
        expected: CrontabDigest,
        actual: CrontabDigest,
        backupURL: URL
    )
}

public protocol CrontabBackupStoring: Sendable {
    func saveBackup(contents: Data) async throws -> URL
}

public protocol CrontabRepositoryProtocol: Sendable {
    func read() async throws -> CrontabSnapshot
    func install(
        contents: Data,
        expectedDigest: CrontabDigest
    ) async throws -> CrontabWriteReceipt
}

/// A filesystem backup store that exclusively creates every backup and fixes
/// and verifies its POSIX permissions before returning it.
public actor FileCrontabBackupStore: CrontabBackupStoring {
    public let directoryURL: URL

    public init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    public func saveBackup(contents: Data) async throws -> URL {
        guard directoryURL.isFileURL, directoryURL.path.hasPrefix("/") else {
            throw BackupFileError.directoryMustBeAbsolute
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: 0o700)]
        )
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: 0o700)],
            ofItemAtPath: directoryURL.path
        )

        let directoryAttributes = try fileManager.attributesOfItem(atPath: directoryURL.path)
        let directoryPermissions = (directoryAttributes[.posixPermissions] as? NSNumber)?.intValue
        guard directoryAttributes[.type] as? FileAttributeType == .typeDirectory else {
            throw BackupFileError.backupPathIsNotDirectory
        }
        guard directoryPermissions.map({ $0 & 0o777 }) == 0o700 else {
            throw BackupFileError.directoryPermissionsWereNot0700
        }

        let fileURL = directoryURL.appendingPathComponent(
            "crontab-\(UUID().uuidString).backup",
            isDirectory: false
        )

        do {
            try Self.writeExclusivePrivateFile(contents, to: fileURL)

            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
            guard attributes[.type] as? FileAttributeType == .typeRegular else {
                throw BackupFileError.backupIsNotRegularFile
            }
            guard permissions.map({ $0 & 0o777 }) == 0o600 else {
                throw BackupFileError.permissionsWereNot0600
            }

            return fileURL
        } catch {
            try? fileManager.removeItem(at: fileURL)
            throw error
        }
    }

    /// Creates the backup inode and its private mode in one exclusive `open(2)`
    /// operation. `O_EXCL` prevents an existing path from ever being replaced,
    /// while `O_NOFOLLOW` rejects a symlink at the generated destination.
    private static func writeExclusivePrivateFile(_ contents: Data, to fileURL: URL) throws {
        let descriptor = try fileURL.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else {
                throw BackupFileError.invalidFileSystemPath
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

/// A serialized, digest-checked repository for the current user's crontab.
///
/// Every write transaction re-reads the source, verifies the caller's digest,
/// backs up those exact bytes, installs, and then requires an exact-byte
/// readback. The explicit gate is necessary because Swift actors are reentrant
/// at each client await.
public actor CrontabRepository: CrontabRepositoryProtocol {
    private let client: any CrontabClient
    private let backupStore: any CrontabBackupStoring
    private let writeGate = AsyncWriteGate()

    public init(
        client: any CrontabClient,
        backupStore: any CrontabBackupStoring
    ) {
        self.client = client
        self.backupStore = backupStore
    }

    public init(client: any CrontabClient, backupDirectoryURL: URL) {
        self.client = client
        backupStore = FileCrontabBackupStore(directoryURL: backupDirectoryURL)
    }

    public func read() async throws -> CrontabSnapshot {
        CrontabSnapshot(contents: try await client.read())
    }

    public func install(
        contents: Data,
        expectedDigest: CrontabDigest
    ) async throws -> CrontabWriteReceipt {
        let client = client
        let backupStore = backupStore

        return try await writeGate.withLock {
            let current = CrontabSnapshot(contents: try await client.read())
            guard current.digest == expectedDigest else {
                throw CrontabRepositoryError.conflict(
                    expected: expectedDigest,
                    actual: current.digest
                )
            }

            let backupURL = try await backupStore.saveBackup(contents: current.contents)

            // Backing up is an actor suspension point and may involve slow I/O.
            // Recheck immediately before install so an external edit made while
            // the backup was being persisted is never overwritten.
            let preInstall = CrontabSnapshot(contents: try await client.read())
            guard preInstall.digest == expectedDigest else {
                throw CrontabRepositoryError.conflict(
                    expected: expectedDigest,
                    actual: preInstall.digest
                )
            }

            try await client.install(contents)

            let installedBytes: Data
            do {
                installedBytes = try await client.read()
            } catch {
                // The install command completed successfully, so a failed
                // readback cannot safely be described as an unchanged crontab.
                throw CrontabRepositoryError.installedStateUnknown(
                    backupURL: backupURL
                )
            }
            guard installedBytes == contents else {
                throw CrontabRepositoryError.readbackMismatch(
                    expected: CrontabDigest(contents: contents),
                    actual: CrontabDigest(contents: installedBytes),
                    backupURL: backupURL
                )
            }

            return CrontabWriteReceipt(
                snapshot: CrontabSnapshot(contents: installedBytes),
                backupURL: backupURL
            )
        }
    }
}

private enum BackupFileError: Error {
    case directoryMustBeAbsolute
    case backupPathIsNotDirectory
    case directoryPermissionsWereNot0700
    case backupIsNotRegularFile
    case invalidFileSystemPath
    case permissionsWereNot0600
}

private actor AsyncWriteGate {
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func withLock<Value: Sendable>(
        _ operation: @Sendable () async throws -> Value
    ) async throws -> Value {
        await acquire()

        do {
            let value = try await operation()
            release()
            return value
        } catch {
            release()
            throw error
        }
    }

    private func acquire() async {
        guard isLocked else {
            isLocked = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        guard !waiters.isEmpty else {
            isLocked = false
            return
        }

        let next = waiters.removeFirst()
        next.resume()
    }
}
