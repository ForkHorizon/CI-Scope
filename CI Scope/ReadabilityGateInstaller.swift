import Foundation
import Combine

struct ReadabilityGateInstallSnapshot: Equatable {
    var state: ServiceState
    var title: String
    var detail: String
    var isInstalling: Bool
    var pullRequestURL: URL?

    static let idle = ReadabilityGateInstallSnapshot(
        state: .unknown,
        title: "AI readability gate",
        detail: "Not installed from this session.",
        isInstalling: false,
        pullRequestURL: nil
    )

    static func installing() -> ReadabilityGateInstallSnapshot {
        ReadabilityGateInstallSnapshot(
            state: .warning,
            title: "Installing AI readability gate",
            detail: "Creating branch, writing files, and preparing a pull request.",
            isInstalling: true,
            pullRequestURL: nil
        )
    }

    static func succeeded(_ result: ReadabilityGateInstallResult) -> ReadabilityGateInstallSnapshot {
        ReadabilityGateInstallSnapshot(
            state: .online,
            title: result.title,
            detail: result.detail,
            isInstalling: false,
            pullRequestURL: result.pullRequestURL
        )
    }

    static func failed(_ message: String) -> ReadabilityGateInstallSnapshot {
        ReadabilityGateInstallSnapshot(
            state: .offline,
            title: "AI readability gate failed",
            detail: message,
            isInstalling: false,
            pullRequestURL: nil
        )
    }
}

struct ReadabilityGateInstallResult {
    let title: String
    let detail: String
    let pullRequestURL: URL?
}

@MainActor
final class ReadabilityGateInstallViewModel: ObservableObject {
    @Published private var snapshots: [CIProject.ID: ReadabilityGateInstallSnapshot] = [:]

    private let installer: ReadabilityGateInstaller

    init() {
        self.installer = ReadabilityGateInstaller(config: DashboardConfig())
    }

    init(config: DashboardConfig) {
        self.installer = ReadabilityGateInstaller(config: config)
    }

    func snapshot(for project: CIProject) -> ReadabilityGateInstallSnapshot {
        snapshots[project.id] ?? .idle
    }

    func install(in project: CIProject, onSuccess: @escaping () -> Void = {}) {
        guard !snapshots.values.contains(where: \.isInstalling) else { return }

        snapshots[project.id] = .installing()

        Task {
            do {
                let result = try await installer.install(in: project)
                snapshots[project.id] = .succeeded(result)
                onSuccess()
            } catch {
                snapshots[project.id] = .failed(error.localizedDescription)
            }
        }
    }
}
