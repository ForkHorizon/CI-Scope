import Foundation

struct AutomationScriptFile: Identifiable, Codable, Equatable {
    var id: String
    var destinationPath: String
    var isExecutable: Bool
    var contents: String

    static func empty() -> AutomationScriptFile {
        AutomationScriptFile(
            id: UUID().uuidString,
            destinationPath: "scripts/new-script.sh",
            isExecutable: true,
            contents: "#!/usr/bin/env bash\nset -euo pipefail\n"
        )
    }
}

struct AutomationScript: Identifiable, Codable, Equatable {
    var id: String
    var title: String
    var summary: String
    var detail: String
    var runnerLabels: [String]
    var branchName: String
    var commitMessage: String
    var pullRequestTitle: String
    var pullRequestBody: String
    var variables: [AutomationScriptVariable]
    var files: [AutomationScriptFile]
    var defaultSeedID: String?

    static func empty(uniqueID: String) -> AutomationScript {
        AutomationScript(
            id: uniqueID,
            title: "New Script",
            summary: "Custom automation script.",
            detail: "",
            runnerLabels: ["self-hosted", "macOS", "ARM64", "ci-scope"],
            branchName: "ci-scope/install-{{script_id}}",
            commitMessage: "Add {{script_id}} automation",
            pullRequestTitle: "Add {{script_id}} automation",
            pullRequestBody: "Adds {{script_id}} automation managed by CI Scope.",
            variables: [],
            files: [.empty()],
            defaultSeedID: nil
        )
    }
}
