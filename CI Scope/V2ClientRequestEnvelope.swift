import Foundation

nonisolated struct V2ClientRequestEnvelope<Payload: Codable & Sendable>: Codable, Sendable {
  let protocolVersion: Int
  let requestId: String
  let payloadHash: String
  let session: V2ClientSessionContext
  let fencing: V2ClientFencingContext
  let payload: Payload

  init(
    payload: Payload,
    session: V2ClientSessionContext,
    fencing: V2ClientFencingContext,
    requestId: String = UUID().uuidString,
    protocolVersion: Int = 2
  ) throws {
    guard protocolVersion == 2 else {
      throw V2ClientBridgeError.unsupportedProtocolVersion(protocolVersion)
    }
    guard session.sessionEpoch > 0,
      fencing.localOwnerEpoch > 0,
      fencing.sessionEpoch == session.sessionEpoch
    else {
      throw V2ClientBridgeError.invalidFencingContext
    }
    self.protocolVersion = protocolVersion
    self.requestId = requestId
    self.payloadHash = try V2ClientPayloadHasher.sha256(payload)
    self.session = session
    self.fencing = fencing
    self.payload = payload
  }

  func validatePayloadHash() throws {
    let actual = try V2ClientPayloadHasher.sha256(payload)
    guard actual == payloadHash else {
      throw V2ClientBridgeError.invalidPayloadHash(expected: payloadHash, actual: actual)
    }
  }

  func validate() throws {
    guard protocolVersion == 2 else {
      throw V2ClientBridgeError.unsupportedProtocolVersion(protocolVersion)
    }
    guard session.sessionEpoch > 0,
      fencing.localOwnerEpoch > 0,
      fencing.sessionEpoch == session.sessionEpoch
    else {
      throw V2ClientBridgeError.invalidFencingContext
    }
    try validatePayloadHash()
  }
}

nonisolated struct V2ClientResponseContext: Sendable {
  let requestId: String
  let session: V2ClientSessionContext
  let fencing: V2ClientFencingContext
  let operationId: String
  let protocolVersion: Int
}
