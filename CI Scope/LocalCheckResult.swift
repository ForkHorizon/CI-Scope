import Foundation

/// Compact result written by `scripts/check` to `~/.ci-scope/checks/<owner>-<repo>.json`.
struct LocalCheckResult: Decodable, Equatable {
    struct Check: Decodable, Equatable, Identifiable {
        let id: String
        let status: String
        let durationMs: Int?

        private enum CodingKeys: String, CodingKey {
            case id, status
            case durationMs = "duration_ms"
        }
    }

    let status: String
    let tier: String?
    let finishedAt: String?
    let gitHead: String?
    let dirty: Bool
    let checks: [Check]
    let slow: [String]

    private enum CodingKeys: String, CodingKey {
        case status, tier, dirty, checks, slow
        case finishedAt = "finished_at"
        case gitHead = "git_head"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(String.self, forKey: .status)
        tier = try container.decodeIfPresent(String.self, forKey: .tier)
        finishedAt = try container.decodeIfPresent(String.self, forKey: .finishedAt)
        gitHead = try container.decodeIfPresent(String.self, forKey: .gitHead)
        dirty = try container.decodeIfPresent(Bool.self, forKey: .dirty) ?? false
        checks = try container.decodeIfPresent([Check].self, forKey: .checks) ?? []
        slow = try container.decodeIfPresent([String].self, forKey: .slow) ?? []
    }

    var passed: Bool { status == "passed" }

    var failedChecks: [Check] {
        checks.filter { $0.status != "passed" && $0.status != "skipped" }
    }

    var finishedDate: Date? {
        guard let finishedAt else { return nil }
        // Python writes microseconds; ISO8601DateFormatter only reliably takes milliseconds, so drop the fraction.
        let trimmed = finishedAt.replacingOccurrences(
            of: #"\.\d+"#, with: "", options: .regularExpression)
        return ISO8601DateFormatter().date(from: trimmed)
    }
}

enum LocalCheckStore {
    static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ci-scope/checks")
    }

    static func fileName(for repositorySlug: String) -> String {
        repositorySlug.replacingOccurrences(of: "/", with: "-") + ".json"
    }

    /// Nil when the project has never run `scripts/check` on this Mac or the file is unreadable.
    static func load(repositorySlug: String, directory: URL = defaultDirectory) -> LocalCheckResult? {
        let url = directory.appendingPathComponent(fileName(for: repositorySlug))
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(LocalCheckResult.self, from: data)
    }
}
