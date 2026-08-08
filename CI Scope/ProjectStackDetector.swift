import Foundation

/// Recommends the default gate set for a project from its GitHub languages plus
/// a Unity marker file (project layout) or a Unity package manifest (UPM package
/// layout). The Code Linter and the advisory slop review apply to every stack; the
/// rest are added per detected language.
struct ProjectStackDetector {
    let config: DashboardConfig

    static let universalSeedIDs = ["code-linter", "slop-review"]

    func recommendedSeedIDs(for project: CIProject) async -> [String] {
        let languages = await languages(for: project)
        let isUnity = await hasUnityMarker(project) ? true : await isUnityPackage(project)

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

    /// A distributable Unity package (UPM) repo has no Assets/ProjectSettings —
    /// hasUnityMarker() misses it entirely — but its root package.json is a Unity
    /// manifest carrying a top-level "unity" version field that npm's never has.
    private func isUnityPackage(_ project: CIProject) async -> Bool {
        let result = await ShellClient.run(
            "gh api repos/\(quoted(project.repositorySlug))/contents/package.json --jq '.unity'",
            timeout: 30,
            config: config
        )
        let value = result.output.trimmed
        return result.exitCode == 0 && !value.isEmpty && value != "null"
    }

    private func hasRootPackageJSON(_ project: CIProject) async -> Bool {
        let result = await ShellClient.run(
            "gh api repos/\(quoted(project.repositorySlug))/contents/package.json --jq '.name'",
            timeout: 30,
            config: config
        )
        return result.exitCode == 0 && !result.output.trimmed.isEmpty
    }

    /// Keep the canonical gate order (Code Linter first, slop review last) so the
    /// preview and the resulting PR read consistently.
    private func ordered(_ ids: Set<String>) -> [String] {
        AutomationScriptSeedProvider.defaultSeedIDs.filter { ids.contains($0) }
    }
}
