import Foundation

/// A project's checks as the CI Scope server holds them (CI-Scope-Web project-config-contract.ts).
/// The repository under test never carries this, so an agent cannot edit the limits it is held to.
struct ProjectConfig: Codable, Equatable {
    struct CodeRules: Codable, Equatable {
        struct Params: Codable, Equatable {
            var maxFileLines: Int
            var maxFunctionLines: Int
            var maxNestingDepth: Int
            var maxParameters: Int
            var ignore: [String]
            var forbidSuppressions: Bool
        }
        var enabled: Bool
        var params: Params
    }

    struct Lanes: Codable, Equatable {
        struct Toggle: Codable, Equatable { var enabled: Bool }
        struct Languages: Codable, Equatable {
            var enabled: Bool
            var adapters: [String]
        }
        struct Tests: Codable, Equatable {
            var enabled: Bool
            var command: String
        }
        var codeRules: CodeRules
        var agentGuard: Toggle
        var language: Languages
        var tests: Tests

        enum CodingKeys: String, CodingKey {
            case codeRules = "code-rules"
            case agentGuard = "agent-guard"
            case language, tests
        }
    }

    struct MergeGate: Codable, Equatable {
        var requireGreen: Bool
        var deleteBranchAfterMerge: Bool
    }

    var schema: Int
    var repository: String
    var version: Int
    var observeOnly: Bool
    var lanes: Lanes
    var protectedFiles: [String]
    var mergeGate: MergeGate
    var updatedBy: String
    var updatedAt: Int

    static let languageAdapters = ["swift", "python", "go", "web", "unity", "rust"]

    /// One line for the project list: which lanes guard this project.
    var summary: String {
        var parts: [String] = []
        if lanes.codeRules.enabled { parts.append("code rules") }
        if lanes.agentGuard.enabled { parts.append("agent guard") }
        if lanes.language.enabled, !lanes.language.adapters.isEmpty {
            parts.append(lanes.language.adapters.joined(separator: ", "))
        }
        if lanes.tests.enabled { parts.append("tests") }
        let base = parts.isEmpty ? "no checks" : parts.joined(separator: " · ")
        return observeOnly ? base + " (observe only)" : base
    }
}
