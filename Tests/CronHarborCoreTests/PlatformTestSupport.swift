import Foundation
@testable import CronHarborCore

struct ObservedInstallFile: Sendable, Equatable {
    let path: String
    let directoryPath: String
    let contents: Data?
    let permissions: Int?
    let isRegularFile: Bool
    let directoryPermissions: Int?
    let isDirectory: Bool
}

actor QueueProcessExecutor: ProcessExecuting {
    private var responses: [ProcessResult]
    private var recordedRequests: [ProcessRequest] = []
    private var recordedInstallFiles: [ObservedInstallFile] = []
    private let inspectInstallFiles: Bool

    init(
        responses: [ProcessResult],
        inspectInstallFiles: Bool = false
    ) {
        self.responses = responses
        self.inspectInstallFiles = inspectInstallFiles
    }

    func execute(_ request: ProcessRequest) async throws -> ProcessResult {
        recordedRequests.append(request)

        if inspectInstallFiles,
           request.arguments.count == 1,
           request.arguments[0] != "-l" {
            let path = request.arguments[0]
            let attributes = try? FileManager.default.attributesOfItem(atPath: path)
            let permissions = (attributes?[.posixPermissions] as? NSNumber)?.intValue
            let directoryPath = URL(fileURLWithPath: path).deletingLastPathComponent().path
            let directoryAttributes = try? FileManager.default.attributesOfItem(
                atPath: directoryPath
            )
            let directoryPermissions = (
                directoryAttributes?[.posixPermissions] as? NSNumber
            )?.intValue
            recordedInstallFiles.append(
                ObservedInstallFile(
                    path: path,
                    directoryPath: directoryPath,
                    contents: try? Data(contentsOf: URL(fileURLWithPath: path)),
                    permissions: permissions.map { $0 & 0o777 },
                    isRegularFile: attributes?[.type] as? FileAttributeType == .typeRegular,
                    directoryPermissions: directoryPermissions.map { $0 & 0o777 },
                    isDirectory: directoryAttributes?[.type] as? FileAttributeType == .typeDirectory
                )
            )
        }

        precondition(!responses.isEmpty, "Unexpected process execution")
        return responses.removeFirst()
    }

    func requests() -> [ProcessRequest] {
        recordedRequests
    }

    func installFiles() -> [ObservedInstallFile] {
        recordedInstallFiles
    }
}

actor BackupInstallOrderProbe {
    private var backupCompleted = false
    private var installSawBackup = false

    func markBackupCompleted() {
        backupCompleted = true
    }

    func markInstallStarted() {
        installSawBackup = backupCompleted
    }

    func installStartedAfterBackup() -> Bool {
        installSawBackup
    }
}

actor StubBackupStore: CrontabBackupStoring {
    private var saved: [Data] = []
    private let url: URL
    private let orderProbe: BackupInstallOrderProbe?

    init(
        url: URL = URL(fileURLWithPath: "/tmp/cronharbor-test.backup"),
        orderProbe: BackupInstallOrderProbe? = nil
    ) {
        self.url = url
        self.orderProbe = orderProbe
    }

    func saveBackup(contents: Data) async throws -> URL {
        saved.append(contents)
        await orderProbe?.markBackupCompleted()
        return url
    }

    func savedContents() -> [Data] {
        saved
    }
}

actor RecordingCrontabClient: CrontabClient {
    private var contents: Data
    private let installedReadbackOverride: Data?
    private let orderProbe: BackupInstallOrderProbe?
    private var installed: [Data] = []
    private var readCount = 0

    init(
        contents: Data,
        installedReadbackOverride: Data? = nil,
        orderProbe: BackupInstallOrderProbe? = nil
    ) {
        self.contents = contents
        self.installedReadbackOverride = installedReadbackOverride
        self.orderProbe = orderProbe
    }

    func read() async throws -> Data {
        readCount += 1
        return contents
    }

    func install(_ contents: Data) async throws {
        await orderProbe?.markInstallStarted()
        installed.append(contents)
        self.contents = installedReadbackOverride ?? contents
    }

    func replaceContents(_ contents: Data) {
        self.contents = contents
    }

    func installs() -> [Data] {
        installed
    }

    func reads() -> Int {
        readCount
    }
}

actor BlockingCrontabClient: CrontabClient {
    private var contents: Data
    private var readCount = 0
    private var installed: [Data] = []
    private var firstInstallStarted = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    init(contents: Data) {
        self.contents = contents
    }

    func read() async throws -> Data {
        readCount += 1
        return contents
    }

    func install(_ contents: Data) async throws {
        installed.append(contents)

        if installed.count == 1 {
            firstInstallStarted = true
            let waiters = startWaiters
            startWaiters.removeAll()
            waiters.forEach { $0.resume() }

            await withCheckedContinuation { continuation in
                releaseContinuation = continuation
            }
        }

        self.contents = contents
    }

    func waitUntilFirstInstallStarts() async {
        if firstInstallStarted {
            return
        }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func releaseFirstInstall() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    func reads() -> Int {
        readCount
    }

    func installs() -> [Data] {
        installed
    }
}

actor BlockingProcessExecutor: ProcessExecuting {
    private let result: ProcessResult
    private var callCount = 0
    private var firstCallStarted = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    init(result: ProcessResult) {
        self.result = result
    }

    func execute(_ request: ProcessRequest) async throws -> ProcessResult {
        callCount += 1
        if callCount == 1 {
            firstCallStarted = true
            let waiters = startWaiters
            startWaiters.removeAll()
            waiters.forEach { $0.resume() }

            await withCheckedContinuation { continuation in
                releaseContinuation = continuation
            }
        }
        return result
    }

    func waitUntilFirstCallStarts() async {
        if firstCallStarted {
            return
        }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func releaseFirstCall() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    func calls() -> Int {
        callCount
    }
}

func platformTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
        "CronHarborTests-\(UUID().uuidString)",
        isDirectory: true
    )
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    return url
}
