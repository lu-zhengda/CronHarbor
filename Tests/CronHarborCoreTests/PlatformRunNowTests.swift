import Foundation
import Testing
@testable import CronHarborCore

@Test
func runNowBuilderUsesEffectiveShellHomeAndSanitizedCronEnvironment() throws {
    let builder = CronRunInvocationBuilder(
        fallbackHomeDirectoryURL: URL(fileURLWithPath: "/fallback", isDirectory: true),
        currentUserName: "fallback-user"
    )
    let invocation = try builder.makeInvocation(
        command: "printf hello\\%world%line one%line two",
        cronEnvironment: [
            "SHELL": "/bin/zsh",
            "HOME": "/Users/cron-user",
            "CUSTOM": "kept",
            "PATH": "/custom/bin",
        ],
        inheritedEnvironment: [
            "LOGNAME": "cron-user",
            "APP_SECRET": "must-not-leak",
            "DYLD_INSERT_LIBRARIES": "/tmp/not-inherited.dylib",
        ]
    )

    #expect(invocation.request.executableURL.path == "/bin/zsh")
    #expect(invocation.request.arguments == ["-c", "printf hello%world"])
    #expect(invocation.request.standardInput == Data("line one\nline two".utf8))
    #expect(invocation.request.currentDirectoryURL?.path == "/Users/cron-user")
    #expect(invocation.request.environment?["SHELL"] == "/bin/zsh")
    #expect(invocation.request.environment?["HOME"] == "/Users/cron-user")
    #expect(invocation.request.environment?["LOGNAME"] == "fallback-user")
    #expect(invocation.request.environment?["USER"] == "fallback-user")
    #expect(invocation.request.environment?["CUSTOM"] == "kept")
    #expect(invocation.request.environment?["PATH"] == "/custom/bin")
    #expect(invocation.request.environment?["APP_SECRET"] == nil)
    #expect(invocation.request.environment?["DYLD_INSERT_LIBRARIES"] == nil)
}

@Test
func runNowBuilderDefaultsToBinShAndMinimalPath() throws {
    let builder = CronRunInvocationBuilder(
        fallbackHomeDirectoryURL: URL(fileURLWithPath: "/fallback-home", isDirectory: true),
        currentUserName: "test-user"
    )
    let invocation = try builder.makeInvocation(
        command: "/usr/bin/true",
        inheritedEnvironment: [:]
    )

    #expect(invocation.request.executableURL.path == "/bin/sh")
    #expect(invocation.request.arguments == ["-c", "/usr/bin/true"])
    #expect(invocation.request.currentDirectoryURL?.path == "/fallback-home")
    #expect(invocation.request.environment?["PATH"] == "/usr/bin:/bin")
    #expect(invocation.request.environment?["USER"] == "test-user")
}

@Test
func runNowBuilderUsesDocumentEnvironmentEffectiveAtJobLine() throws {
    let document = CrontabDocument(
        data: Data(
            "SHELL = \"/bin/zsh\"\nHOME = '/tmp/cron home'\n* * * * * echo ready\nSHELL=/bin/false\n".utf8
        )
    )
    let job = try #require(document.jobs.first)
    let builder = CronRunInvocationBuilder(currentUserName: "test-user")

    let invocation = try builder.makeInvocation(
        for: job,
        in: document,
        inheritedEnvironment: [:]
    )

    #expect(invocation.request.executableURL.path == "/bin/zsh")
    #expect(invocation.request.currentDirectoryURL?.path == "/tmp/cron home")
}

@Test
func runNowBuilderUsesAccountDefaultsAndPreservesUnquotedTrailingSpaces() throws {
    let document = CrontabDocument(
        data: Data("CUSTOM = value  \n* * * * * /usr/bin/true\n".utf8)
    )
    let job = try #require(document.jobs.first)
    let builder = CronRunInvocationBuilder(
        fallbackHomeDirectoryURL: URL(fileURLWithPath: "/account-home", isDirectory: true),
        currentUserName: "account-user"
    )

    let invocation = try builder.makeInvocation(
        for: job,
        in: document,
        inheritedEnvironment: [
            "HOME": "/gui-home",
            "LOGNAME": "gui-user",
            "USER": "gui-user",
        ]
    )

    #expect(invocation.request.currentDirectoryURL?.path == "/account-home")
    #expect(invocation.request.environment?["HOME"] == "/account-home")
    #expect(invocation.request.environment?["LOGNAME"] == "account-user")
    #expect(invocation.request.environment?["USER"] == "account-user")
    #expect(invocation.request.environment?["CUSTOM"] == "value  ")
}

@Test
func runNowBuilderRejectsRelativeShellAndInvalidEnvironmentNames() throws {
    let builder = CronRunInvocationBuilder()

    #expect(throws: CronRunInvocationError.shellMustBeAnAbsolutePath("zsh")) {
        try builder.makeInvocation(
            command: "true",
            cronEnvironment: ["SHELL": "zsh"]
        )
    }
    #expect(throws: CronRunInvocationError.invalidEnvironmentVariableName("BAD-NAME")) {
        try builder.makeInvocation(
            command: "true",
            cronEnvironment: ["BAD-NAME": "value"]
        )
    }
}

@Test
func runNowExecutorReturnsCapturedBytesAndSuppressesAnActiveDuplicate() async throws {
    let expected = ProcessResult(
        terminationStatus: 7,
        standardOutput: Data("stdout".utf8),
        standardError: Data("stderr".utf8)
    )
    let processExecutor = BlockingProcessExecutor(result: expected)
    let executor = RunNowExecutor(processExecutor: processExecutor)
    let invocation = try CronRunInvocationBuilder().makeInvocation(
        command: "echo test",
        inheritedEnvironment: ["HOME": "/tmp", "USER": "tester"]
    )

    let first = Task {
        try await executor.execute(invocation)
    }
    await processExecutor.waitUntilFirstCallStarts()

    do {
        _ = try await executor.execute(invocation)
        Issue.record("Expected duplicate run suppression")
    } catch let error as RunNowExecutionError {
        #expect(error == .duplicateRun(invocation.id))
    }

    await processExecutor.releaseFirstCall()
    #expect(try await first.value == expected)
    #expect(try await executor.execute(invocation) == expected)
    #expect(await processExecutor.calls() == 2)
}
