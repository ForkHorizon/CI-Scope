import Foundation

struct UnifiedCheckResult: Decodable, Equatable, Identifiable {
    let id: String
    let type: String?
    let status: String
    let required: Bool?
    let durationMs: Int?
    let detail: String?
    let reason: String?
    let log: String?

    private enum CodingKeys: String, CodingKey {
        case id, type, status, required, detail, reason, log
        case durationMs = "duration_ms"
    }
}

struct UnifiedChecksReport: Decodable, Equatable {
    let version: Int
    let status: String
    let head: String?
    let run: RunIdentity
    let checks: [UnifiedCheckResult]
    let timings: Timings?

    struct RunIdentity: Decodable, Equatable {
        let repository: String?
        let runId: String?
        let attempt: String?
        let checkedSha: String?

        private enum CodingKeys: String, CodingKey {
            case repository, attempt
            case runId = "run_id"
            case checkedSha = "checked_sha"
        }
    }

    struct Timings: Decodable, Equatable {
        let ordinaryMs: Int
        let aiMs: Int

        private enum CodingKeys: String, CodingKey {
            case ordinaryMs = "ordinary_ms"
            case aiMs = "ai_ms"
        }
    }

    static func decode(_ data: Data, project: CIProject, run githubRun: GitHubRun) throws -> Self {
        guard data.count <= 65_536 else { throw UnifiedChecksError.reportTooLarge }
        let report = try JSONDecoder().decode(Self.self, from: data)
        guard report.version == 1 else { throw UnifiedChecksError.unsupportedReportVersion }
        guard let repository = report.run.repository,
            let reportAttempt = report.run.attempt.flatMap(Int.init),
            let githubAttempt = githubRun.attempt,
            let reportSHA = report.run.checkedSha,
            let githubSHA = githubRun.headSha,
            repository.caseInsensitiveCompare(project.repositorySlug) == .orderedSame,
            report.run.runId == String(githubRun.databaseId),
            reportAttempt == githubAttempt,
            reportSHA == githubSHA || report.head == githubSHA
        else { throw UnifiedChecksError.reportIdentityMismatch }
        return report
    }
}
