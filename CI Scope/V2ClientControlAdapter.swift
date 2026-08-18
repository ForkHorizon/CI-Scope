import Foundation

nonisolated struct V2ClientControlRequest: Sendable {
    let command: V2ClientControlCommand
    let controlToken: String?
    let drainDeadline: Date?
    let requestID: String
    let now: Date

    init(
        command: V2ClientControlCommand,
        controlToken: String? = nil,
        drainDeadline: Date? = nil,
        requestID: String = UUID().uuidString,
        now: Date = Date()
    ) {
        self.command = command
        self.controlToken = controlToken
        self.drainDeadline = drainDeadline
        self.requestID = requestID
        self.now = now
    }
}

nonisolated struct V2ClientControlAdapter: @unchecked Sendable {
    let statusAdapter: V2ClientStatusAdapter
    let authorityState: V2ClientAuthorityState
    let lease: V2ClientControlLeaseMachine

    init(
        statusAdapter: V2ClientStatusAdapter,
        authorityState: V2ClientAuthorityState,
        lease: V2ClientControlLeaseMachine = V2ClientControlLeaseMachine()
    ) {
        self.statusAdapter = statusAdapter
        self.authorityState = authorityState
        self.lease = lease
    }

    nonisolated static func configured(defaults: UserDefaults = .standard) -> V2ClientControlAdapter? {
        guard let statusAdapter = V2ClientStatusAdapter.configured(defaults: defaults) else { return nil }
        return V2ClientControlAdapter(
            statusAdapter: statusAdapter,
            authorityState: V2ClientFeature.authorityState(defaults: defaults)
        )
    }

    nonisolated func makeControlRequest(
        command: V2ClientControlCommand,
        controlToken: String? = nil,
        drainDeadline: Date? = nil,
        requestID: String = UUID().uuidString,
        now: Date = Date()
    ) throws -> V2ClientRequestEnvelope<V2ClientControlCommandPayload> {
        guard command != .status else { throw V2ClientBridgeError.invalidControlCommand }

        switch command {
        case .acquireControlLease:
            guard authorityState == .v2ReadOnly, controlToken == nil else {
                throw V2ClientBridgeError.authorityRequired
            }
        case .renewControlLease, .resume, .drain:
            guard authorityState.allowsMutation else { throw V2ClientBridgeError.authorityRequired }
            guard case .active(let leaseToken, let expiresAt) = lease.state,
                expiresAt > now,
                controlToken == leaseToken
            else {
                throw V2ClientBridgeError.controlLeaseRequired
            }
        case .emergencyStop:
            guard authorityState.allowsMutation else { throw V2ClientBridgeError.authorityRequired }
            guard case .draining(let leaseToken, _) = lease.state,
                controlToken == leaseToken
            else {
                throw V2ClientBridgeError.controlLeaseRequired
            }
        case .status:
            throw V2ClientBridgeError.invalidControlCommand
        }

        return try V2ClientRequestEnvelope(
            payload: V2ClientControlCommandPayload(
                command: command,
                appInstanceId: statusAdapter.appInstanceID,
                controlToken: controlToken,
                drainDeadline: drainDeadline
            ),
            session: statusAdapter.session,
            fencing: statusAdapter.fencing,
            requestId: requestID
        )
    }

    nonisolated func sendControl<ResponsePayload: Codable & Sendable>(
        _ request: V2ClientControlRequest,
        responseType: ResponsePayload.Type
    ) throws -> V2ClientResponseEnvelope<ResponsePayload> {
        let envelope = try makeControlRequest(
            command: request.command,
            controlToken: request.controlToken,
            drainDeadline: request.drainDeadline,
            requestID: request.requestID,
            now: request.now
        )
        return try statusAdapter.transport.send(envelope, responseType: responseType)
    }
}
