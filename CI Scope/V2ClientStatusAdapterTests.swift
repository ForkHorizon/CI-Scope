#if canImport(XCTest)
import Foundation
import XCTest

final class V2ClientStatusAdapterTests: XCTestCase {
    func testStatusAdapterIsOptInAndDoesNotEnableFromMissingDefaults() {
        let suiteName = "V2ClientStatusAdapterTests"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        XCTAssertFalse(V2ClientFeature.statusAdapterEnabled(defaults: defaults))
        XCTAssertNil(V2ClientStatusAdapter.configured(defaults: defaults))
    }

    func testStatusRequestUsesReadOnlyStatusCommandAndContext() throws {
        let transport = V2ClientUnixSocketTransport(
            configuration: V2ClientUnixSocketConfiguration(
                socketURL: URL(fileURLWithPath: "/tmp/ci-scope-test.sock"),
                expectedPeerUID: 1
            )
        )
        let adapter = V2ClientStatusAdapter(
            transport: transport,
            session: V2ClientSessionContext(
                machineId: "machine-1",
                bootId: "boot-1",
                agentInstanceId: "agent-1",
                sessionId: "session-1",
                sessionEpoch: 2
            ),
            fencing: V2ClientFencingContext(localOwnerEpoch: 3, sessionEpoch: 2, fencingToken: "fence-1"),
            appInstanceID: "ui-1"
        )

        let request = try adapter.makeStatusRequest(requestID: "status-1")
        XCTAssertEqual(request.requestId, "status-1")
        XCTAssertEqual(request.payload.command, .status)
        XCTAssertEqual(request.payload.appInstanceId, "ui-1")
        XCTAssertEqual(request.fencing.fencingToken, "fence-1")
        XCTAssertNoThrow(try request.validate())
    }

    func testAuthorityStateDefaultsToLegacyOrReadOnly() {
        let suiteName = "V2ClientAuthorityStateTests"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        XCTAssertEqual(V2ClientFeature.authorityState(defaults: defaults), .legacyBroker)
        defaults.set(true, forKey: V2ClientFeature.statusAdapterKey)
        XCTAssertEqual(V2ClientFeature.authorityState(defaults: defaults), .v2ReadOnly)

        defaults.set(V2ClientAuthorityState.v2Authority.rawValue, forKey: V2ClientFeature.authorityStateKey)
        XCTAssertEqual(V2ClientFeature.authorityState(defaults: defaults), .v2Authority)

        defaults.set(false, forKey: V2ClientFeature.statusAdapterKey)
        XCTAssertEqual(V2ClientFeature.authorityState(defaults: defaults), .legacyBroker)
    }

    func testEmergencyStopRequiresDrainingLease() throws {
        let now = Date(timeIntervalSince1970: 100)
        var lease = V2ClientControlLeaseMachine()
        try lease.apply(.acquired(controlToken: "token", expiresAt: now.addingTimeInterval(30)), now: now)
        try lease.apply(.drainRequested(controlToken: "token", deadline: now.addingTimeInterval(10)), now: now)
        let adapter = makeAdapter(authorityState: .v2Authority, lease: lease)

        let request = try adapter.makeControlRequest(
            command: .emergencyStop,
            controlToken: "token",
            now: now
        )
        XCTAssertEqual(request.payload.command, .emergencyStop)
    }

    func testControlResponsePayloadPreservesEmptyErrorPayloadHash() throws {
        let payload = try JSONDecoder().decode(
            V2ClientControlResponsePayload.self,
            from: Data("{}".utf8)
        )
        XCTAssertNil(payload.controlToken)
        XCTAssertEqual(try V2ClientPayloadHasher.canonicalData(payload), Data("{}".utf8))
    }

    func testControlAdapterAllowsOnlyLeaseAcquisitionWhileReadOnly() throws {
        let adapter = makeAdapter(authorityState: .v2ReadOnly)

        let request = try adapter.makeControlRequest(
            command: .acquireControlLease,
            requestID: "acquire-1"
        )
        XCTAssertEqual(request.payload.command, .acquireControlLease)

        XCTAssertThrowsError(
            try adapter.makeControlRequest(command: .drain, controlToken: "token")
        ) { error in
            XCTAssertEqual(error as? V2ClientBridgeError, .authorityRequired)
        }
    }

