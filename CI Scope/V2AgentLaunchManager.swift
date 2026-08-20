import Foundation
import Security

struct V2AgentLaunchManager {
    static let serviceLabel = "com.forkhorizon.ci-scope.agent"
    static let legacyServiceLabel = "com.ci-scope.local-mac-broker"

    let config: DashboardConfig
    private let fileManager = FileManager.default

    init(config: DashboardConfig = DashboardConfig()) {
        self.config = config
    }

    var launchAgentURL: URL {
        try! fileManager.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .safelyAppendingPathComponent("LaunchAgents/\(Self.serviceLabel).plist")
    }

    var stateRootURL: URL {
        try! fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .safelyAppendingPathComponent("CI-Scope", isDirectory: true)
    }

    var logDirURL: URL {
        try! fileManager.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .safelyAppendingPathComponent("Logs/CI-Scope", isDirectory: true)
    }

    func installOrUpdateLaunchAgent() async throws -> String {
        try ensureDirectories()
        await stopLegacyBroker()

        let agentExecutableURL = try findAgentExecutable()
        let settings = CIQueueSettingsStore.snapshot()
        let controlPlaneURL = settings.serverURL.isEmpty ? "https://ci.forkhorizon.com" : settings.serverURL
        let machineID = settings.machineID.isEmpty ? (Host.current().localizedName ?? "macbook") : settings.machineID
        let credentialID = "machine-credential"

        let plistContent = renderAgentPlist(
            agentPath: agentExecutableURL.path,
            controlPlaneURL: controlPlaneURL,
            machineID: machineID,
            credentialID: credentialID
        )

        let existing = try? String(contentsOf: launchAgentURL, encoding: .utf8)
        let changed = existing != plistContent
        try plistContent.write(to: launchAgentURL, atomically: true, encoding: .utf8)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: launchAgentURL.path)

        let uid = geteuid()
        if changed {
            _ = await ShellClient.run("launchctl bootout gui/\(uid)/\(Self.serviceLabel) >/dev/null 2>&1 || true", timeout: 8, config: config)
        }

        let isLoaded = await launchAgentIsLoaded()
        if changed || !isLoaded {
            let result = await ShellClient.run(
                "launchctl bootstrap gui/\(uid) \(quoted(launchAgentURL.path))",
                timeout: 10,
                config: config
            )
            if result.exitCode != 0, !result.output.contains("Bootstrap failed: 5") {
                throw V2AgentLaunchError.launchAgent(result.output.trimmed)
            }
        }

