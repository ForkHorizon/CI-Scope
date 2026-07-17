import Foundation

struct RunnerFleetService {
    let config: DashboardConfig

    func loadSnapshot(prepareBroker: Bool = true) async -> RunnerFleetSnapshot {
        let broker = await LocalBrokerService(config: config).loadRunnerSnapshot(prepareBroker: prepareBroker)

        return RunnerFleetSnapshot(
            runners: [broker],
            refreshedAt: Date(),
            errors: [broker].compactMap(\.error)
        )
    }
}
