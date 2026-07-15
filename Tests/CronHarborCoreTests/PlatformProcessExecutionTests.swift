import Foundation
import Testing
@testable import CronHarborCore

@Test
func foundationProcessExecutorCapturesStdoutStderrAndSuppliesStdin() async throws {
    let executor = FoundationProcessExecutor()
    let result = try await executor.execute(
        ProcessRequest(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: [
                "-c",
                "IFS= read -r line; printf 'out:%s' \"$line\"; printf 'err:%s' \"$line\" >&2; exit 3",
            ],
            environment: ["LC_ALL": "C"],
            standardInput: Data("payload\n".utf8)
        )
    )

    #expect(result.terminationStatus == 3)
    #expect(result.standardOutput == Data("out:payload".utf8))
    #expect(result.standardError == Data("err:payload".utf8))
    #expect(!result.standardOutputWasTruncated)
    #expect(!result.standardErrorWasTruncated)
}

@Test
func foundationProcessExecutorCapsButFullyDrainsNoisyOutput() async throws {
    let captureLimit = 4_096
    let executor = FoundationProcessExecutor(
        maximumCapturedBytesPerStream: captureLimit
    )
    let result = try await executor.execute(
        ProcessRequest(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: [
                "-c",
                "/usr/bin/yes O | /usr/bin/head -c 262144; "
                    + "/usr/bin/yes E | /usr/bin/head -c 262144 >&2",
            ],
            environment: ["LC_ALL": "C"]
        )
    )

    #expect(result.terminationStatus == 0)
    #expect(result.standardOutput.count == captureLimit)
    #expect(result.standardError.count == captureLimit)
    #expect(result.standardOutput.prefix(2) == Data("O\n".utf8))
    #expect(result.standardError.prefix(2) == Data("E\n".utf8))
    #expect(result.standardOutputWasTruncated)
    #expect(result.standardErrorWasTruncated)
}

@Test
func processRequestCanRaiseTheCaptureLimitForAuthoritativeOutput() async throws {
    let executor = FoundationProcessExecutor(maximumCapturedBytesPerStream: 4)
    let result = try await executor.execute(
        ProcessRequest(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf 12345678"],
            environment: ["LC_ALL": "C"],
            maximumCapturedBytesPerStream: 8
        )
    )

    #expect(result.standardOutput == Data("12345678".utf8))
    #expect(!result.standardOutputWasTruncated)
}

@Test
func foundationProcessExecutorRejectsNonAbsoluteExecutableBeforeLaunch() async throws {
    let executor = FoundationProcessExecutor()
    let relativeURL = URL(string: "relative-program")!

    do {
        _ = try await executor.execute(ProcessRequest(executableURL: relativeURL))
        Issue.record("Expected relative executable rejection")
    } catch let error as ProcessExecutionError {
        #expect(error == .executableMustBeAnAbsoluteFileURL(relativeURL))
    }
}
