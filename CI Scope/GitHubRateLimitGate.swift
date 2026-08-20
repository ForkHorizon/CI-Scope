import Foundation

/// Process-wide throttle that pauses GitHub CLI calls after GitHub reports a
/// rate-limit response, so the app stops piling more requests onto an already
/// exhausted quota. Every `gh` polling site should consult `isPaused()` before
/// issuing a request and report its result through `note(result:config:)`.
actor GitHubRateLimitGate {
  static let shared = GitHubRateLimitGate()

  private var pausedUntil: Date?
  private var reason: String?

  /// True while the most recent rate-limit response has not yet reset.
  /// Clears the pause automatically once the reset time has passed.
  func isPaused(now: Date = Date()) -> Bool {
    guard let pausedUntil else { return false }
    if now >= pausedUntil {
      self.pausedUntil = nil
      self.reason = nil
      return false
    }
    return true
  }

  /// The active pause window, if any, for surfacing in the UI.
  func activePause(now: Date = Date()) -> (until: Date, reason: String)? {
    guard let pausedUntil, now < pausedUntil else { return nil }
    return (pausedUntil, reason ?? "GitHub rate limit reached")
  }

  /// Inspect a finished `gh` result and arm the pause when GitHub reports a
  /// rate limit. Safe (and cheap) to call after every `gh` invocation; it is
  /// a no-op for successful or non-rate-limit responses.
  func note(result: ShellResult, config: DashboardConfig) async {
    guard result.exitCode != 0, Self.looksRateLimited(result.output) else { return }

    if Self.isSecondary(result.output) {
      arm(
        until: Date().addingTimeInterval(60),
        reason: "GitHub secondary rate limit — backing off 60s")
      return
    }

    let reset = await Self.coreResetDate(config: config)
    arm(
      until: reset ?? Date().addingTimeInterval(60),
      reason: "GitHub API rate limit exhausted — paused until reset")
  }

  private func arm(until: Date, reason: String) {
    // Never shorten an existing, later pause window.
    if let current = pausedUntil, current > until { return }
    pausedUntil = until
    self.reason = reason
  }

  private static func looksRateLimited(_ output: String) -> Bool {
    let lowered = output.lowercased()
    if lowered.contains("secondary rate limit") { return true }
    return lowered.contains("rate limit") && lowered.contains("exceeded")
  }

  private static func isSecondary(_ output: String) -> Bool {
    output.lowercased().contains("secondary rate limit")
  }

  /// Reads the quota-free `rate_limit` endpoint to learn the exact core reset
  /// time. This endpoint does not count against the rate limit, so it is safe
  /// to call even while throttled.
  private static func coreResetDate(config: DashboardConfig) async -> Date? {
    let result = await ShellClient.run(
      "gh api rate_limit --jq '.resources.core.reset'",
      timeout: 8,
      config: config
    )
    let trimmed = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    guard result.exitCode == 0, let epoch = TimeInterval(trimmed) else { return nil }
    return Date(timeIntervalSince1970: epoch)
  }
}
