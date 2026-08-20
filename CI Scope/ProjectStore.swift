import Foundation
import Combine

struct CIProject: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let repositoryOwner: String
    let repositoryName: String
    let repositorySlug: String
    let remoteURL: String

    var normalizedSlug: String {
        repositorySlug.lowercased()
    }
}

@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [CIProject]
    @Published private(set) var selectedProjectID: CIProject.ID?

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
            self.selectedProjectID = normalizedProjects.first?.id
        }

        persist()
    }

    var selectedProject: CIProject? {
        guard let selectedProjectID else { return nil }
        return projects.first(where: { $0.id == selectedProjectID })
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
            remoteURL: parsed.remoteURL
        )

        projects.append(project)
        selectedProjectID = project.id
        persist()
        return project
    }

    func removeProject(_ project: CIProject) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }

        let wasSelected = selectedProjectID == project.id
        projects.remove(at: index)

        if wasSelected {
            if projects.isEmpty {
                selectedProjectID = nil
            } else {
                selectedProjectID = projects[min(index, projects.count - 1)].id
            }
        } else if let selectedProjectID, !projects.contains(where: { $0.id == selectedProjectID }) {
            self.selectedProjectID = projects.first?.id
        }

        persist()
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
        if let selectedProjectID {
            defaults.set(selectedProjectID, forKey: selectedProjectKey)
        } else {
            defaults.removeObject(forKey: selectedProjectKey)
        }
    }

    static func loadConfiguredProjects(from defaults: UserDefaults = .standard) -> [CIProject] {
        let loaded = loadProjects(from: defaults, key: "ciScope.projects")
        return normalizedProjects(loaded)
    }

    private static func loadProjects(from defaults: UserDefaults, key: String) -> [CIProject] {
        guard
            let data = defaults.data(forKey: key),
            let decoded = try? JSONDecoder().decode([CIProject].self, from: data)
        else {
            return []
        }
        return decoded
    }

    private static func normalizedProjects(_ projects: [CIProject]) -> [CIProject] {
        var seen = Set<String>()
        var result: [CIProject] = []

        for project in projects {
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

        let protocolGroup = "^(?:https?://github\\.com/|git@github\\.com:)?"
        let ownerGroup = "([a-zA-Z0-9](?:[a-zA-Z0-9]|-(?=[a-zA-Z0-9])){0,38})"
        let repoGroup = "/([a-zA-Z0-9_.-]+?)(?:\\.git)?/?$"
        let pattern = protocolGroup + ownerGroup + repoGroup

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            throw ProjectStoreError.invalidRepositoryURL
        }

        let nsString = trimmed as NSString
        let results = regex.matches(in: trimmed, range: NSRange(location: 0, length: nsString.length))

        guard let match = results.first, match.numberOfRanges == 3 else {
            throw ProjectStoreError.invalidRepositoryURL
        }

        let ownerRange = match.range(at: 1)
        let repoRange = match.range(at: 2)

        let owner = nsString.substring(with: ownerRange)
        let name = nsString.substring(with: repoRange)

        guard isValidGitHubComponent(owner), isValidGitHubComponent(name) else {
            throw ProjectStoreError.invalidRepositoryURL
        }

        let remoteURL = "https://github.com/\(owner)/\(name).git"
        return ParsedRepository(owner: owner, name: name, remoteURL: remoteURL)
    }

    private static func isValidGitHubComponent(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        if value.hasPrefix("-") || value.hasPrefix(".") { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private struct ParsedRepository {
        let owner: String
        let name: String
        let remoteURL: String
    }
}
