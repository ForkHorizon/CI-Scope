import Foundation

nonisolated struct V2ClientStatusDetails: Sendable {
  let state: String?
  let localEpoch: Int64?
  let serverSessionEpoch: Int64?
  let controlLeaseExpiresAt: Int64?

  init(
    state: String? = nil,
    localEpoch: Int64? = nil,
    serverSessionEpoch: Int64? = nil,
    controlLeaseExpiresAt: Int64? = nil
  ) {
    self.state = state
    self.localEpoch = localEpoch
    self.serverSessionEpoch = serverSessionEpoch
    self.controlLeaseExpiresAt = controlLeaseExpiresAt
  }
}
