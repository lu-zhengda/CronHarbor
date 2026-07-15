import Foundation
import Testing
@testable import CronHarborCore

@Test
func systemCrontabReadUsesFixedExecutableAndSafeArguments() async throws {
    let expected = Data("* * * * * /usr/bin/true\n".utf8)
    let executor = QueueProcessExecutor(
        responses: [ProcessResult(terminationStatus: 0, standardOutput: expected)]
    )
    let client = SystemCrontabClient(
        executor: executor,
        currentUserName: "unit-test-user"
    )

    let actual = try await client.read()
    let requests = await executor.requests()
    let request = try #require(requests.first)

    #expect(actual == expected)
    #expect(requests.count == 1)
    #expect(request.executableURL.path == "/usr/bin/crontab")
    #expect(request.arguments == ["-l"])
    #expect(request.environment == ["LC_ALL": "C"])
    #expect(request.maximumCapturedBytesPerStream == SystemCrontabClient.maximumCrontabBytes)
    #expect(!request.arguments.contains("-u"))
}

@Test
func systemCrontabReadRejectsTruncatedAuthoritativeOutput() async throws {
    let executor = QueueProcessExecutor(
        responses: [
            ProcessResult(
                terminationStatus: 0,
                standardOutput: Data(repeating: 0x61, count: 32),
                standardOutputWasTruncated: true
            )
        ]
    )
    let client = SystemCrontabClient(executor: executor, currentUserName: "tester")

    await #expect(throws: CrontabReadSafetyError.outputExceededLimit(
        bytes: SystemCrontabClient.maximumCrontabBytes
    )) {
        _ = try await client.read()
    }
}

@Test
func systemCrontabReadTreatsOnlyCanonicalMissingCrontabAsEmpty() async throws {
    let missing = QueueProcessExecutor(
        responses: [
            ProcessResult(
                terminationStatus: 1,
                standardError: Data("crontab: no crontab for unit-test-user\n".utf8)
            ),
        ]
    )
    let missingClient = SystemCrontabClient(
        executor: missing,
        currentUserName: "unit-test-user"
    )
    #expect(try await missingClient.read() == Data())

    let unrelatedFailure = QueueProcessExecutor(
        responses: [
            ProcessResult(
                terminationStatus: 1,
                standardError: Data("crontab: permission denied\n".utf8)
            ),
        ]
    )
    let failingClient = SystemCrontabClient(
        executor: unrelatedFailure,
        currentUserName: "unit-test-user"
    )

    do {
        _ = try await failingClient.read()
        Issue.record("Expected a non-canonical failure to be surfaced")
    } catch let error as CrontabCommandError {
        #expect(error.operation == .read)
        #expect(error.terminationStatus == 1)
    }
}

@Test
func systemCrontabInstallUsesExclusive0600FileAndDeletesItAfterward() async throws {
    let temporaryDirectory = try platformTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let contents = Data("MAILTO=\"\"\n0 9 * * * /usr/bin/true\n".utf8)
    let executor = QueueProcessExecutor(
        responses: [ProcessResult(terminationStatus: 0)],
        inspectInstallFiles: true
    )
    let client = SystemCrontabClient(
        executor: executor,
        temporaryDirectoryURL: temporaryDirectory,
        currentUserName: "unit-test-user"
    )

    try await client.install(contents)

    let requests = await executor.requests()
    let files = await executor.installFiles()
    let request = try #require(requests.first)
    let file = try #require(files.first)
    #expect(requests.count == 1)
    #expect(request.executableURL.path == "/usr/bin/crontab")
    #expect(request.arguments.count == 1)
    #expect(!request.arguments.contains("-u"))
    #expect(request.environment == ["LC_ALL": "C"])
    #expect(files.count == 1)
    #expect(file.contents == contents)
    #expect(file.permissions == 0o600)
    #expect(file.isRegularFile)
    #expect(file.directoryPermissions == 0o700)
    #expect(file.isDirectory)
    #expect(!FileManager.default.fileExists(atPath: file.path))
    #expect(!FileManager.default.fileExists(atPath: file.directoryPath))
}

@Test
func systemCrontabInstallSurfacesFailureAndStillCleansUp() async throws {
    let temporaryDirectory = try platformTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let executor = QueueProcessExecutor(
        responses: [
            ProcessResult(
                terminationStatus: 2,
                standardError: Data("syntax error\n".utf8)
            ),
        ],
        inspectInstallFiles: true
    )
    let client = SystemCrontabClient(
        executor: executor,
        temporaryDirectoryURL: temporaryDirectory,
        currentUserName: "unit-test-user"
    )

    do {
        try await client.install(Data("bad".utf8))
        Issue.record("Expected install failure")
    } catch let error as CrontabCommandError {
        #expect(error.operation == .install)
        #expect(error.terminationStatus == 2)
    }

    let files = await executor.installFiles()
    let file = try #require(files.first)
    #expect(files.count == 1)
    #expect(file.permissions == 0o600)
    #expect(file.isRegularFile)
    #expect(file.directoryPermissions == 0o700)
    #expect(file.isDirectory)
    #expect(!FileManager.default.fileExists(atPath: file.path))
    #expect(!FileManager.default.fileExists(atPath: file.directoryPath))
}

@Test
func systemCrontabRejectsRelativeTemporaryDirectoryBeforeProcessExecution() async throws {
    let executor = QueueProcessExecutor(
        responses: [ProcessResult(terminationStatus: 0)]
    )
    let client = SystemCrontabClient(
        executor: executor,
        temporaryDirectoryURL: URL(string: "relative-temp")!,
        currentUserName: "unit-test-user"
    )

    do {
        try await client.install(Data("safe".utf8))
        Issue.record("Expected a relative temporary directory to be rejected")
    } catch {
        // The concrete filesystem error is intentionally an implementation
        // detail; the safety property is that no process boundary was crossed.
    }

    #expect(await executor.requests().isEmpty)
}
