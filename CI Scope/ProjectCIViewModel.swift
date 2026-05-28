import Foundation
import Combine

@MainActor
final class ProjectCIViewModel: ObservableObject {
    @Published private(set) var snapshots: [CIProject.ID: ProjectCISnapshot] = [:]
    @Published private(set) var loadingProjectID: CIProject.ID?

    private let service: ProjectCIService

    init() {
        self.service = ProjectCIService(config: DashboardConfig())
    }

    func snapshot(for projectID: CIProject.ID) -> ProjectCISnapshot? {
        snapshots[projectID]
    }

    func load(_ project: CIProject) async {
        loadingProjectID = project.id
        let snapshot = await service.loadSnapshot(for: project)
        snapshots[project.id] = snapshot
        if loadingProjectID == project.id {
            loadingProjectID = nil
        }
    }
}
