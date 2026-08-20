import Combine
import Foundation

@MainActor
final class ProjectCIViewModel: ObservableObject {
  @Published private(set) var snapshots: [CIProject.ID: ProjectCISnapshot] = [:]
  @Published private(set) var loadingProjectID: CIProject.ID?

  private let service: ProjectCIService
  private var invalidatedProjectIDs = Set<CIProject.ID>()
  // Guards against stale async writes racing on snapshots[id]. loadGeneration
  // discards superseded loads (A→B→A or duplicate refresh); brokerWriteSeq lets
  // a finishing load detect a fresher broker localRunner landed mid-flight.
  private var loadGeneration: [CIProject.ID: Int] = [:]
  private var runnerWriteSeq: [CIProject.ID: Int] = [:]

  init() {
    self.service = ProjectCIService(config: DashboardConfig())
  }

  func snapshot(for projectID: CIProject.ID) -> ProjectCISnapshot? {
    snapshots[projectID]
  }

  func load(_ project: CIProject, forceRefresh: Bool = false) async {
    invalidatedProjectIDs.remove(project.id)
    loadingProjectID = project.id
    let generation = (loadGeneration[project.id] ?? 0) + 1
    loadGeneration[project.id] = generation
    let runnerSeqAtStart = runnerWriteSeq[project.id] ?? 0

    var snapshot = await service.loadSnapshot(for: project, forceRefresh: forceRefresh)
    guard !invalidatedProjectIDs.contains(project.id),
      loadGeneration[project.id] == generation
    else { return }

    // A runner refresh landed a fresher local-runner state while we were loading;
    // keep it instead of reverting to the copy loadSnapshot fetched earlier.
    if runnerWriteSeq[project.id] != runnerSeqAtStart,
      let liveRunner = snapshots[project.id]?.localRunner
    {
      snapshot.localRunner = liveRunner
    }
    snapshots[project.id] = snapshot

    NotificationManager.shared.checkRunUpdates(
      projectSlug: project.repositorySlug, runs: snapshot.runs)

    if loadingProjectID == project.id {
      loadingProjectID = nil
    }
  }

  func refreshLocalRunner(_ project: CIProject) async {
    guard !invalidatedProjectIDs.contains(project.id) else { return }

    let localRunner = await service.loadLocalRunner(for: project)
    var snapshot = snapshots[project.id] ?? ProjectCISnapshot()
    snapshot.localRunner = localRunner
    snapshot.refreshedAt = Date()
    if snapshot.workflows.isEmpty && snapshot.runs.isEmpty && snapshot.error == nil {
      snapshot.state = localRunner.state
    }
    snapshots[project.id] = snapshot
    runnerWriteSeq[project.id] = (runnerWriteSeq[project.id] ?? 0) + 1
  }

  func removeSnapshot(for projectID: CIProject.ID) {
    invalidatedProjectIDs.insert(projectID)
    snapshots[projectID] = nil
    if loadingProjectID == projectID {
      loadingProjectID = nil
    }
  }
}
