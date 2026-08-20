import Foundation

struct DashboardConfig {
  let actionsRunnerRequiredLabels = ["self-hosted", "macos", "arm64", "ci-scope"]

  var actionsRunners: [ActionsRunnerConfig] {
    [
      ActionsRunnerConfig(
        id: "forkhorizon-org",
        title: "ForkHorizon organization sub-runner",
        root: "/Users/daliys/actions-runners/forkhorizon-org-ci",
        scope: .organization("ForkHorizon"),
        requiredLabels: actionsRunnerRequiredLabels,
        serviceLabel: nil
      ),
      ActionsRunnerConfig(
        id: "daliys-personal",
        title: "Daliys private sub-runner",
        root: "/Users/daliys/actions-runner/moodling",
        scope: .personalAccount("Daliys"),
        requiredLabels: actionsRunnerRequiredLabels,
        serviceLabel: nil
      ),
    ]
  }

  var shellPath: String {
    [
      "/opt/homebrew/opt/python@3.14/libexec/bin",
      "/opt/homebrew/bin",
      "/opt/homebrew/sbin",
      "/usr/local/bin",
      "/usr/bin",
      "/bin",
      "/usr/sbin",
      "/sbin",
      "/Library/Apple/usr/bin",
      "/opt/homebrew/opt/openjdk@17/bin",
      "/Users/daliys/.local/bin",
    ].joined(separator: ":")
  }
}
