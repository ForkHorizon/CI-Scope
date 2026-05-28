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
        if loadingProjectID == project.id {
            loadingProjectID = nil
        }
    }

    func removeSnapshot(for projectID: CIProject.ID) {
        invalidatedProjectIDs.insert(projectID)
        snapshots[projectID] = nil
        if loadingProjectID == projectID {
            loadingProjectID = nil
        }
    }
}
