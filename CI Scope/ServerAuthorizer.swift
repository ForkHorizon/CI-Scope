// Reads the website's secrets over SSH and gates the admin password behind Touch ID.
import Foundation
import LocalAuthentication

enum ServerAuthorizerError: LocalizedError {
    case cancelled
    case serverUnreachable(String)
    case loginUnavailable

    var errorDescription: String? {
        switch self {
        case .cancelled: "Touch ID was cancelled. Nothing was changed."
        case .serverUnreachable(let key):
            "Couldn't read \(key) from \(ServerAuthorizer.host) over SSH. Check the VPS is up and this Mac's SSH key is authorized."
        case .loginUnavailable: "Couldn't read the GitHub login from the gh CLI. Run `gh auth login`."
        }
    }
}

/// Gate for every action that changes something on the website. Secrets are read live from the server's env
/// over SSH (this Mac's key), so a local copy can never go stale. The admin password is fetched only after
/// Touch ID (or the Mac password) succeeds; the app-enforced gate is needed because the ad-hoc-signed app
/// cannot use biometry-bound keychain items (-34018).
enum ServerAuthorizer {
    static let host = "daliys@143.14.22.61"
    static let envFile = "/etc/ci-scope-web/env"

    /// Read-only token for the project config and security event routes; needs no Touch ID.
    static func configReadToken() async throws -> String {
        // Asked once per run: every ask is an ssh to the VPS, and the screens refresh every few seconds.
        if let cached = await ReadTokenCache.shared.value { return cached }
        let token = try await serverValue("CI_SCOPE_CONFIG_READ_TOKEN")
        await ReadTokenCache.shared.store(token)
        return token
    }

    /// Prompts for Touch ID, then returns the admin login (the GitHub login of this Mac's owner) and password.
    static func adminLogin(reason: String) async throws -> (user: String, password: String) {
        let password = try await adminPassword(reason: reason)
        let result = await ShellClient.run("gh api user --jq .login 2>/dev/null", timeout: 20, config: DashboardConfig())
        let login = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.exitCode == 0, !login.isEmpty else { throw ServerAuthorizerError.loginUnavailable }
        return (login, password)
    }

    private static func adminPassword(reason: String) async throws -> String {
        let context = LAContext()
        context.touchIDAuthenticationAllowableReuseDuration = 60
        do {
            guard try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) else {
                throw ServerAuthorizerError.cancelled
            }
        } catch let error as LAError where error.code == .userCancel || error.code == .appCancel {
            throw ServerAuthorizerError.cancelled
        }
        return try await serverValue("CI_SCOPE_ADMIN_PASSWORD")
    }

    private static func serverValue(_ key: String) async throws -> String {
        let remote = "sudo -n grep '^\(key)=' \(envFile) | cut -d= -f2-"
        // stderr dropped: ShellClient merges it into output, and an ssh warning would corrupt the value.
        let command = "ssh -o BatchMode=yes -o ConnectTimeout=10 \(quoted(host)) \(quoted(remote)) 2>/dev/null"
        var result = await ShellClient.run(command, timeout: 20, config: DashboardConfig())
        for attempt in 1..<3 where result.exitCode != 0 {  // flaky network: two more tries
            try await Task.sleep(for: .seconds(2 * attempt))
            result = await ShellClient.run(command, timeout: 20, config: DashboardConfig())
        }
        // Only the one trailing newline from `cut`; the value itself may contain spaces or symbols.
        let value = result.output.hasSuffix("\n") ? String(result.output.dropLast()) : result.output
        guard result.exitCode == 0, !value.isEmpty, !value.contains("\n") else {
            throw ServerAuthorizerError.serverUnreachable(key)
        }
        return value
    }
}

/// Older tests and callers refer to the authorizer by its former name.
typealias PolicyAuthorizerError = ServerAuthorizerError

private actor ReadTokenCache {
    static let shared = ReadTokenCache()
    private(set) var value: String?
    func store(_ token: String) { value = token }
}
