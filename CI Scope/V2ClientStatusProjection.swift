import Foundation

nonisolated struct V2ClientStatusProjection: Codable, Equatable, Sendable {
  let processAlive: Bool
  let schedulerHealthy: Bool
  let controlLeaseActive: Bool
  let serverConnected: Bool
  let draining: Bool
  let recoveryBlocked: Bool
  let projectionLagging: Bool
  // The Agent includes these fields in its signed payload. Keep them in the
  // Codable projection so decoding and re-encoding preserves the envelope's
  // payload hash instead of silently dropping server state.
  let state: String?
  let localEpoch: Int64?
  let serverSessionEpoch: Int64?
  let controlLeaseExpiresAt: Int64?

  var readyToClaim: Bool {
    Self.canClaim(
      health: V2ClientStatusHealth(
        processAlive: processAlive,
        schedulerHealthy: schedulerHealthy,
        controlLeaseActive: controlLeaseActive,
        serverConnected: serverConnected
      ),
      safety: V2ClientStatusSafety(
        draining: draining,
        recoveryBlocked: recoveryBlocked,
        projectionLagging: projectionLagging
      )
    )
  }

  init(
    health: V2ClientStatusHealth,
    safety: V2ClientStatusSafety,
    details: V2ClientStatusDetails = V2ClientStatusDetails()
  ) {
    processAlive = health.processAlive
    schedulerHealthy = health.schedulerHealthy
    controlLeaseActive = health.controlLeaseActive
    serverConnected = health.serverConnected
    draining = safety.draining
    recoveryBlocked = safety.recoveryBlocked
    projectionLagging = safety.projectionLagging
    state = details.state
    localEpoch = details.localEpoch
    serverSessionEpoch = details.serverSessionEpoch
    controlLeaseExpiresAt = details.controlLeaseExpiresAt
  }

  static func canClaim(
    health: V2ClientStatusHealth,
    safety: V2ClientStatusSafety
  ) -> Bool {
    health.processAlive && health.schedulerHealthy && health.controlLeaseActive
      && health.serverConnected && !safety.draining && !safety.recoveryBlocked
      && !safety.projectionLagging
  }

  private enum CodingKeys: String, CodingKey {
    case processAlive
    case schedulerHealthy
    case controlLeaseActive
    case serverConnected
    case readyToClaim
    case draining
    case recoveryBlocked
    case projectionLagging
    case state
    case localEpoch
    case serverSessionEpoch
    case controlLeaseExpiresAt
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    processAlive = try container.decode(Bool.self, forKey: .processAlive)
    schedulerHealthy = try container.decode(Bool.self, forKey: .schedulerHealthy)
    controlLeaseActive = try container.decode(Bool.self, forKey: .controlLeaseActive)
    serverConnected = try container.decode(Bool.self, forKey: .serverConnected)
    draining = try container.decode(Bool.self, forKey: .draining)
    recoveryBlocked = try container.decode(Bool.self, forKey: .recoveryBlocked)
    projectionLagging = try container.decode(Bool.self, forKey: .projectionLagging)
    state = try container.decodeIfPresent(String.self, forKey: .state)
    localEpoch = try container.decodeIfPresent(Int64.self, forKey: .localEpoch)
    serverSessionEpoch = try container.decodeIfPresent(Int64.self, forKey: .serverSessionEpoch)
    controlLeaseExpiresAt = try container.decodeIfPresent(
      Int64.self, forKey: .controlLeaseExpiresAt)
    _ = try container.decodeIfPresent(Bool.self, forKey: .readyToClaim)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(processAlive, forKey: .processAlive)
    try container.encode(schedulerHealthy, forKey: .schedulerHealthy)
    try container.encode(controlLeaseActive, forKey: .controlLeaseActive)
    try container.encode(serverConnected, forKey: .serverConnected)
    try container.encode(readyToClaim, forKey: .readyToClaim)
    try container.encode(draining, forKey: .draining)
    try container.encode(recoveryBlocked, forKey: .recoveryBlocked)
    try container.encode(projectionLagging, forKey: .projectionLagging)
    try container.encodeIfPresent(state, forKey: .state)
    try container.encodeIfPresent(localEpoch, forKey: .localEpoch)
    try container.encodeIfPresent(serverSessionEpoch, forKey: .serverSessionEpoch)
    try container.encodeIfPresent(controlLeaseExpiresAt, forKey: .controlLeaseExpiresAt)
  }
}