    func testControlAdapterRequiresMatchingLiveLeaseForMutations() throws {
        let now = Date(timeIntervalSince1970: 100)
        var lease = V2ClientControlLeaseMachine()
        try lease.apply(.acquired(controlToken: "token", expiresAt: now.addingTimeInterval(30)), now: now)
        let adapter = makeAdapter(authorityState: .v2Authority, lease: lease)

        let request = try adapter.makeControlRequest(
            command: .drain,
            controlToken: "token",
            now: now
        )
        XCTAssertEqual(request.payload.command, .drain)

        XCTAssertThrowsError(
            try adapter.makeControlRequest(command: .drain, controlToken: "wrong", now: now)
        ) { error in
            XCTAssertEqual(error as? V2ClientBridgeError, .controlLeaseRequired)
        }
    }

    func testAuthorityAcquireRequiresLiveHealthyAgentStatus() {
        let healthy = V2ClientStatusProjection(
            health: V2ClientStatusHealth(
                processAlive: true,
                schedulerHealthy: true,
                controlLeaseActive: false,
                serverConnected: true
            ),
            safety: V2ClientStatusSafety(
                draining: false,
                recoveryBlocked: false,
                projectionLagging: false
            )
        )
        XCTAssertTrue(V2ClientControlSession.canAcquire(status: healthy, agentIsLive: true))
        XCTAssertFalse(V2ClientControlSession.canAcquire(status: healthy, agentIsLive: false))
        XCTAssertFalse(V2ClientControlSession.canAcquire(status: nil, agentIsLive: true))

        let occupied = V2ClientStatusProjection(
            health: V2ClientStatusHealth(
                processAlive: true,
                schedulerHealthy: true,
                controlLeaseActive: true,
                serverConnected: true
            ),
            safety: V2ClientStatusSafety(
                draining: false,
                recoveryBlocked: false,
                projectionLagging: false
            )
        )
        XCTAssertFalse(V2ClientControlSession.canAcquire(status: occupied, agentIsLive: true))
    }

    func testAuthorityAcquireRejectsUnhealthyOrDrainingAgent() {
        let draining = V2ClientStatusProjection(
            health: V2ClientStatusHealth(
                processAlive: true,
                schedulerHealthy: true,
                controlLeaseActive: false,
                serverConnected: true
            ),
            safety: V2ClientStatusSafety(
                draining: true,
                recoveryBlocked: false,
                projectionLagging: false
            )
        )
        let unhealthy = V2ClientStatusProjection(
            health: V2ClientStatusHealth(
                processAlive: true,
                schedulerHealthy: false,
                controlLeaseActive: false,
                serverConnected: true
            ),
            safety: V2ClientStatusSafety(
                draining: false,
                recoveryBlocked: false,
                projectionLagging: false
            )
        )
        XCTAssertFalse(V2ClientControlSession.canAcquire(status: draining, agentIsLive: true))
        XCTAssertFalse(V2ClientControlSession.canAcquire(status: unhealthy, agentIsLive: true))
    }

    func testPendingAuthorityReleaseDoesNotFallBackToLegacy() {
        let active = V2ClientControlLeaseState.active(
            controlToken: "not-persisted",
            expiresAt: Date().addingTimeInterval(30)
        )
        XCTAssertEqual(
            V2ClientControlSession.effectiveAuthorityState(
                explicitAuthorityEnabled: false,
                leaseState: active,
                releasePending: true
            ),
            .v2Authority
        )
        XCTAssertEqual(
            V2ClientControlSession.effectiveAuthorityState(
                explicitAuthorityEnabled: false,
                leaseState: .released,
                releasePending: false
            ),
            .legacyBroker
        )
    }

    private func makeAdapter(
        authorityState: V2ClientAuthorityState,
        lease: V2ClientControlLeaseMachine = V2ClientControlLeaseMachine()
    ) -> V2ClientControlAdapter {
        let transport = V2ClientUnixSocketTransport(
            configuration: V2ClientUnixSocketConfiguration(
                socketURL: URL(fileURLWithPath: "/tmp/ci-scope-test.sock"),
                expectedPeerUID: 1
            )
        )
        let statusAdapter = V2ClientStatusAdapter(
            transport: transport,
            session: V2ClientSessionContext(
                machineId: "machine-1",
                bootId: "boot-1",
                agentInstanceId: "agent-1",
                sessionId: "session-1",
                sessionEpoch: 2
            ),
            fencing: V2ClientFencingContext(localOwnerEpoch: 3, sessionEpoch: 2, fencingToken: "fence-1"),
            appInstanceID: "ui-1"
        )
        return V2ClientControlAdapter(
            statusAdapter: statusAdapter,
            authorityState: authorityState,
            lease: lease
        )
    }
}
#endif
