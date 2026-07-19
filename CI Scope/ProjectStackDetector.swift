import Foundation

/// Recommends the default gate set for a project from its GitHub languages plus
/// a Unity marker file. Readability and the advisory slop review apply to every
/// stack; the rest are added per detected language.
struct ProjectStackDetector {
    let config: DashboardConfig

    static let universalSeedIDs = ["ai-readability", "slop-review"]

    func recommendedSeedIDs(for project: CIProject) async -> [String] {
        let languages = await languages(for: project)
        let isUnity = await hasUnityMarker(project)

        var ids = Set(Self.universalSeedIDs)
        if isUnity {
            ids.insert("unity-quality-gate")
        }
        if languages.contains("swift") {
            ids.insert("swift-compile-gate")
            ids.insert("swift-quality-gate")
        }
        // Language stats count bytes anywhere in the repo (e.g. a JS subfolder in a
        // Go backend), which isn't what the gate needs — it runs npm at repo root.
        // A Unity project is also C#/JS-heavy; don't also recommend the web gate.
        if !isUnity, await hasRootPackageJSON(project) {
            ids.insert("web-quality-gate")
        }
        if languages.contains("python") {
            ids.insert("python-quality-gate")
        }
        if languages.contains("go") {
            ids.insert("go-quality-gate")
        }
        return ordered(ids)
    }

    private func languages(for project: CIProject) async -> Set<String> {
        let result = await ShellClient.run(
            "gh api repos/\(quoted(project.repositorySlug))/languages --jq 'keys[]'",
            timeout: 30,
            config: config
        )
        guard result.exitCode == 0 else { return [] }
        return Set(result.output.split(separator: "\n").map { String($0).trimmed.lowercased() }.filter { !$0.isEmpty })
    }

    private func hasUnityMarker(_ project: CIProject) async -> Bool {
        let result = await ShellClient.run(
            "gh api repos/\(quoted(project.repositorySlug))/contents/ProjectSettings/ProjectVersion.txt --jq '.name'",
            timeout: 30,
            config: config
        )
        return result.exitCode == 0 && !result.output.trimmed.isEmpty
    }

    private func hasRootPackageJSON(_ project: CIProject) async -> Bool {
        let result = await ShellClient.run(
            "gh api repos/\(quoted(project.repositorySlug))/contents/package.json --jq '.name'",
            timeout: 30,
            config: config
        )
        return result.exitCode == 0 && !result.output.trimmed.isEmpty
    }

    /// Keep the canonical gate order (readability first, slop review last) so the
    /// preview and the resulting PR read consistently.
    private func ordered(_ ids: Set<String>) -> [String] {
        AutomationScriptSeedProvider.defaultSeedIDs.filter { ids.contains($0) }
    }
}
