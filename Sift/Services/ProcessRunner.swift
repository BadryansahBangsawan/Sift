import Foundation

/// Runs one child process and always drains both pipes. A child that fills the
/// 64 KB stderr buffer before writing stdout cannot deadlock the caller; a
/// child that ignores SIGTERM is killed after a short grace.
enum ProcessRunner {
    struct Result: Sendable {
        let status: Int32
        let stdout: String
        let stderr: String
        let timedOut: Bool
    }

    static let terminationGrace: TimeInterval = 1

    static func run(
        executable: URL,
        arguments: [String],
        timeout: TimeInterval,
        environment: [String: String]? = nil
    ) -> Result {
        let task = Process()
        task.executableURL = executable
        task.arguments = arguments
        if let environment { task.environment = environment }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        task.standardOutput = stdoutPipe
        task.standardError = stderrPipe
        task.standardInput = FileHandle.nullDevice

        do {
            try task.run()
        } catch {
            return Result(status: -1, stdout: "", stderr: error.localizedDescription, timedOut: false)
        }

        let outBox = LockedProcessData()
        let errBox = LockedProcessData()
        let readers = DispatchGroup()
        let queue = DispatchQueue(label: "com.sift.process-runner.pipes", attributes: .concurrent)
        for (pipe, box) in [(stdoutPipe, outBox), (stderrPipe, errBox)] {
            readers.enter()
            queue.async {
                box.set(pipe.fileHandleForReading.readDataToEndOfFile())
                readers.leave()
            }
        }

        let drained = readers.wait(timeout: .now() + max(0.1, timeout)) == .success
        if !drained {
            task.terminate()
            if readers.wait(timeout: .now() + terminationGrace) != .success {
                kill(task.processIdentifier, SIGKILL)
                _ = readers.wait(timeout: .now() + terminationGrace)
            }
        }
        task.waitUntilExit()

        return Result(
            status: drained ? task.terminationStatus : -1,
            stdout: String(data: outBox.value, encoding: .utf8) ?? "",
            stderr: String(data: errBox.value, encoding: .utf8) ?? "",
            timedOut: !drained
        )
    }
}

private final class LockedProcessData: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func set(_ data: Data) {
        lock.lock()
        storage = data
        lock.unlock()
    }

    var value: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
