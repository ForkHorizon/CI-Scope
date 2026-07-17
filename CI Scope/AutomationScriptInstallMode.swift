import Foundation

enum AutomationScriptInstallMode: String, CaseIterable, Identifiable {
    case localBroker
    case githubHosted

    static let allCases: [AutomationScriptInstallMode] = [.localBroker]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .localBroker: "MacBook Runner"
        case .githubHosted: "GitHub hosted"
        }
    }

    func detail(for script: AutomationScript?) -> String {
        switch self {
        case .localBroker: "Runs jobs on this Mac through the serial broker."
        case .githubHosted:
            if script?.requiresMacGitHubHostedRunner == true {
                "Uses GitHub-hosted macOS runners for Swift/Xcode scripts."
            } else {
                "Uses GitHub-hosted runners for portable scripts."
            }
        }
    }

    func runnerLabels(for script: AutomationScript?) -> [String] {
        switch self {
        case .localBroker: LocalBrokerConstants.runnerLabels
        case .githubHosted:
            script?.requiresMacGitHubHostedRunner == true ? ["macos-latest"] : ["ubuntu-latest"]
        }
    }
}

private extension AutomationScript {
    var requiresMacGitHubHostedRunner: Bool {
        defaultSeedID == "swift-quality-gate" || id == "swift-quality-gate"
    }
}
