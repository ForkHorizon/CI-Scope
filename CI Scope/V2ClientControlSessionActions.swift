import Foundation

@MainActor
extension V2ClientControlSession {
    func acquire() async {
        guard explicitAuthorityEnabled else {
            lastError = V2ClientBridgeError.authorityRequired.description
            return
        }
        guard let statusAdapter = configuredStatusAdapter() else {
            lastError = "V2 Agent session is not configured."
            return
        }
        guard Self.canAcquire(status: statusProjection, agentIsLive: isAgentLive) else {
            lastError = "V2 Agent must be live, connected, healthy, and not draining before authority can be acquired."
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let response = try await send(
                command: .acquireControlLease,
                adapter: V2ClientControlAdapter(
                    statusAdapter: statusAdapter,
                    authorityState: .v2ReadOnly,
                    lease: leaseMachine
                )
            )
            guard response.outcome == .accepted || response.outcome == .succeeded,
                let token = response.payload.controlToken,
                let expiresAt = response.payload.expiresAt
            else {
                throw V2ClientBridgeError.socketFailure("Agent rejected control lease acquisition.")
            }
            let expiry = Date(timeIntervalSince1970: Double(expiresAt) / 1_000)
            try leaseMachine.apply(.acquired(controlToken: token, expiresAt: expiry))
            leaseState = leaseMachine.state
            statusProjection = response.payload.statusProjection ?? statusProjection
            authorityReleasePending = false
            isDisablingAuthority = false
            defaults.set(false, forKey: V2ClientFeature.authorityReleasePendingKey)
            lastError = nil
            scheduleRenewal()
        } catch {
            lastError = String(describing: error)
        }
    }

    func renew() async {
        guard let (token, _) = activeLease else { return }
        await runMutation(.renewControlLease, controlToken: token) { [weak self] payload in
            guard let self, let nextExpiry = payload.expiresAt else { return }
            let expiry = Date(timeIntervalSince1970: Double(nextExpiry) / 1_000)
            try self.leaseMachine.apply(.renewed(controlToken: token, expiresAt: expiry))
            self.leaseState = self.leaseMachine.state
        }
    }

    func resume() async {
        guard let (token, _) = activeLease else { return }
        await runMutation(.resume, controlToken: token) { [weak self] payload in
            guard let self else { return }
            self.statusProjection = payload.statusProjection ?? self.statusProjection
        }
    }

    func drain(deadline: Date = Date().addingTimeInterval(60)) async {
        guard let (token, _) = activeLease else { return }
        await runMutation(.drain, controlToken: token, drainDeadline: deadline) { [weak self] payload in
            guard let self else { return }
            try self.leaseMachine.apply(.drainRequested(controlToken: token, deadline: deadline))
            self.leaseState = self.leaseMachine.state
            self.statusProjection = payload.statusProjection ?? self.statusProjection
            self.renewalTask?.cancel()
            self.renewalTask = nil
        }
    }

    func emergencyStop() async {
        guard case .draining(let token, _) = leaseState else {
            lastError = V2ClientBridgeError.controlLeaseRequired.description
            return
        }
        await runMutation(.emergencyStop, controlToken: token) { [weak self] payload in
            guard let self else { return }
            self.leaseMachine = V2ClientControlLeaseMachine(state: .released)
            self.leaseState = self.leaseMachine.state
            self.statusProjection = payload.statusProjection ?? self.statusProjection
            self.renewalTask?.cancel()
            self.renewalTask = nil
        }
    }

    var activeLease: (String, Date)? {
        guard case .active(let token, let expiry) = leaseState, expiry > Date() else { return nil }
        return (token, expiry)
    }

    func refreshStatusNow() async {
        guard let adapter else {
            isAgentLive = false
            return
        }
        let result = await adapter.status()
        switch result {
        case .available(let projection):
            statusProjection = projection
            isAgentLive = true
            lastStatusAt = Date()
            lastError = nil

            if authorityReleasePending {
                if !projection.draining && !projection.controlLeaseActive {
                    releaseAuthorityLocally()
                }
            } else if case .active = leaseState, !projection.controlLeaseActive {
                renewalTask?.cancel()
                renewalTask = nil
                leaseMachine = V2ClientControlLeaseMachine(state: .expired)
                leaseState = leaseMachine.state
                lastError = "V2 control lease is no longer active on the Agent."
            }
        case .unavailable(let error):
            isAgentLive = false
            lastError = error
        }
    }

    func drainForAuthorityDisable() async {
        guard case .active = leaseState else {
            if isDraining {
                await refreshStatusNow()
            } else {
                releaseAuthorityLocally()
            }
            return
        }
        await drain(deadline: Date().addingTimeInterval(60))
        await refreshStatusNow()
    }

    func releaseAuthorityLocally() {
        renewalTask?.cancel()
        renewalTask = nil
        leaseMachine = V2ClientControlLeaseMachine(state: .released)
        leaseState = leaseMachine.state
        authorityReleasePending = false
        isDisablingAuthority = false
        defaults.set(false, forKey: V2ClientFeature.authorityReleasePendingKey)
        lastError = nil
    }

    func configure() {
        adapter = V2ClientStatusAdapter.configured(defaults: defaults)
    }

    func configuredStatusAdapter() -> V2ClientStatusAdapter? {
        configure()
        return adapter
    }

    func scheduleRenewal() {
        renewalTask?.cancel()
        renewalTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let (_, expiry) = self.activeLease else { return }
                let delay = max(1, expiry.timeIntervalSinceNow / 2)
                do {
                    try await Task.sleep(for: .seconds(delay))
                } catch {
                    return
                }
                if !Task.isCancelled { await self.renew() }
            }
        }
    }

    func runMutation(
        _ command: V2ClientControlCommand,
        controlToken: String,
        drainDeadline: Date? = nil,
        apply: @escaping @MainActor (V2ClientControlResponsePayload) throws -> Void
    ) async {
        guard let statusAdapter = configuredStatusAdapter() else {
            lastError = "V2 Agent session is not configured."
            return
        }
        guard isAgentLive else {
            lastError = "V2 Agent session is not live. Refresh status before sending control commands."
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let response = try await send(
                command: command,
                controlToken: controlToken,
                drainDeadline: drainDeadline,
                adapter: V2ClientControlAdapter(
                    statusAdapter: statusAdapter,
                    authorityState: .v2Authority,
                    lease: leaseMachine
                )
            )
            guard response.outcome == .accepted || response.outcome == .succeeded else {
                throw V2ClientBridgeError.socketFailure("Agent rejected \(command.rawValue).")
            }
            try apply(response.payload)
            lastError = nil
        } catch {
            lastError = String(describing: error)
        }
    }

    func send(
        command: V2ClientControlCommand,
        controlToken: String? = nil,
        drainDeadline: Date? = nil,
        adapter: V2ClientControlAdapter
    ) async throws -> V2ClientResponseEnvelope<V2ClientControlResponsePayload> {
        try await Task.detached(priority: .utility) {
            try adapter.sendControl(
                V2ClientControlRequest(
                    command: command,
                    controlToken: controlToken,
                    drainDeadline: drainDeadline
                ),
                responseType: V2ClientControlResponsePayload.self
            )
        }.value
    }
}
