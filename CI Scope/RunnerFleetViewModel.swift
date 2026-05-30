import Foundation
import Combine

@MainActor
final class RunnerFleetViewModel: ObservableObject {
    @Published private(set) var snapshot = RunnerFleetSnapshot()
    @Published private(set) var isLoading = false

    private let service: RunnerFleetService

    init() {
        self.service = RunnerFleetService(config: DashboardConfig())
    }

    func load() async {
        isLoading = true
        snapshot = await service.loadSnapshot()
        isLoading = false
    }
}
