import Darwin
import Foundation

struct ProcessInvocation: Sendable {
    let executable: URL
    let arguments: [String]
    let environment: [String: String]
    let workingDirectory: URL
    let standardInput: Data
}

struct ProcessOutput: Sendable {
    let exitCode: Int32
    let standardOutput: Data
    let standardError: Data
}

enum ProcessRunError: Error, Equatable {
    case timedOut
}

/// Seam for the summarizer's tests: canned outputs replace a real `claude` launch.
protocol ProcessRunning: Sendable {
    /// Throws `ProcessRunError.timedOut` or `CancellationError`; in both cases the process is terminated.
    func run(_ invocation: ProcessInvocation, timeout: Duration) async throws -> ProcessOutput
}

/// Runs a child process with stdin, collecting stdout/stderr without blocking Swift's cooperative threads.
struct ProcessRunner: ProcessRunning {
    func run(_ invocation: ProcessInvocation, timeout: Duration) async throws -> ProcessOutput {
        let process = Process()
        process.executableURL = invocation.executable
        process.arguments = invocation.arguments
        process.environment = invocation.environment
        process.currentDirectoryURL = invocation.workingDirectory
        let input = Pipe(), output = Pipe(), error = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error
        // A child that exits before reading all of stdin would otherwise kill Rec with SIGPIPE.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)

        try process.run()
        let control = ProcessControl(process)
        Self.feed(invocation.standardInput, to: input.fileHandleForWriting)

        return try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: ProcessOutput?.self) { group in
                group.addTask { await Self.collect(process, output: output, error: error) }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    return nil
                }
                defer { group.cancelAll() }
                guard let first = try await group.next(), let result = first else {
                    control.terminate()
                    throw ProcessRunError.timedOut
                }
                return result
            }
        } onCancel: {
            control.terminate()
        }
    }

    private static func feed(_ data: Data, to handle: FileHandle) {
        DispatchQueue.global(qos: .userInitiated).async {
            // A write error means the child already exited; its exit code and output tell why.
            try? handle.write(contentsOf: data)
            try? handle.close()
        }
    }

    private static func collect(_ process: Process, output: Pipe, error: Pipe) async -> ProcessOutput {
        async let stdout = readToEnd(output.fileHandleForReading)
        async let stderr = readToEnd(error.fileHandleForReading)
        let (out, err) = await (stdout, stderr)
        let exitCode = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                process.waitUntilExit()
                continuation.resume(returning: process.terminationStatus)
            }
        }
        return ProcessOutput(exitCode: exitCode, standardOutput: out, standardError: err)
    }

    private static func readToEnd(_ handle: FileHandle) async -> Data {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: (try? handle.readToEnd()) ?? Data())
            }
        }
    }
}

/// `Process` isn't Sendable; this wrapper only exposes the thread-safe `terminate`.
private final class ProcessControl: @unchecked Sendable {
    private let process: Process

    init(_ process: Process) {
        self.process = process
    }

    func terminate() {
        if process.isRunning { process.terminate() }
    }
}
