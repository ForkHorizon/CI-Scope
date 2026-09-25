import Foundation
import LocalAuthentication

enum PolicyAuthorizerError: LocalizedError {
    case cancelled
    case serverUnreachable(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: "Touch ID was cancelled. Nothing was changed."
        case .serverUnreachable(let key):
            "Couldn't read \(key) from \(PolicyAuthorizer.host) over SSH. Check the VPS is up and this Mac's SSH key is authorized."
        }
    }
}

/// Gate for every dangerous policy action. Secrets are read live from the server's env
/// over SSH (this Mac's key), so a local copy can never go stale. The admin password is
/// fetched only after Touch ID (or the Mac password) succeeds. ponytail: app-enforced
/// gate, since the ad-hoc-signed app can't use biometry-bound keychain items (-34018).
enum PolicyAuthorizer {
    static let host = "daliys@143.14.22.61"
    static let envFile = "/etc/ci-scope-web/env"

    /// Read-only token for GET /api/ci/policy; status views use it without Touch ID.
    static func readToken() async throws -> String {
        try await serverValue("CI_SCOPE_POLICY_READ_TOKEN")
    }

    /// Prompts for Touch ID, then returns the admin password.
    static func adminPassword(reason: String) async throws -> String {
        let context = LAContext()
        context.touchIDAuthenticationAllowableReuseDuration = 60
        do {
            guard try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) else {
                throw PolicyAuthorizerError.cancelled
            }
        } catch let error as LAError where error.code == .userCancel || error.code == .appCancel {
            throw PolicyAuthorizerError.cancelled
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
            throw PolicyAuthorizerError.serverUnreachable(key)
        }
        return value
    }
}
