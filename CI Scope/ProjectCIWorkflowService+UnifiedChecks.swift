import Foundation

private struct GitHubArtifact: Decodable {
    let name: String
    let expired: Bool
}

private struct GitHubArtifactList: Decodable {
    let artifacts: [GitHubArtifact]
}

/// The `.ci-scope.json` / `CI Scope / Checks` result lookup for the coverage
/// panel. Split into one function per phase (find run, resolve artifact,
/// decode report) so each stays under the linter's function-length limit and
/// each early-exit state (missing/pending/expired/invalid) reads at its own
/// call site instead of being buried in one long guard chain.
extension ProjectCIService {
    func loadUnifiedManifest(for project: CIProject) async -> LoadResponse<CIScopeManifest> {
        let command = """
            gh api --cache 30s -H 'Accept: application/vnd.github.raw+json' \(quoted("repos/\(project.repositorySlug)/contents/.ci-scope.json"))
            """
        let result = await ShellClient.run(command, timeout: 15, config: config)
        if result.exitCode != 0 {
            if result.output.contains("HTTP 404") || result.output.contains("Not Found") {
                return LoadResponse()
            }
            return LoadResponse(error: "Unable to read .ci-scope.json.")
        }
        guard let data = result.output.data(using: .utf8) else {
            return LoadResponse(error: "Unable to decode .ci-scope.json.")
        }
        do {
            return LoadResponse(value: try CIScopeManifest.decode(data))
        } catch {
            return LoadResponse(error: error.localizedDescription)
        }
    }

    func loadUnifiedChecks(
        for project: CIProject, manifest: CIScopeManifest, runs: [GitHubRun]
    ) async -> UnifiedChecksSnapshot {
        guard let run = runs.first(where: isUnifiedChecksRun) else {
            return UnifiedChecksSnapshot(manifest: manifest, run: nil, report: nil, artifact: .missing)
        }
        guard run.status == "completed" else {
            return UnifiedChecksSnapshot(manifest: manifest, run: run, report: nil, artifact: .pending)
        }

        guard let artifact = await resolvedUnifiedChecksArtifact(for: project, run: run) else {
            return UnifiedChecksSnapshot(manifest: manifest, run: run, report: nil, artifact: .missing)
        }
        guard !artifact.expired else {
            return UnifiedChecksSnapshot(manifest: manifest, run: run, report: nil, artifact: .expired)
        }

        return await downloadedUnifiedChecksReport(
            for: project, run: run, manifest: manifest, artifact: artifact)
    }

    private func isUnifiedChecksRun(_ run: GitHubRun) -> Bool {
        run.workflowName == "CI Scope" || run.workflowName == "CI Scope / Checks"
    }

    private func resolvedUnifiedChecksArtifact(
        for project: CIProject, run: GitHubRun
    ) async -> GitHubArtifact? {
        let command = """
            gh api --cache 30s \(quoted("repos/\(project.repositorySlug)/actions/runs/\(run.databaseId)/artifacts"))
            """
        let result = await ShellClient.run(command, timeout: 15, config: config)
        guard result.exitCode == 0,
            let data = result.output.data(using: .utf8),
            let list = try? JSONDecoder().decode(GitHubArtifactList.self, from: data)
        else { return nil }
        return list.artifacts.first(where: { $0.name.hasPrefix("ci-scope-") })
    }

    private func downloadedUnifiedChecksReport(
        for project: CIProject, run: GitHubRun, manifest: CIScopeManifest, artifact: GitHubArtifact
    ) async -> UnifiedChecksSnapshot {
        let downloadCommand = """
            tmp=$(mktemp -d)
            cleanup() { rm -rf "$tmp"; }
            trap cleanup EXIT
            gh run download \(run.databaseId) --repo \(quoted(project.repositorySlug)) --name \(quoted(artifact.name)) --dir "$tmp" >/dev/null
            report_file=$(find "$tmp" -type f -name result.json -print -quit)
            if [[ -n "$report_file" ]]; then head -c 65537 "$report_file"; fi
            """
        let download = await ShellClient.run(downloadCommand, timeout: 30, config: config)
        guard download.exitCode == 0, let reportData = download.output.data(using: .utf8),
            !reportData.isEmpty
        else {
            return UnifiedChecksSnapshot(
                manifest: manifest, run: run, report: nil,
                artifact: .invalid("result.json is unavailable"))
        }
        do {
            let report = try UnifiedChecksReport.decode(reportData, project: project, run: run)
            guard Set(report.checks.map(\.id)) == Set(manifest.checks.map(\.id)),
                report.checks.count == manifest.checks.count
            else {
                return UnifiedChecksSnapshot(
                    manifest: manifest, run: run, report: nil,
                    artifact: .invalid("result.json checks do not match .ci-scope.json"))
            }
            return UnifiedChecksSnapshot(
                manifest: manifest, run: run, report: report, artifact: .available(name: artifact.name))
        } catch {
            return UnifiedChecksSnapshot(
                manifest: manifest, run: run, report: nil,
                artifact: .invalid(error.localizedDescription))
        }
    }
}
