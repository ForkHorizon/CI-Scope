import Foundation

struct DashboardService {
    let config: DashboardConfig

    func loadSnapshot() async -> DashboardSnapshot {
        async let runner = loadRunnerStatus()
        async let runs = loadGitHubRuns()
        async let ollama = loadOllamaStatus()
        async let nexus = loadNexusUnityStatus()
        async let logs = loadLogs()
        async let stages = loadScriptStages()

        var snapshot = DashboardSnapshot()
        snapshot.runner = await runner
        snapshot.runs = await runs
        snapshot.ollama = await ollama
        snapshot.nexusUnity = await nexus
        snapshot.logs = await logs
        snapshot.stages = await stages
        snapshot.refreshedAt = Date()

        if let error = snapshot.runner.error { snapshot.errors.append("Runner: \(error)") }
        if let error = snapshot.ollama.error { snapshot.errors.append("Ollama: \(error)") }
        if let error = snapshot.nexusUnity.error { snapshot.errors.append("Nexus Unity: \(error)") }
        return snapshot
    }

    func loadRunnerStatus() async -> RunnerStatus {
        let uid = await ShellClient.run("id -u", timeout: 3, config: config)
            .output
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let label = config.runnerServiceLabel
        let launch = await ShellClient.run("launchctl print gui/\(uid)/\(label)", timeout: 5, config: config)

        var status = RunnerStatus()
        if launch.exitCode != 0 {
            status.state = .offline
            status.error = launch.output.trimmingCharacters(in: .whitespacesAndNewlines)
            return status
        }

        status.launchctlState = firstMatch(in: launch.output, pattern: #"state = ([a-zA-Z]+)"#) ?? "unknown"
        status.servicePID = intMatch(in: launch.output, pattern: #"pid = ([0-9]+)"#)
        status.state = status.launchctlState == "running" ? .online : .offline

        let process = await ShellClient.run(
            "ps aux | rg 'NexusUnity-DO-NOT-QUIT-Ollama-AI-Docs-GitHub-Runner-Listener' | rg -v rg",
            timeout: 5,
            config: config
        )
        status.listenerPID = firstProcessPID(from: process.output)
        status.uptime = await processUptime(pid: status.listenerPID ?? status.servicePID)
        status.lastLine = await lastNonEmptyLine(path: config.runnerStdoutLog) ?? "Runner stdout is empty."
        return status
    }

    func loadGitHubRuns() async -> [GitHubRun] {
        let command = """
            gh run list --repo \(quoted(config.repositorySlug)) --limit 20 --json databaseId,status,conclusion,displayTitle,workflowName,headBranch,event,createdAt,updatedAt,url
            """
        let result = await ShellClient.run(command, cwd: config.repositoryRoot, timeout: 15, config: config)
        guard result.exitCode == 0, let data = result.output.data(using: .utf8) else {
            return []
        }

        return (try? JSONDecoder().decode([GitHubRun].self, from: data)) ?? []
    }

    func loadOllamaStatus() async -> OllamaStatus {
        var status = OllamaStatus()

        do {
            let psData = try await getJSON(path: "/api/ps", baseURL: config.ollamaURL)
            let ps = try JSONDecoder().decode(OllamaPsResponse.self, from: psData)
            status.loadedModels = ps.models

            let tagsData = try await getJSON(path: "/api/tags", baseURL: config.ollamaURL)
            let tags = try JSONDecoder().decode(OllamaTagsResponse.self, from: tagsData)
            status.availableModels = tags.models
            status.state = .online
        } catch {
            status.state = .offline
            status.error = error.localizedDescription
        }

        return status
    }

    func loadNexusUnityStatus() async -> NexusUnitySnapshot {
        var snapshot = NexusUnitySnapshot()
        do {
            let payload = #"{"jsonrpc":"2.0","method":"get_server_status","params":{},"id":1}"#
            let command =
                "curl -fsS -H 'Content-Type: application/json' --data \(quoted(payload)) \(quoted(config.nexusUnityURL.absoluteString))"
            let result = await ShellClient.run(command, timeout: 8, config: config)
            guard result.exitCode == 0, let data = result.output.data(using: .utf8) else {
                throw DashboardServiceError.commandFailed(result.output)
            }

            let decoded = try JSONDecoder().decode(JSONRPCResponse<NexusUnityStatus>.self, from: data)
            if let error = decoded.error {
                snapshot.state = .warning
                snapshot.error = error.message ?? "JSON-RPC error \(error.code ?? 0)"
                return snapshot
            }

            snapshot.status = decoded.result
            if decoded.result?.serverAlive == true, decoded.result?.state == "Running" {
                snapshot.state = .online
            } else {
                snapshot.state = .warning
            }
        } catch {
            snapshot.state = .offline
            snapshot.error = error.localizedDescription
        }

        return snapshot
    }

    func loadLogs() async -> LogSnapshot {
        async let stdout = tail(path: config.runnerStdoutLog, lines: 120)
        async let stderr = tail(path: config.runnerStderrLog, lines: 80)
        async let runnerDiag = latestDiag(prefix: "Runner_", lines: 140)
        async let workerDiag = latestDiag(prefix: "Worker_", lines: 180)

        let runnerDiagResult = await runnerDiag
        let workerDiagResult = await workerDiag
        return LogSnapshot(
            stdoutTail: await stdout,
            stderrTail: await stderr,
            latestRunnerDiagTail: runnerDiagResult.tail,
            latestWorkerDiagTail: workerDiagResult.tail,
            latestRunnerDiagName: runnerDiagResult.name,
            latestWorkerDiagName: workerDiagResult.name,
            stdoutPath: config.runnerStdoutLog,
            stderrPath: config.runnerStderrLog,
            latestRunnerDiagPath: runnerDiagResult.path,
            latestWorkerDiagPath: workerDiagResult.path
        )
    }

    func loadScriptStages() async -> [ScriptStage] {
        let workflowPath = config.repositoryRoot + "/.github/workflows/validate.yml"
        let scriptPath = config.repositoryRoot + "/scripts/prepush-validate.sh"
        var stages: [ScriptStage] = []

        if let workflow = try? String(contentsOfFile: workflowPath, encoding: .utf8) {
            stages.append(contentsOf: parseWorkflow(workflow, sourcePath: workflowPath))
        }

        if let script = try? String(contentsOfFile: scriptPath, encoding: .utf8) {
            stages.append(contentsOf: parseValidationScript(script, sourcePath: scriptPath))
        }

        return stages
    }

    private func getJSON(path: String, baseURL: URL) async throws -> Data {
        let base =
            baseURL.absoluteString.hasSuffix("/")
            ? String(baseURL.absoluteString.dropLast())
            : baseURL.absoluteString
        let result = await ShellClient.run("curl -fsS \(quoted(base + path))", timeout: 8, config: config)
        guard result.exitCode == 0, let data = result.output.data(using: .utf8) else {
            throw DashboardServiceError.commandFailed(result.output)
        }
        return data
    }

    private func tail(path: String, lines: Int) async -> String {
        let result = await ShellClient.run(
            "test -f \(quoted(path)) && tail -n \(lines) \(quoted(path)) || true", timeout: 5, config: config)
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func latestDiag(prefix: String, lines: Int) async -> (name: String, tail: String, path: String?) {
        let command = """
            file=$(find \(quoted(config.runnerRoot + "/_diag")) -maxdepth 1 -type f -name '\(prefix)*.log' -print | sort | tail -n 1)
            if [ -n "$file" ]; then
              printf '%s\\n' "$file"
              printf '\\n---\\n'
              basename "$file"
              printf '\\n---\\n'
              tail -n \(lines) "$file"
            fi
            """
        let result = await ShellClient.run(command, timeout: 5, config: config)
        let parts = result.output.components(separatedBy: "\n---\n")
        let path = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = parts.dropFirst().first?.trimmingCharacters(in: .whitespacesAndNewlines)
        let tail = parts.dropFirst(2).joined(separator: "\n---\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (name?.isEmpty == false ? name! : "\(prefix)diag", tail, path?.isEmpty == false ? path : nil)
    }

    private func processUptime(pid: Int?) async -> String {
        guard let pid else { return "-" }
        let result = await ShellClient.run("ps -p \(pid) -o etime= | xargs", timeout: 3, config: config)
        let uptime = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return uptime.isEmpty ? "-" : uptime
    }

    private func lastNonEmptyLine(path: String) async -> String? {
        let result = await ShellClient.run(
            "test -f \(quoted(path)) && awk 'NF { line=$0 } END { print line }' \(quoted(path)) || true", timeout: 3,
            config: config)
        let value = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func firstProcessPID(from psOutput: String) -> Int? {
        let first = psOutput.components(separatedBy: .newlines).first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let pid = first?.split(separator: " ").dropFirst().first
        return pid.flatMap { Int($0) }
    }

    private func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1 else { return nil }
        guard let valueRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[valueRange])
    }

    private func intMatch(in text: String, pattern: String) -> Int? {
        firstMatch(in: text, pattern: pattern).flatMap(Int.init)
    }

    private func quoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
