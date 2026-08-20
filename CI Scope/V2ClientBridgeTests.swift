#if canImport(XCTest)
  import XCTest

  final class V2ClientBridgeTests: XCTestCase {
    private struct Payload: Codable, Equatable {
      let z: Int
      let a: String
    }

    private let session = V2ClientSessionContext(
      machineId: "machine-1",
      bootId: "boot-1",
      agentInstanceId: "agent-1",
      sessionId: "session-1",
      sessionEpoch: 4
    )

    private let fencing = V2ClientFencingContext(
      localOwnerEpoch: 7,
      sessionEpoch: 4,
      fencingToken: "fence-1"
    )

    func testPayloadHashIsCanonicalAndEnvelopeDetectsTampering() throws {
      let first = try V2ClientPayloadHasher.sha256(Payload(z: 1, a: "x"))
      let second = try V2ClientPayloadHasher.sha256(Payload(z: 1, a: "x"))
      XCTAssertEqual(first, second)

      let request = try V2ClientRequestEnvelope(
        payload: Payload(z: 1, a: "x"),
        session: session,
        fencing: fencing,
        requestId: "request-1"
      )
      XCTAssertNoThrow(try request.validatePayloadHash())
      XCTAssertEqual(request.requestId, "request-1")
      XCTAssertEqual(request.payloadHash, first)

      var object = try XCTUnwrap(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
      object["payload"] = ["a": "tampered", "z": 2]
      let tampered = try JSONSerialization.data(withJSONObject: object)
      let decoded = try JSONDecoder().decode(V2ClientRequestEnvelope<Payload>.self, from: tampered)
      XCTAssertThrowsError(try decoded.validatePayloadHash())
    }

    func testEnvelopeRejectsUnsupportedVersionAndMismatchedEpoch() {
      XCTAssertThrowsError(
        try V2ClientRequestEnvelope(
          payload: Payload(z: 1, a: "x"),
          session: session,
          fencing: fencing,
          protocolVersion: 3
        )
      )

      XCTAssertThrowsError(
        try V2ClientRequestEnvelope(
          payload: Payload(z: 1, a: "x"),
          session: session,
          fencing: V2ClientFencingContext(localOwnerEpoch: 7, sessionEpoch: 5)
        )
      )
    }

    func testResponseMustMatchRequestContext() throws {
      let request = try V2ClientRequestEnvelope(
        payload: Payload(z: 1, a: "x"),
        session: session,
        fencing: fencing,
        requestId: "request-1"
      )
      let response = try V2ClientResponseEnvelope(
        payload: Payload(z: 1, a: "x"),
        context: V2ClientResponseContext(
          requestId: request.requestId,
          session: session,
          fencing: V2ClientFencingContext(
            localOwnerEpoch: fencing.localOwnerEpoch,
            sessionEpoch: fencing.sessionEpoch,
            fencingToken: "stale-fence"
          )
        ),
        serverRevision: 1,
        outcome: .accepted
      )
      XCTAssertThrowsError(try response.validateAgainst(request: request))
    }

    func testStatusProjectionNeverReportsReadyWhileUnsafe() throws {
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

      let data = try JSONEncoder().encode(projection)
      let decoded = try JSONDecoder().decode(V2ClientStatusProjection.self, from: data)
      XCTAssertFalse(decoded.readyToClaim)
      XCTAssertNotNil(String(data: data, encoding: .utf8)?.range(of: "readyToClaim"))
    }

    func testStatusProjectionPreservesAgentPayloadFieldsForHashValidation() throws {
      let projection = V2ClientStatusProjection(
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
        ),
        state: "recovering",
        localEpoch: 7,
        serverSessionEpoch: 4,
        controlLeaseExpiresAt: 1_700_000_000
      )
      let data = try V2ClientPayloadHasher.canonicalData(projection)
      let decoded = try JSONDecoder().decode(V2ClientStatusProjection.self, from: data)
      XCTAssertEqual(decoded, projection)
      XCTAssertEqual(
        try V2ClientPayloadHasher.sha256(decoded), try V2ClientPayloadHasher.sha256(projection))
    }

    func testLeaseMachineDrainsAndExpiresWithoutStoppingRunner() throws {
      let now = Date(timeIntervalSince1970: 100)
      var machine = V2ClientControlLeaseMachine()
      try machine.apply(
        .acquired(controlToken: "token", expiresAt: now.addingTimeInterval(30)), now: now)
      XCTAssertTrue(machine.state.canClaim(at: now))

      try machine.apply(
        .drainRequested(controlToken: "token", deadline: now.addingTimeInterval(5)),
        now: now
      )
      XCTAssertTrue(machine.state.isDraining)
      XCTAssertFalse(machine.state.canClaim(at: now))

      machine.expireIfNeeded(at: now.addingTimeInterval(5))
      XCTAssertEqual(machine.state, .expired)
    }

    func testLeaseRejectsWrongTokenAndExpiredAcquire() {
      let now = Date(timeIntervalSince1970: 100)
      var machine = V2ClientControlLeaseMachine()
      XCTAssertThrowsError(
        try machine.apply(.acquired(controlToken: "token", expiresAt: now), now: now)
      )
      XCTAssertThrowsError(
        try machine.apply(.drainRequested(controlToken: "wrong", deadline: now), now: now)
      )
    }

    func testWireCodecFramesJSONWithBoundedSize() throws {
      let value = Payload(z: 1, a: "x")
      let frame = try V2ClientWireCodec.encodeFrame(value, maximumBytes: 100)
      XCTAssertEqual(frame.last, 0x0A)
      XCTAssertEqual(
        try V2ClientWireCodec.decodeFrame(frame, as: Payload.self, maximumBytes: 100), value)
      XCTAssertThrowsError(try V2ClientWireCodec.encodeFrame(value, maximumBytes: 2))
      XCTAssertThrowsError(
        try V2ClientWireCodec.decodeFrame(Data("{}".utf8), as: Payload.self, maximumBytes: 100))
    }
  }
#endif
