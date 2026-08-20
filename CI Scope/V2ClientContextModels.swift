import Foundation

nonisolated struct V2ClientSessionContext: Codable, Equatable, Sendable {
  let machineId: String
  let bootId: String
  let agentInstanceId: String
  let sessionId: String
  let sessionEpoch: Int64
}

nonisolated struct V2ClientFencingContext: Codable, Equatable, Sendable {
  let localOwnerEpoch: Int64
  let sessionEpoch: Int64
  let fencingToken: String?
  let runnerInstanceId: String?

  init(
    localOwnerEpoch: Int64,
    sessionEpoch: Int64,
    fencingToken: String? = nil,
    runnerInstanceId: String? = nil
  ) {
    self.localOwnerEpoch = localOwnerEpoch
    self.sessionEpoch = sessionEpoch
    self.fencingToken = fencingToken
    self.runnerInstanceId = runnerInstanceId
  }
}
