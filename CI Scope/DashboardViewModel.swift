import Foundation
import Combine

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var snapshot = DashboardSnapshot()
    @Published var isRefreshing = false
    @Published var selectedLog = LogKind.stdout

    let config = DashboardConfig()
    let commandRunner: LocalCommandRunner

    private let service: DashboardService

    init() {
        let config = DashboardConfig()
        self.service = DashboardService(config: config)
        self.commandRunner = LocalCommandRunner(config: config)
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true

        Task {
            let nextSnapshot = await service.loadSnapshot()
            snapshot = nextSnapshot
            isRefreshing = false
        }
    }

    func selectedLogText() -> String {
        switch selectedLog {
        case .stdout:
            snapshot.logs.stdoutTail
        case .stderr:
            snapshot.logs.stderrTail
        case .runnerDiag:
            snapshot.logs.latestRunnerDiagTail
        case .workerDiag:
            snapshot.logs.latestWorkerDiagTail
        }
    }
}

enum LogKind: String, CaseIterable, Identifiable {
    case stdout = "stdout"
    case stderr = "stderr"
    case runnerDiag = "runner diag"
    case workerDiag = "worker diag"

    var id: String { rawValue }
}
