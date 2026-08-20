import Foundation

nonisolated struct V2ClientStatusHealth: Sendable {
  let processAlive: Bool
  let schedulerHealthy: Bool
  let controlLeaseActive: Bool
  let serverConnected: Bool
}

nonisolated struct V2ClientStatusSafety: Sendable {
  let draining: Bool
  let recoveryBlocked: Bool
  let projectionLagging: Bool
}
