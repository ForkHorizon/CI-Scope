import Foundation

struct ActionsRunnerConfig: Identifiable {
    let id: String
    let title: String
    let root: String
    let scope: ActionsRunnerScope
    let requiredLabels: [String]
    let serviceLabel: String?

    var runnerConfigurationPath: String {
        root + "/.runner"
    }
}

enum ActionsRunnerScope {
    case organization(String)
    case personalAccount(String)
    case repository(String)

    var description: String {
        switch self {
        case .organization(let organization):
            "\(organization) organization"
        case .personalAccount(let account):
            "\(account) personal repos"
        case .repository(let slug):
            slug
        }
    }
}

struct DashboardConfig {
    let repositoryOwner = "ForkHorizon"
    let repositoryName = "NexusUnity"
    let repositoryRoot = "/Users/daliys/Daliys/UnityProjects/UnityTestForNexus/Assets/NexusUnity"
    let runnerRoot = "/Users/daliys/actions-runners/forkhorizon-org-ci"
    let runnerServiceLabel = "actions.runner.ForkHorizon.ForkHorizon-MacBook-CI-Scope-Org"
    let runnerStdoutLog = "/Users/daliys/Library/Logs/actions.runner.ForkHorizon.ForkHorizon-MacBook-CI-Scope-Org/stdout.log"
    let runnerStderrLog = "/Users/daliys/Library/Logs/actions.runner.ForkHorizon.ForkHorizon-MacBook-CI-Scope-Org/stderr.log"
    let ollamaURL = URL(string: "http://127.0.0.1:11434")!
    let nexusUnityURL = URL(string: "http://127.0.0.1:8081/")!
    let unityEditorPath = "/Applications/Unity/Hub/Editor/6000.4.3f1/Unity.app/Contents/MacOS/Unity"
    let qualityModel = "qwen3-coder:30b-a3b-q4_K_M"
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

    var repositorySlug: String {
        "\(repositoryOwner)/\(repositoryName)"
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
