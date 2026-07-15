import Foundation
import Testing
@testable import CronHarborCore

@Test
func repositoryConflictPreventsBackupAndInstall() async throws {
    let originallyRead = Data("old\n".utf8)
    let externallyChanged = Data("changed elsewhere\n".utf8)
    let client = RecordingCrontabClient(contents: externallyChanged)
    let backupStore = StubBackupStore()
    let repository = CrontabRepository(client: client, backupStore: backupStore)

    do {
        _ = try await repository.install(
            contents: Data("replacement\n".utf8),
            expectedDigest: CrontabDigest(contents: originallyRead)
        )
        Issue.record("Expected a digest conflict")
    } catch let error as CrontabRepositoryError {
        #expect(
            error == .conflict(
                expected: CrontabDigest(contents: originallyRead),
                actual: CrontabDigest(contents: externallyChanged)
            )
        )
    }

    #expect(await client.installs().isEmpty)
    #expect(await backupStore.savedContents().isEmpty)
}

@Test
func repositoryBacksUpCurrentBytesBeforeInstallAndVerifiesReadback() async throws {
    let old = Data("old bytes\n".utf8)
    let replacement = Data("new bytes\n".utf8)
    let backupURL = URL(fileURLWithPath: "/tmp/expected.backup")
    let probe = BackupInstallOrderProbe()
    let client = RecordingCrontabClient(contents: old, orderProbe: probe)
    let backupStore = StubBackupStore(url: backupURL, orderProbe: probe)
    let repository = CrontabRepository(client: client, backupStore: backupStore)

    let receipt = try await repository.install(
        contents: replacement,
        expectedDigest: CrontabDigest(contents: old)
    )

    #expect(await backupStore.savedContents() == [old])
    #expect(await probe.installStartedAfterBackup())
    #expect(await client.installs() == [replacement])
    #expect(await client.reads() == 3)
    #expect(receipt.backupURL == backupURL)
    #expect(receipt.snapshot.contents == replacement)
}

@Test
func repositoryStopsWhenCrontabDriftsWhileBackupIsBeingSaved() async throws {
    let old = Data("old\n".utf8)
    let externallyChanged = Data("changed during backup\n".utf8)
    let requested = Data("new\n".utf8)
    let client = RecordingCrontabClient(contents: old)
    let backupStore = DriftingBackupStore(
        client: client,
        replacement: externallyChanged
    )
    let repository = CrontabRepository(client: client, backupStore: backupStore)

    do {
        _ = try await repository.install(
            contents: requested,
            expectedDigest: CrontabDigest(contents: old)
        )
        Issue.record("Expected the pre-install drift check to fail")
    } catch let error as CrontabRepositoryError {
        #expect(
            error == .conflict(
                expected: CrontabDigest(contents: old),
                actual: CrontabDigest(contents: externallyChanged)
            )
        )
    }

    #expect(await backupStore.savedContents() == [old])
    #expect(await client.installs().isEmpty)
    #expect(await client.reads() == 2)
}

@Test
func repositoryReportsUnknownInstalledStateWhenPostInstallReadbackThrows() async throws {
    let old = Data("old\n".utf8)
    let requested = Data("new\n".utf8)
    let backupURL = URL(fileURLWithPath: "/tmp/readback-failed.backup")
    let client = FailingReadbackCrontabClient(contents: old)
    let backupStore = StubBackupStore(url: backupURL)
    let repository = CrontabRepository(client: client, backupStore: backupStore)

    do {
        _ = try await repository.install(
            contents: requested,
            expectedDigest: CrontabDigest(contents: old)
        )
        Issue.record("Expected post-install readback to fail")
    } catch let error as CrontabRepositoryError {
        #expect(error == .installedStateUnknown(backupURL: backupURL))
    }

    #expect(await backupStore.savedContents() == [old])
    #expect(await client.installs() == [requested])
    #expect(await client.reads() == 3)
}

