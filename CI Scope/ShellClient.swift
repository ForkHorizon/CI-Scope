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
    let loggedCommand = redactSecrets(command)
    let start = Date()
    let result: ShellResult = await withCheckedContinuation { continuation in
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
          continuation.resume(
            returning: ShellResult(exitCode: 127, output: error.localizedDescription))
          return
        }

        terminate(process, after: timeout)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        let sanitizedOutput = sanitizeOutput(output)
        continuation.resume(
          returning: ShellResult(exitCode: process.terminationStatus, output: sanitizedOutput))
      }
    }
    logResult(loggedCommand, result, durationMs: Int(Date().timeIntervalSince(start) * 1000))
    return result
  }

  private static func logResult(_ loggedCommand: String, _ result: ShellResult, durationMs: Int) {
    if result.exitCode == 0 {
      AppLogger.shared.debug(
        "shell.run", "\(loggedCommand) -> exit 0",
        context: ["command": loggedCommand, "exitCode": 0, "durationMs": durationMs]
      )
    } else {
      AppLogger.shared.warn(
        "shell.run_failed", "\(loggedCommand) -> exit \(result.exitCode)",
        context: [
          "command": loggedCommand, "exitCode": result.exitCode, "durationMs": durationMs,
          "output": String(result.output.prefix(2000)),
        ]
      )
    }
  }

  /// Best-effort masking so a logged command line never carries a live
  /// token/secret — commands often embed `Authorization: Bearer …` or
  /// `-H "..."` auth headers passed straight to gh/curl.
  private static func redactSecrets(_ command: String) -> String {
    var redacted = command
    for pattern in [
      "(Bearer\\s+)[A-Za-z0-9._-]+",
      "(ghp_|gho_|ghu_|ghs_|ghr_)[A-Za-z0-9]+",
      "([Tt]oken[\"'=:\\s]+)[A-Za-z0-9._-]{8,}",
    ] {
      redacted = redacted.replacingOccurrences(
        of: pattern, with: "$1<redacted>", options: .regularExpression)
    }
    return redacted
  }

  private static func sanitizeOutput(_ output: String) -> String {
    var sanitized = output.replacingOccurrences(
      of: "\u{001B}\\[[0-9;?]*[a-zA-Z]",
      with: "",
      options: .regularExpression
    )
    sanitized = sanitized.replacingOccurrences(
      of: "\u{001B}\\][^\u{0007}\u{001B}]*(?:\u{0007}|\u{001B}\\\\)",
      with: "",
      options: .regularExpression
    )
    sanitized = sanitized.replacingOccurrences(of: "\u{001B}", with: "")
    return sanitized
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
    for (key, value) in environment {
      env[key] = value
    }
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
