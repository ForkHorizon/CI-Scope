import Foundation

struct GitHubWorkflow: Identifiable, Decodable {
    let id: String
    let name: String
    let path: String?
    let state: String

    init(id: String, name: String, path: String?, state: String) {
        self.id = id
        self.name = name
        self.path = path
        self.state = state
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let intID = try? container.decode(Int.self, forKey: .id) {
            id = String(intID)
        } else {
            id = try container.decode(String.self, forKey: .id)
        }
        name = try container.decode(String.self, forKey: .name)
        path = try container.decodeIfPresent(String.self, forKey: .path)
        state = try container.decode(String.self, forKey: .state)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case path
        case state
    }
}

struct ProjectCISnapshot {
    var state: ServiceState = .unknown
    var localRunner = ProjectLocalRunnerStatus()
    var v2Status: V2ClientStatusProjection?
    var v2StatusError: String?
    var workflows: [GitHubWorkflow] = []
    var runs: [GitHubRun] = []
    var unifiedChecks: UnifiedChecksSnapshot?
    var unifiedChecksError: String?
    var error: String?
    var refreshedAt = Date()
}

struct CIScopeManifest: Decodable, Equatable {
    let version: Int
    let checks: [CIScopeManifestCheck]

    static func decode(_ data: Data) throws -> Self {
        let manifest = try JSONDecoder().decode(Self.self, from: data)
        guard manifest.version == 1 else { throw UnifiedChecksError.unsupportedManifestVersion }
        guard !manifest.checks.isEmpty else { throw UnifiedChecksError.emptyManifest }
        guard Set(manifest.checks.map(\.id)).count == manifest.checks.count else {
            throw UnifiedChecksError.duplicateCheckID
        }
        return manifest
    }
}

struct CIScopeManifestCheck: Decodable, Equatable, Identifiable {
    let id: String
    let type: String
}

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

enum UnifiedArtifactState: Equatable {
    case pending
    case available(name: String)
    case missing
    case expired
    case invalid(String)

    var description: String {
        switch self {
        case .pending: "Report pending"
        case .available: "Report available"
        case .missing: "Results unavailable"
        case .expired: "Report expired"
        case .invalid(let reason): "Invalid report: \(reason)"
        }
    }
}

struct UnifiedChecksSnapshot {
    let manifest: CIScopeManifest
    let run: GitHubRun?
    let report: UnifiedChecksReport?
    let artifact: UnifiedArtifactState
}

enum UnifiedChecksError: LocalizedError {
    case unsupportedManifestVersion
    case emptyManifest
    case duplicateCheckID
    case unsupportedReportVersion
    case reportTooLarge
    case reportIdentityMismatch

    var errorDescription: String? {
        switch self {
        case .unsupportedManifestVersion: "Unsupported .ci-scope.json version."
        case .emptyManifest: ".ci-scope.json contains no checks."
        case .duplicateCheckID: ".ci-scope.json contains duplicate check IDs."
        case .unsupportedReportVersion: "Unsupported result.json version."
        case .reportTooLarge: "result.json exceeds 64 KiB."
        case .reportIdentityMismatch: "Report identity does not match the GitHub run."
        }
    }
}