@Test
func repositoryRejectsNonExactPostInstallReadbackAndReturnsBackupInError() async throws {
    let old = Data("old\n".utf8)
    let requested = Data("new\n".utf8)
    let altered = Data("new\n\n".utf8)
    let backupURL = URL(fileURLWithPath: "/tmp/readback.backup")
    let client = RecordingCrontabClient(
        contents: old,
        installedReadbackOverride: altered
    )
    let backupStore = StubBackupStore(url: backupURL)
    let repository = CrontabRepository(client: client, backupStore: backupStore)

    do {
        _ = try await repository.install(
            contents: requested,
            expectedDigest: CrontabDigest(contents: old)
        )
        Issue.record("Expected exact readback verification to fail")
    } catch let error as CrontabRepositoryError {
        #expect(
            error == .readbackMismatch(
                expected: CrontabDigest(contents: requested),
                actual: CrontabDigest(contents: altered),
                backupURL: backupURL
            )
        )
    }

    #expect(await backupStore.savedContents() == [old])
    #expect(await client.installs() == [requested])
}

@Test
func fileBackupStoreWritesExactBytesWith0600Permissions() async throws {
    let directory = try platformTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.setAttributes(
        [.posixPermissions: NSNumber(value: 0o777)],
        ofItemAtPath: directory.path
    )

    let bytes = Data([0, 10, 13, 0xff])
    let store = FileCrontabBackupStore(directoryURL: directory)
    let backupURL = try await store.saveBackup(contents: bytes)
    let attributes = try FileManager.default.attributesOfItem(atPath: backupURL.path)
    let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
    let directoryAttributes = try FileManager.default.attributesOfItem(atPath: directory.path)
    let directoryPermissions = (directoryAttributes[.posixPermissions] as? NSNumber)?.intValue

    #expect(try Data(contentsOf: backupURL) == bytes)
    #expect(permissions.map { $0 & 0o777 } == 0o600)
    #expect(directoryPermissions.map { $0 & 0o777 } == 0o700)
}

@Test
func repositorySerializesWholeWriteTransactionsAcrossActorSuspension() async throws {
    let old = Data("old\n".utf8)
    let firstReplacement = Data("first\n".utf8)
    let secondReplacement = Data("second\n".utf8)
    let client = BlockingCrontabClient(contents: old)
    let backupStore = StubBackupStore()
    let repository = CrontabRepository(client: client, backupStore: backupStore)

    let first = Task {
        try await repository.install(
            contents: firstReplacement,
            expectedDigest: CrontabDigest(contents: old)
        )
    }
    await client.waitUntilFirstInstallStarts()

    let second = Task {
        try await repository.install(
            contents: secondReplacement,
            expectedDigest: CrontabDigest(contents: firstReplacement)
        )
    }

    for _ in 0..<20 {
        await Task.yield()
    }
    #expect(await client.reads() == 2)

    await client.releaseFirstInstall()
    _ = try await first.value
    _ = try await second.value

    #expect(await client.installs() == [firstReplacement, secondReplacement])
    #expect(await client.reads() == 6)
}

private actor DriftingBackupStore: CrontabBackupStoring {
    private let client: RecordingCrontabClient
    private let replacement: Data
    private var saved: [Data] = []

    init(client: RecordingCrontabClient, replacement: Data) {
        self.client = client
        self.replacement = replacement
    }

    func saveBackup(contents: Data) async throws -> URL {
        saved.append(contents)
        await client.replaceContents(replacement)
        return URL(fileURLWithPath: "/tmp/drift.backup")
    }

    func savedContents() -> [Data] {
        saved
    }
}

private actor FailingReadbackCrontabClient: CrontabClient {
    private var contents: Data
    private var installed: [Data] = []
    private var readCount = 0

    init(contents: Data) {
        self.contents = contents
    }

    func read() async throws -> Data {
        readCount += 1
        if readCount == 3 {
            throw FailingReadbackError.readFailed
        }
        return contents
    }

    func install(_ contents: Data) async throws {
        installed.append(contents)
        self.contents = contents
    }

    func installs() -> [Data] {
        installed
    }

    func reads() -> Int {
        readCount
    }
}

private enum FailingReadbackError: Error {
    case readFailed
}
