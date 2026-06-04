import Foundation

@MainActor
extension AutomationScriptStore {
    func migratedLegacyReadabilityScript(_ script: AutomationScript) -> AutomationScript {
        guard script.destinationPathSet == Self.legacyReadabilityDestinationPaths else {
            return script
        }

        var migrated = script
        if migrated.defaultSeedID == nil {
            migrated.defaultSeedID = "ai-readability"
        }
        if migrated.summary == "Checks max source file length and function length for AI-readable code." {
            migrated.summary = "Checks max source file length and function length."
        }
        if migrated.commitMessage == "Add AI readability gate" || migrated.commitMessage == "Add 300-line linter gate" {
            migrated.commitMessage = "Add {{script_title}}"
        }
        if migrated.pullRequestTitle == "Add AI readability gate" || migrated.pullRequestTitle == "Add 300-line linter gate" {
            migrated.pullRequestTitle = "Add {{script_title}}"
        }
        migrated.pullRequestBody = migratedLegacyReadabilityBody(migrated.pullRequestBody)
        migrated.files = migratedLegacyReadabilityFiles(migrated.files)
        return migrated
    }

    private func migratedLegacyReadabilityBody(_ body: String) -> String {
        body
            .replacingOccurrences(
                of: "Adds the portable AI Readability Gate managed by CI Scope.",
                with: "Adds {{script_title}} managed by CI Scope."
            )
            .replacingOccurrences(
                of: "Adds the portable 300-line linter managed by CI Scope.",
                with: "Adds {{script_title}} managed by CI Scope."
            )
            .replacingOccurrences(of: ".github/workflows/ai-readability.yml", with: ".github/workflows/{{script_slug}}.yml")
            .replacingOccurrences(of: ".ai-readability.json", with: ".{{script_slug}}.json")
            .replacingOccurrences(of: "scripts/ai-readability-check.py", with: "scripts/{{script_slug}}.py")
    }

    private func migratedLegacyReadabilityFiles(_ files: [AutomationScriptFile]) -> [AutomationScriptFile] {
        files.map { file in
            var migratedFile = file
            migratedFile.destinationPath = migratedDestinationPath(for: migratedFile.destinationPath)
            migratedFile.contents = migratedLegacyReadabilityContents(migratedFile.contents)
            return migratedFile
        }
    }

    private func migratedLegacyReadabilityContents(_ contents: String) -> String {
        contents
            .replacingOccurrences(of: "name: AI Readability", with: "name: {{script_title}}")
            .replacingOccurrences(of: "name: 300-line linter gate", with: "name: {{script_title}}")
            .replacingOccurrences(of: "name: AI readability gate", with: "name: {{script_title}}")
            .replacingOccurrences(of: "name: Linter Checker 300 Lines", with: "name: {{script_title}}")
            .replacingOccurrences(of: "- name: Run AI readability check", with: "- name: Run {{script_title}}")
            .replacingOccurrences(of: "- name: Run 300-line linter", with: "- name: Run {{script_title}}")
            .replacingOccurrences(
                of: "python3 scripts/ai-readability-check.py", with: "python3 scripts/{{script_slug}}.py --config .{{script_slug}}.json"
            )
            .replacingOccurrences(
                of: "python3 scripts/{{script_slug}}.py --config .{{script_slug}}.json \\\n              --mode",
                with: "python3 scripts/{{script_slug}}.py \\\n              --config .{{script_slug}}.json \\\n              --mode"
            )
            .replacingOccurrences(of: "ai-readability-check.py", with: "{{script_slug}}.py")
    }

    func migratedSwiftQualityGateScript(_ script: AutomationScript) -> AutomationScript {
        let isSwiftQualityGate = script.defaultSeedID == "swift-quality-gate" || script.id == "swift-quality-gate"
        guard isSwiftQualityGate else { return script }

        let hasOldReadabilitySettings = script.variables.contains { variable in
            variable.id == "max_file_lines" || variable.id == "max_function_lines"
        }
        let hasOldReadabilityStage = script.files.contains { file in
            file.contents.contains("--stage readability")
                || file.contents.contains("max_file_lines")
                || file.contents.contains("max_function_lines")
        }
        let hasNonBlockingDeadCodeGate = script.files.contains { file in
            file.destinationPath.normalizedScriptStorePath == "scripts/{{script_slug}}.py"
                && file.contents.contains("periphery")
                && !file.contents.contains("\"--strict\"")
        }
        guard hasOldReadabilitySettings || hasOldReadabilityStage || hasNonBlockingDeadCodeGate else {
            return script
        }

        guard var seed = try? AutomationScriptSeedProvider.loadSeed("swift-quality-gate") else {
            return script
        }
        seed.id = script.id
        return seed
    }

    private func migratedDestinationPath(for path: String) -> String {
        switch path.normalizedScriptStorePath {
        case ".ai-readability.json":
            ".{{script_slug}}.json"
        case ".github/workflows/ai-readability.yml":
            ".github/workflows/{{script_slug}}.yml"
        case "scripts/ai-readability-check.py":
            "scripts/{{script_slug}}.py"
        default:
            path
        }
    }

    private static let legacyReadabilityDestinationPaths: Set<String> = [
        ".ai-readability.json",
        ".github/workflows/ai-readability.yml",
        "scripts/ai-readability-check.py",
    ]
}

extension AutomationScript {
    var destinationPathSet: Set<String> {
        Set(files.map { $0.destinationPath.normalizedScriptStorePath })
    }
}

extension String {
    var normalizedScriptStorePath: String {
        trimmed
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
    }
}
