import Foundation

public enum V2ClientResponseOutcome: String, Codable {
    case accepted
    case succeeded
    case rejected
    case retryable
    case ambiguous
}

public struct V2ClientResponseEnvelope<Payload: Codable>: Codable {
    public let protocolVersion: Int
    public let requestId: String
    public let payloadHash: String
    public let session: V2ClientSessionContext
    public let fencing: V2ClientFencingContext
    public let operationId: String
    public let serverRevision: Int64
    public let outcome: V2ClientResponseOutcome
    public let retryAfterMs: Int64?
    public let payload: Payload

    public init(
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

    public func validatePayloadHash() throws {
        let actual = try V2ClientPayloadHasher.sha256(payload)
        guard actual == payloadHash else {
            throw V2ClientBridgeError.invalidPayloadHash(expected: payloadHash, actual: actual)
        }
    }

    public func validateAgainst<RequestPayload: Codable>(request: V2ClientRequestEnvelope<RequestPayload>) throws {
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

