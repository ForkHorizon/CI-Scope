import Foundation

nonisolated struct V2ClientStatusAdapter: @unchecked Sendable {
    let transport: V2ClientUnixSocketTransport
    let session: V2ClientSessionContext
    let fencing: V2ClientFencingContext
    let appInstanceID: String

    nonisolated static func configured(defaults: UserDefaults = .standard) -> V2ClientStatusAdapter? {
        guard V2ClientFeature.statusAdapterEnabled(defaults: defaults) else { return nil }
        let descriptor = V2ClientAgentSessionDescriptor.load()
        let socketPath =
            descriptor?.socketPath ?? defaults.string(forKey: V2ClientFeature.socketPathKey)
        let bootID = descriptor?.bootID ?? defaults.string(forKey: V2ClientFeature.bootIDKey)
        let agentInstanceID =
            descriptor?.agentInstanceID ?? defaults.string(forKey: V2ClientFeature.agentInstanceIDKey)
        let sessionID = descriptor?.sessionID ?? defaults.string(forKey: V2ClientFeature.sessionIDKey)
        let fencingToken =
            descriptor?.fencingToken ?? defaults.string(forKey: V2ClientFeature.fencingTokenKey)
        let machineID = descriptor?.machineID ?? defaults.string(forKey: "ciScope.queue.machineID")
        guard let socketPath, let bootID, let agentInstanceID, let sessionID, let fencingToken,
            let machineID,
            !socketPath.isEmpty, !bootID.isEmpty, !agentInstanceID.isEmpty, !sessionID.isEmpty,
            !fencingToken.isEmpty, !machineID.isEmpty
        else { return nil }

        let sessionEpoch =
            descriptor?.sessionEpoch ?? defaults.integer(forKey: V2ClientFeature.sessionEpochKey)
        let localOwnerEpoch =
            descriptor?.localOwnerEpoch ?? defaults.integer(forKey: V2ClientFeature.localOwnerEpochKey)
        guard sessionEpoch > 0, localOwnerEpoch > 0 else { return nil }

        let session = V2ClientSessionContext(
            machineId: machineID,
            bootId: bootID,
            agentInstanceId: agentInstanceID,
            sessionId: sessionID,
            sessionEpoch: Int64(sessionEpoch)
        )
        let fencing = V2ClientFencingContext(
            localOwnerEpoch: Int64(localOwnerEpoch),
            sessionEpoch: Int64(sessionEpoch),
            fencingToken: fencingToken
        )
        let configuration = V2ClientUnixSocketConfiguration(socketURL: URL(fileURLWithPath: socketPath))
        return V2ClientStatusAdapter(
            transport: V2ClientUnixSocketTransport(configuration: configuration),
            session: session,
            fencing: fencing,
            appInstanceID: defaults.string(forKey: "ciScope.v2.appInstanceID") ?? UUID().uuidString
        )
    }

    nonisolated func makeStatusRequest(requestID: String = UUID().uuidString) throws
        -> V2ClientRequestEnvelope<
            V2ClientControlCommandPayload
        >
    {
        try V2ClientRequestEnvelope(
            payload: V2ClientControlCommandPayload(command: .status, appInstanceId: appInstanceID),
            session: session,
            fencing: fencing,
            requestId: requestID
        )
    }

    func status() async -> V2ClientStatusResult {
        await Task.detached(priority: .utility) {
            do {
                let request = try makeStatusRequest()
                let response: V2ClientResponseEnvelope<V2ClientStatusProjection> = try transport.send(
                    request,
                    responseType: V2ClientStatusProjection.self
                )
                guard response.outcome == .accepted || response.outcome == .succeeded else {
                    return .unavailable("Agent returned \(response.outcome.rawValue) for status.")
                }
                return .available(response.payload)
            } catch {
                return .unavailable(String(describing: error))
            }
        }.value
    }
}

/// The narrow transition seam for future V2 mutations. Status remains
/// available in read-only mode; every other command fails closed until an
/// explicit authority state and matching live control lease are present.
