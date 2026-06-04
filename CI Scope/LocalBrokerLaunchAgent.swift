import Foundation

extension LocalBrokerService {
    func installOrUpdateLaunchAgent() async throws -> String {
        try ensureDirectories()
        let executableURL = try installBrokerExecutable()
        let plist = launchAgentPlist(executableURL: executableURL)
        try fileManager.createDirectory(
            at: launchAgentURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let existing = try? String(contentsOf: launchAgentURL, encoding: .utf8)
        let changed = existing != plist
        try plist.write(to: launchAgentURL, atomically: true, encoding: .utf8)

        if changed {
            _ = await ShellClient.run(bootoutCommand, timeout: 8, config: config)
        }

        let isLoaded = await launchAgentIsLoaded()
        if changed || !isLoaded {
            let result = await ShellClient.run(
                "launchctl bootstrap gui/$(id -u) \(quoted(launchAgentURL.path))",
                timeout: 10,
                config: config
            )
            if result.exitCode != 0, !result.output.contains("Bootstrap failed: 5") {
                throw LocalBrokerError.launchAgent(result.output.trimmed)
            }
        }

        _ = await ShellClient.run(kickstartCommand, timeout: 8, config: config)
        return executableURL.path
    }

    private func installBrokerExecutable() throws -> URL {
        guard let sourceURL = brokerResourceURL else {
            throw LocalBrokerError.missingResource
        }
        let destinationURL = try! brokerDirectory.safelyAppendingPathComponent("CI Scope Broker")
        if (try? Data(contentsOf: sourceURL)) != (try? Data(contentsOf: destinationURL)) {
            try? fileManager.removeItem(at: destinationURL)
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        }
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destinationURL.path)
        return destinationURL
    }

    private var brokerResourceURL: URL? {
        Bundle.main.url(forResource: "CI Scope Broker", withExtension: nil, subdirectory: "Broker")
            ?? Bundle.main.url(forResource: "CI Scope Broker", withExtension: nil)
    }

    private var launchAgentURL: URL {
        try! fileManager.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .safelyAppendingPathComponent("LaunchAgents/\(LocalBrokerConstants.serviceLabel).plist")
    }

    private func launchAgentIsLoaded() async -> Bool {
        let result = await ShellClient.run(
            "launchctl print gui/$(id -u)/\(LocalBrokerConstants.serviceLabel)",
            timeout: 4,
            config: config
        )
        return result.exitCode == 0
    }

    private var bootoutCommand: String {
        "launchctl bootout gui/$(id -u)/\(LocalBrokerConstants.serviceLabel) >/dev/null 2>&1 || true"
    }

    private var kickstartCommand: String {
        "launchctl kickstart -k gui/$(id -u)/\(LocalBrokerConstants.serviceLabel) >/dev/null 2>&1 || true"
    }

    private func launchAgentPlist(executableURL: URL) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>\(LocalBrokerConstants.serviceLabel)</string>
          <key>ProgramArguments</key>
          <array>
            <string>\(executableURL.path)</string>
          </array>
          <key>RunAtLoad</key>
          <true/>
          <key>KeepAlive</key>
          <true/>
          <key>EnvironmentVariables</key>
          <dict>
            <key>PATH</key>
            <string>\(config.shellPath)</string>
          </dict>
          <key>StandardOutPath</key>
          <string>\(try! logsDirectory.safelyAppendingPathComponent("broker.out.log").path)</string>
          <key>StandardErrorPath</key>
          <string>\(try! logsDirectory.safelyAppendingPathComponent("broker.err.log").path)</string>
        </dict>
        </plist>
        """
    }
}

enum LocalBrokerError: LocalizedError {
    case missingResource
    case launchAgent(String)
    case invalidRepository(String)

    var errorDescription: String? {
        switch self {
        case .missingResource:
            "CI Scope Broker helper was not found in the app bundle."
        case .launchAgent(let output):
            output.isEmpty ? "Could not start Local Mac Broker." : output
        case .invalidRepository(let detail):
            detail
        }
    }
}
