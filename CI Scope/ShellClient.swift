import Foundation

struct ShellResult {
    let exitCode: Int32
    let output: String
}

enum ShellClient {
    static func run(
        _ command: String,
        cwd: String? = nil,
        environment: [String: String] = [:],
        timeout: TimeInterval = 20,
        config: DashboardConfig
    ) async -> ShellResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = configuredProcess(
                    command: command,
                    cwd: cwd,
                    environment: environment,
                    config: config
                )
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: ShellResult(exitCode: 127, output: error.localizedDescription))
                    return
                }

                terminate(process, after: timeout)
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: ShellResult(exitCode: process.terminationStatus, output: output))
            }
        }
    }

    private static func configuredProcess(
        command: String,
        cwd: String?,
        environment: [String: String],
        config: DashboardConfig
    ) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-lc", command]
        if let cwd {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = config.shellPath
        environment.forEach { env[$0.key] = $0.value }
        process.environment = env
        return process
    }

    private static func terminate(_ process: Process, after timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.2)
            if process.isRunning {
                process.interrupt()
            }
        }
    }
}
