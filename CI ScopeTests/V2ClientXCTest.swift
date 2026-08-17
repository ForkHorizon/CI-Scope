import Foundation
import XCTest
@testable import CI_Scope

final class V2ClientXCTest: XCTestCase {
    private let session = V2ClientSessionContext(
        machineId: "machine-1",
        bootId: "boot-1",
        agentInstanceId: "agent-1",
        sessionId: "session-1",
        sessionEpoch: 4
    )

    func testEnvelopeHashIsCanonicalAndDetectsTampering() throws {
        struct Payload: Codable, Equatable { let z: Int; let a: String }
        let payload = Payload(z: 1, a: "x")
        let request = try V2ClientRequestEnvelope(
            payload: payload,
            session: session,
            fencing: V2ClientFencingContext(localOwnerEpoch: 7, sessionEpoch: 4, fencingToken: "fence-1"),
            requestId: "request-1"
        )
        XCTAssertNoThrow(try request.validatePayloadHash())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        object["payload"] = ["a": "tampered", "z": 2]
        let decoded = try JSONDecoder().decode(
            V2ClientRequestEnvelope<Payload>.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        XCTAssertThrowsError(try decoded.validatePayloadHash())
    }

    func testLeaseMachineDrainsAndExpires() throws {
        let now = Date(timeIntervalSince1970: 100)
        var lease = V2ClientControlLeaseMachine()
        try lease.apply(.acquired(controlToken: "token", expiresAt: now.addingTimeInterval(30)), now: now)
        XCTAssertTrue(lease.state.canClaim(at: now))
        try lease.apply(.drainRequested(controlToken: "token", deadline: now.addingTimeInterval(5)), now: now)
        XCTAssertFalse(lease.state.canClaim(at: now))
        lease.expireIfNeeded(at: now.addingTimeInterval(5))
        XCTAssertEqual(lease.state, .expired)
    }

    func testStatusProjectionNeverReportsReadyWhileDraining() {
        let projection = V2ClientStatusProjection(
            health: V2ClientStatusHealth(
                processAlive: true,
                schedulerHealthy: true,
                controlLeaseActive: true,
                serverConnected: true
            ),
            safety: V2ClientStatusSafety(
                draining: true,
                recoveryBlocked: false,
                projectionLagging: false
            )
        )
        XCTAssertFalse(projection.readyToClaim)
    }

    func testAuthorityStateDefaultsToLegacyBroker() {
        let suiteName = "V2ClientXCTest.defaults"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        XCTAssertEqual(V2ClientFeature.authorityState(defaults: defaults), .legacyBroker)
        XCTAssertFalse(V2ClientFeature.statusAdapterEnabled(defaults: defaults))
    }
}
