import Foundation

extension AutomationScriptInstaller {
    func diffHasChanges(_ command: String, cwd: URL, step: String) async throws -> Bool {
        let result = await shell(command, cwd: cwd)
        if result.exitCode == 0 { return false }
        if result.exitCode == 1 { return true }
        throw AutomationScriptError.commandFailed(step: step, output: result.output)
    }

    func run(
        _ command: String,
        cwd: URL? = nil,
        timeout: TimeInterval = 30,
        step: String
    ) async throws -> String {
        let result = await shell(command, cwd: cwd, timeout: timeout)
        guard result.exitCode == 0 else {
            throw AutomationScriptError.commandFailed(step: step, output: result.output)
        }
        return result.output
    }

    func shell(_ command: String, cwd: URL? = nil, timeout: TimeInterval = 30) async -> ShellResult {
        await ShellClient.run(command, cwd: cwd?.path, timeout: timeout, config: config)
    }

    func temporaryRoot() throws -> URL {
        try FileManager.default.temporaryDirectory
            .safelyAppendingPathComponent("ci-scope-script-\(UUID().uuidString)", isDirectory: true)
    }

    func gitPaths(_ files: [AutomationScriptFile]) -> String {
        files.map { quoted($0.destinationPath) }.joined(separator: " ")
    }
}
