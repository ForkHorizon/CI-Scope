import Foundation
import Combine

@MainActor
final class ProjectCIViewModel: ObservableObject {
    @Published private(set) var snapshots: [CIProject.ID: ProjectCISnapshot] = [:]
    @Published private(set) var loadingProjectID: CIProject.ID?

    private let service: ProjectCIService
    private var invalidatedProjectIDs = Set<CIProject.ID>()

    init() {
        self.service = ProjectCIService(config: DashboardConfig())
    }

    func snapshot(for projectID: CIProject.ID) -> ProjectCISnapshot? {
        snapshots[projectID]
    }

    func load(_ project: CIProject) async {
        invalidatedProjectIDs.remove(project.id)
        loadingProjectID = project.id
        let snapshot = await service.loadSnapshot(for: project)
        guard !invalidatedProjectIDs.contains(project.id) else { return }
        snapshots[project.id] = snapshot

        NotificationManager.shared.checkRunUpdates(projectSlug: project.repositorySlug, runs: snapshot.runs)

        if loadingProjectID == project.id {
            loadingProjectID = nil
        }
    }

    func refreshLocalRunnerFromBroker(_ project: CIProject) async {
        guard LocalBrokerService(config: DashboardConfig()).isManaged(project: project) else { return }
        guard !invalidatedProjectIDs.contains(project.id) else { return }

        let localRunner = await service.loadLocalRunner(for: project, prepareBroker: false)
        var snapshot = snapshots[project.id] ?? ProjectCISnapshot(projectID: project.id)
        snapshot.localRunner = localRunner
        snapshot.refreshedAt = Date()
        if snapshot.workflows.isEmpty && snapshot.runs.isEmpty && snapshot.error == nil {
            snapshot.state = localRunner.state
        }
        snapshots[project.id] = snapshot
    }

    func removeSnapshot(for projectID: CIProject.ID) {
        invalidatedProjectIDs.insert(projectID)
        snapshots[projectID] = nil
        if loadingProjectID == projectID {
            loadingProjectID = nil
        }
    }
}