        _ = await ShellClient.run("launchctl kickstart -k gui/\(uid)/\(Self.serviceLabel) >/dev/null 2>&1 || true", timeout: 8, config: config)
        return agentExecutableURL.path
    }

    func stopLegacyBroker() async {
        let uid = geteuid()
        _ = await ShellClient.run("launchctl bootout gui/\(uid)/\(Self.legacyServiceLabel) >/dev/null 2>&1 || true", timeout: 5, config: config)
    }

    func launchStatus() async -> RunnerLaunchStatus {
        let uid = geteuid()
        let result = await ShellClient.run(
            "launchctl print gui/\(uid)/\(Self.serviceLabel)",
            timeout: 5,
            config: config
        )
        guard result.exitCode == 0 else {
            return RunnerLaunchStatus(
                state: .offline,
                launchctlState: "not running",
                pid: nil,
                uptime: "-"
            )
        }

        let launchState = firstMatch(in: result.output, pattern: #"state = ([a-zA-Z]+)"#) ?? "running"
        let pid = intMatch(in: result.output, pattern: #"pid = ([0-9]+)"#)
        return RunnerLaunchStatus(
            state: launchState == "running" ? .online : .warning,
            launchctlState: launchState,
            pid: pid,
            uptime: await processUptime(pid: pid)
        )
    }

    private func launchAgentIsLoaded() async -> Bool {
        let result = await ShellClient.run(
            "launchctl print gui/\(geteuid())/\(Self.serviceLabel)",
            timeout: 5,
            config: config
        )
        return result.exitCode == 0
    }

    private func ensureDirectories() throws {
        try fileManager.createDirectory(at: launchAgentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: stateRootURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: logDirURL, withIntermediateDirectories: true)
        try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: stateRootURL.path)
        try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: logDirURL.path)
    }

    private func findAgentExecutable() throws -> URL {
        if let bundleAgent = Bundle.main.url(forResource: "ci-scope-agent", withExtension: nil) {
            return bundleAgent
        }

        let standardLocations = [
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("ci-scope-agent"),
            URL(fileURLWithPath: "/usr/local/bin/ci-scope-agent"),
            URL(fileURLWithPath: "/opt/homebrew/bin/ci-scope-agent"),
            stateRootURL.appendingPathComponent("bin/ci-scope-agent")
        ]

        for url in standardLocations where fileManager.isExecutableFile(atPath: url.path) {
            return url
        }

        let devPath = URL(fileURLWithPath: "/Users/daliys/Daliys/Swift/CI Scope/agent/ci-scope-agent")
        if fileManager.isExecutableFile(atPath: devPath.path) {
            return devPath
        }

        throw V2AgentLaunchError.missingExecutable
    }

    private func renderAgentPlist(
        agentPath: String,
        controlPlaneURL: String,
        machineID: String,
        credentialID: String
    ) -> String {
        let stdoutPath = logDirURL.appendingPathComponent("agent.log").path
        let stderrPath = logDirURL.appendingPathComponent("agent.err.log").path
        let envXml = agentEnvironmentXML(
            controlPlaneURL: controlPlaneURL,
            machineID: machineID,
            credentialID: credentialID
        )

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(Self.serviceLabel)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(agentPath)</string>
                <string>run</string>
            </array>
            <key>EnvironmentVariables</key>
            <dict>
        \(envXml)
            </dict>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <dict>
                <key>SuccessfulExit</key>
                <false/>
            </dict>
            <key>StandardOutPath</key>
            <string>\(stdoutPath)</string>
            <key>StandardErrorPath</key>
            <string>\(stderrPath)</string>
        </dict>
        </plist>
        """
    }

    private func agentEnvironmentXML(
        controlPlaneURL: String,
        machineID: String,
        credentialID: String
    ) -> String {
        let socketPath = stateRootURL.appendingPathComponent("agent.sock").path
        let bootID = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        let env: [(String, String)] = [
            ("CI_SCOPE_CONTROL_PLANE_URL", controlPlaneURL),
            ("CI_SCOPE_MACHINE_ID", machineID),
            ("CI_SCOPE_BOOT_ID", bootID),
            ("CI_SCOPE_AGENT_INSTANCE_ID", UUID().uuidString.lowercased()),
            ("CI_SCOPE_CREDENTIAL_ID", credentialID),
            ("CI_SCOPE_POOL_IDENTITY", "forkhorizon-production"),
            ("CI_SCOPE_SESSION_REQUEST_ID", UUID().uuidString.lowercased()),
            ("CI_SCOPE_SOCKET_PATH", socketPath),
            ("CI_SCOPE_STATE_ROOT", stateRootURL.path),
            ("CI_SCOPE_LOG_DIR", logDirURL.path),
            ("CI_SCOPE_KEYCHAIN_SERVICE", "com.forkhorizon.ci-scope.agent"),
            ("CI_SCOPE_V2_SHADOW_TOKEN_KEYCHAIN_ACCOUNT", "shadow-token")
        ]
        return env.map { "        <key>\($0.0)</key>\n        <string>\($0.1)</string>" }.joined(separator: "\n")
    }

    private func processUptime(pid: Int?) async -> String {
        guard let pid else { return "-" }
        let result = await ShellClient.run("ps -p \(pid) -o etime= | xargs", timeout: 3, config: config)
        let uptime = result.output.trimmed
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

enum V2AgentLaunchError: LocalizedError {
    case missingExecutable
    case launchAgent(String)

    var errorDescription: String? {
        switch self {
        case .missingExecutable:
            return "Could not locate ci-scope-agent binary. Build or package the Go Agent first."
        case .launchAgent(let message):
            return "LaunchAgent error: \(message)"
        }
    }
}
