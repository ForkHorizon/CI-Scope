import Foundation

public struct V2ClientRequestEnvelope<Payload: Codable>: Codable {
    public let protocolVersion: Int
    public let requestId: String
    public let payloadHash: String
    public let session: V2ClientSessionContext
    public let fencing: V2ClientFencingContext
    public let payload: Payload

    public init(
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

    public func validatePayloadHash() throws {
        let actual = try V2ClientPayloadHasher.sha256(payload)
        guard actual == payloadHash else {
            throw V2ClientBridgeError.invalidPayloadHash(expected: payloadHash, actual: actual)
        }
    }

    public func validate() throws {
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

public struct V2ClientResponseContext {
    public let requestId: String
    public let session: V2ClientSessionContext
    public let fencing: V2ClientFencingContext
    public let operationId: String
    public let protocolVersion: Int

    public init(
        requestId: String,
        session: V2ClientSessionContext,
        fencing: V2ClientFencingContext,
        operationId: String = UUID().uuidString,
        protocolVersion: Int = 2
    ) {
        self.requestId = requestId
        self.session = session
        self.fencing = fencing
        self.operationId = operationId
        self.protocolVersion = protocolVersion
    }
}

