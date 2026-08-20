import Foundation

nonisolated enum V2ClientResponseOutcome: String, Codable, Sendable {
  case accepted
  case succeeded
  case rejected
  case retryable
  case ambiguous
}

nonisolated struct V2ClientResponseEnvelope<Payload: Codable & Sendable>: Codable, Sendable {
  let protocolVersion: Int
  let requestId: String
  let payloadHash: String
  let session: V2ClientSessionContext
  let fencing: V2ClientFencingContext
  let operationId: String
  let serverRevision: Int64
  let outcome: V2ClientResponseOutcome
  let retryAfterMs: Int64?
  let payload: Payload

  init(
    payload: Payload,
    context: V2ClientResponseContext,
    serverRevision: Int64,
    outcome: V2ClientResponseOutcome,
    retryAfterMs: Int64? = nil
  ) throws {
    guard context.protocolVersion == 2 else {
      throw V2ClientBridgeError.unsupportedProtocolVersion(context.protocolVersion)
    }
    guard serverRevision >= 0,
      context.session.sessionEpoch > 0,
      context.fencing.localOwnerEpoch > 0,
      context.fencing.sessionEpoch == context.session.sessionEpoch
    else {
      if serverRevision < 0 { throw V2ClientBridgeError.invalidServerRevision }
      throw V2ClientBridgeError.invalidFencingContext
    }
    self.protocolVersion = context.protocolVersion
    self.requestId = context.requestId
    self.payloadHash = try V2ClientPayloadHasher.sha256(payload)
    self.session = context.session
    self.fencing = context.fencing
    self.operationId = context.operationId
    self.serverRevision = serverRevision
    self.outcome = outcome
    self.retryAfterMs = retryAfterMs
    self.payload = payload
  }

  func validatePayloadHash() throws {
    let actual = try V2ClientPayloadHasher.sha256(payload)
    guard actual == payloadHash else {
      throw V2ClientBridgeError.invalidPayloadHash(expected: payloadHash, actual: actual)
    }
  }

  func validateAgainst<RequestPayload: Codable>(request: V2ClientRequestEnvelope<RequestPayload>)
    throws
  {
    guard protocolVersion == request.protocolVersion, protocolVersion == 2,
      request.session == session,
      request.fencing.sessionEpoch == fencing.sessionEpoch,
      request.fencing.localOwnerEpoch == fencing.localOwnerEpoch,
      request.fencing.fencingToken == fencing.fencingToken
    else {
      throw V2ClientBridgeError.invalidResponseContext
    }
    guard serverRevision >= 0 else {
      throw V2ClientBridgeError.invalidServerRevision
    }
    try validatePayloadHash()
  }
}
