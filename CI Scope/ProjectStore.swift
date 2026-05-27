import Foundation
import Combine

struct CIProject: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let repositoryOwner: String
    let repositoryName: String
    let repositorySlug: String
    let remoteURL: String
    let isPrimary: Bool

    static let primary = CIProject(
        id: "forkhorizon/nexusunity",
        title: "NexusUnity",
        repositoryOwner: "ForkHorizon",
        repositoryName: "NexusUnity",
        repositorySlug: "ForkHorizon/NexusUnity",
        remoteURL: "git@github.com:ForkHorizon/NexusUnity.git",
        isPrimary: true
    )

    var normalizedSlug: String {
        repositorySlug.lowercased()
    }
}

@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [CIProject]
    @Published private(set) var selectedProjectID: CIProject.ID

    private let defaults: UserDefaults
    private let projectsKey = "ciScope.projects"
    private let selectedProjectKey = "ciScope.selectedProjectID"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let loadedProjects = Self.loadProjects(from: defaults, key: projectsKey)
        let normalizedProjects = Self.normalizedProjects(loadedProjects)
        self.projects = normalizedProjects

        let storedSelection = defaults.string(forKey: selectedProjectKey)
        if let storedSelection, normalizedProjects.contains(where: { $0.id == storedSelection }) {
            self.selectedProjectID = storedSelection
        } else {
            self.selectedProjectID = CIProject.primary.id
        }

        persist()
    }

    var selectedProject: CIProject {
        projects.first(where: { $0.id == selectedProjectID }) ?? CIProject.primary
    }

    func select(_ project: CIProject) {
        selectedProjectID = project.id
        persistSelectedProject()
    }

    @discardableResult
    func addProject(from input: String) throws -> CIProject {
        let parsed = try Self.parseRepository(from: input)
        let slug = "\(parsed.owner)/\(parsed.name)"
        let normalizedSlug = slug.lowercased()

        guard !projects.contains(where: { $0.normalizedSlug == normalizedSlug }) else {
            throw ProjectStoreError.duplicateProject(slug)
        }

        let project = CIProject(
            id: normalizedSlug,
            title: parsed.name,
            repositoryOwner: parsed.owner,
            repositoryName: parsed.name,
            repositorySlug: slug,
            remoteURL: parsed.remoteURL,
            isPrimary: false
        )

        projects.append(project)
        selectedProjectID = project.id
        persist()
        return project
    }

    private func persist() {
        persistProjects()
        persistSelectedProject()
    }

    private func persistProjects() {
        guard let data = try? JSONEncoder().encode(projects) else { return }
        defaults.set(data, forKey: projectsKey)
    }

    private func persistSelectedProject() {
        defaults.set(selectedProjectID, forKey: selectedProjectKey)
    }

    private static func loadProjects(from defaults: UserDefaults, key: String) -> [CIProject] {
        guard
            let data = defaults.data(forKey: key),
            let decoded = try? JSONDecoder().decode([CIProject].self, from: data)
        else {
            return [CIProject.primary]
        }
        return decoded
    }

    private static func normalizedProjects(_ projects: [CIProject]) -> [CIProject] {
        var seen = Set<String>()
        var result: [CIProject] = []

        for project in [CIProject.primary] + projects {
            let slug = project.normalizedSlug
            guard !seen.contains(slug) else { continue }
            seen.insert(slug)
            result.append(project)
        }

        return result
    }

    private static func parseRepository(from input: String) throws -> ParsedRepository {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ProjectStoreError.emptyInput
        }

        if trimmed.hasPrefix("git@github.com:") {
            let path = String(trimmed.dropFirst("git@github.com:".count))
            return try parsePath(path, originalInput: trimmed)
        }

        if trimmed.hasPrefix("https://github.com/") {
            let path = String(trimmed.dropFirst("https://github.com/".count))
            return try parsePath(path, originalInput: trimmed)
        }

        if trimmed.hasPrefix("http://github.com/") {
            let path = String(trimmed.dropFirst("http://github.com/".count))
            return try parsePath(path, originalInput: trimmed)
        }

        return try parsePath(trimmed, originalInput: trimmed)
    }

    private static func parsePath(_ path: String, originalInput: String) throws -> ParsedRepository {
        let sanitized = path
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let parts = sanitized.split(separator: "/", omittingEmptySubsequences: true)

        guard parts.count == 2 else {
            throw ProjectStoreError.invalidRepositoryURL
        }

        let owner = String(parts[0])
        let rawName = String(parts[1])
        let name = rawName.hasSuffix(".git") ? String(rawName.dropLast(4)) : rawName

        guard isValidGitHubComponent(owner), isValidGitHubComponent(name) else {
            throw ProjectStoreError.invalidRepositoryURL
        }

        return ParsedRepository(owner: owner, name: name, remoteURL: originalInput)
    }

    private static func isValidGitHubComponent(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private struct ParsedRepository {
        let owner: String
        let name: String
        let remoteURL: String
    }
}

enum ProjectStoreError: LocalizedError {
    case emptyInput
    case invalidRepositoryURL
    case duplicateProject(String)

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            "Enter a GitHub repository URL."
        case .invalidRepositoryURL:
            "Use owner/repo, https://github.com/owner/repo, or git@github.com:owner/repo.git."
        case .duplicateProject(let slug):
            "\(slug) is already in Projects."
        }
    }
}
