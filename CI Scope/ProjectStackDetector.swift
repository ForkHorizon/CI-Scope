import Foundation

/// Recommends the default gate set for a project from its GitHub languages plus
/// a Unity marker file (project layout) or a Unity package manifest (UPM package
/// layout). The Code Linter applies to every stack; the rest are added per
/// detected language.
struct ProjectStackDetector {
    let config: DashboardConfig

    static let universalSeedIDs = ["code-linter", "agent-toolkit"]

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

    /// Agent toolkit choice: the dominant stack profile, whether a stack gate fits at all, and
    /// whether the toolkit is already in the repository (`scripts/check`).
    /// A Rust workspace (or TypeScript only in sub-packages) has no gate, so its manifest keeps just
    /// the universal checks instead of web checks that need a root package.json.
    func stackChoice(for project: CIProject) async -> StackChoice {
        let bytes = await languageBytes(for: project)
        let isUnity = await hasUnityMarker(project) ? true : await isUnityPackage(project)
        let dominant = Self.dominantLanguage(bytes)
        let languages: Set<String> = dominant.map { [$0] } ?? []
        return StackChoice(
            profile: Self.profile(languages: languages, isUnity: isUnity),
            hasStackChecks: Self.hasStackGate(
                languages: languages, isUnity: isUnity, hasRootPackageJSON: await hasRootPackageJSON(project)),
            toolkitInstalled: await hasToolkit(project))
    }

    struct StackChoice {
        let profile: String
        let hasStackChecks: Bool
        let toolkitInstalled: Bool
    }

    /// The stack the repository is mainly written in, by bytes (JavaScript counts as TypeScript).
    /// A few Python bench scripts in a TypeScript repo must not decide the profile.
    static func dominantLanguage(_ bytes: [String: Int]) -> String? {
        let groups = ["swift": "swift", "go": "go", "python": "python", "typescript": "typescript", "javascript": "typescript"]
        var totals: [String: Int] = [:]
        for (language, count) in bytes {
            if let group = groups[language] { totals[group, default: 0] += count }
        }
        return totals.max { $0.value < $1.value }?.key
    }

    private func hasToolkit(_ project: CIProject) async -> Bool {
        let result = await ShellClient.run(
            "gh api repos/\(quoted(project.repositorySlug))/contents/scripts/check --jq '.name'",
            timeout: 30,
            config: config
        )
        return result.exitCode == 0 && !result.output.trimmed.isEmpty
    }

    static func hasStackGate(languages: Set<String>, isUnity: Bool, hasRootPackageJSON: Bool) -> Bool {
        isUnity || !languages.isDisjoint(with: ["swift", "go", "python"])
            || (hasRootPackageJSON && languages.contains("typescript"))
    }

    static func profile(languages: Set<String>, isUnity: Bool) -> String {
        if isUnity { return "unity" }
        if languages.contains("swift") { return "swift" }
        if languages.contains("go") { return "go" }
        if languages.contains("python") { return "python" }
        return "ts-web"
    }

    private func languages(for project: CIProject) async -> Set<String> {
        Set(await languageBytes(for: project).keys)
    }

    /// GitHub language statistics (bytes per lowercased language name).
    private func languageBytes(for project: CIProject) async -> [String: Int] {
        let result = await ShellClient.run(
            "gh api repos/\(quoted(project.repositorySlug))/languages --jq 'to_entries[] | \"\\(.key)\\t\\(.value)\"'",
            timeout: 30,
            config: config
        )
        guard result.exitCode == 0 else { return [:] }
        var bytes: [String: Int] = [:]
        for line in result.output.split(separator: "\n") {
            let parts = line.split(separator: "\t")
            if parts.count == 2, let count = Int(parts[1]) { bytes[String(parts[0]).trimmed.lowercased()] = count }
        }
        return bytes
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
            "gh api -H 'Accept: application/vnd.github.raw+json' repos/\(quoted(project.repositorySlug))/contents/package.json --jq '.unity'",
            timeout: 30,
            config: config
        )
        let value = result.output.trimmed
        return result.exitCode == 0 && !value.isEmpty && value != "null"
    }

    private func hasRootPackageJSON(_ project: CIProject) async -> Bool {
        let result = await ShellClient.run(
            "gh api -H 'Accept: application/vnd.github.raw+json' repos/\(quoted(project.repositorySlug))/contents/package.json --jq '.name'",
            timeout: 30,
            config: config
        )
        let value = result.output.trimmed
        return result.exitCode == 0 && !value.isEmpty && value != "null"
    }

    /// Keep the canonical gate order (Code Linter first) so the
    /// preview and the resulting PR read consistently.
    private func ordered(_ ids: Set<String>) -> [String] {
        AutomationScriptSeedProvider.defaultSeedIDs.filter { ids.contains($0) }
    }
}
