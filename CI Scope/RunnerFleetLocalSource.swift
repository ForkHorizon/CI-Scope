import Foundation

extension RunnerFleetService {
    func localLaunchStatus(serviceLabel: String?, title: String) async -> RunnerLaunchStatus {
        guard let serviceLabel else {
            return RunnerLaunchStatus(
                state: .warning,
                launchctlState: "not installed",
                pid: nil,
                uptime: "-",
                error: "Service not installed for \(title)."
            )
        }

        let uid = await ShellClient.run("id -u", timeout: 3, config: config)
            .output
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let launch = await ShellClient.run("launchctl print gui/\(uid)/\(serviceLabel)", timeout: 5, config: config)

        guard launch.exitCode == 0 else {
            return RunnerLaunchStatus(
                state: .offline,
                launchctlState: "unavailable",
                pid: nil,
                uptime: "-",
                error: trimmedError(launch.output, fallback: "launchctl could not read \(title).")
            )
        }

        let launchState = firstMatch(in: launch.output, pattern: #"state = ([a-zA-Z]+)"#) ?? "unknown"
        let pid = intMatch(in: launch.output, pattern: #"pid = ([0-9]+)"#)
        return RunnerLaunchStatus(
            state: launchState == "running" ? .online : .offline,
            launchctlState: launchState,
            pid: pid,
            uptime: await processUptime(pid: pid),
            error: nil
        )
    }

    func serviceLabel(for runnerConfig: ActionsRunnerConfig) -> String? {
        if let serviceLabel = runnerConfig.serviceLabel {
            return serviceLabel
        }

        let servicePath = runnerConfig.root + "/.service"
        guard
            let contents = try? String(contentsOfFile: servicePath, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !contents.isEmpty
        else {
            return nil
        }

        return URL(fileURLWithPath: contents)
            .deletingPathExtension()
            .lastPathComponent
    }

    func readLocalRunner(_ runnerConfig: ActionsRunnerConfig) -> FleetLocalRunnerInfo? {
        guard let runner = readRunnerConfiguration(path: runnerConfig.runnerConfigurationPath) else {
            return nil
        }

        return FleetLocalRunnerInfo(
            config: runnerConfig,
            runner: runner,
            repositorySlug: gitHubSlug(from: runner.gitHubUrl),
            owner: gitHubOwner(from: runner.gitHubUrl)
        )
    }

    func missingLabels(for runnerConfig: ActionsRunnerConfig, remoteRunner: FleetGitHubActionsRunner) -> [String] {
        let availableLabels = Set(remoteRunner.labels.map { $0.name.lowercased() })
        return runnerConfig.requiredLabels.filter { !availableLabels.contains($0.lowercased()) }
    }

    func hasLabels(_ labels: [String], requiredLabels: [String]) -> Bool {
        let availableLabels = Set(labels.map { $0.lowercased() })
        return requiredLabels.allSatisfy { availableLabels.contains($0.lowercased()) }
    }

    func trimmedError(_ output: String, fallback: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    func quoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func readRunnerConfiguration(path: String) -> FleetRunnerConfiguration? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return nil
        }

        let jsonData: Data
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            jsonData = data.dropFirst(3)
        } else {
            jsonData = data
        }

        return try? JSONDecoder().decode(FleetRunnerConfiguration.self, from: jsonData)
    }

    private func gitHubSlug(from value: String?) -> String? {
        guard var value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        if value.hasPrefix("git@github.com:") {
            value = String(value.dropFirst("git@github.com:".count))
        } else if value.hasPrefix("https://github.com/") {
            value = String(value.dropFirst("https://github.com/".count))
        } else if value.hasPrefix("http://github.com/") {
            value = String(value.dropFirst("http://github.com/".count))
        }

        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if value.hasSuffix(".git") {
            value = String(value.dropLast(4))
        }

        let parts = value.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count >= 2 else { return nil }
        return "\(parts[0])/\(parts[1])"
    }

    private func gitHubOwner(from value: String?) -> String? {
        gitHubSlug(from: value)?.split(separator: "/").first.map(String.init)
    }

    private func processUptime(pid: Int?) async -> String {
        guard let pid else { return "-" }
        let result = await ShellClient.run("ps -p \(pid) -o etime= | xargs", timeout: 3, config: config)
        let uptime = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return uptime.isEmpty ? "-" : uptime
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
}
