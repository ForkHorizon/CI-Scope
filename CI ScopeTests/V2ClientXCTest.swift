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
        struct Payload: Codable, Equatable {
            let z: Int
            let a: String
        }
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
        defaults.set(false, forKey: V2ClientFeature.statusAdapterKey)
        XCTAssertEqual(V2ClientFeature.authorityState(defaults: defaults), .legacyBroker)
        XCTAssertFalse(V2ClientFeature.statusAdapterEnabled(defaults: defaults))
    }

    func testUnifiedManifestRejectsUnknownVersionAndDuplicateIDs() throws {
        XCTAssertThrowsError(
            try CIScopeManifest.decode(Data(#"{"version":2,"checks":[{"id":"lint","type":"code-linter"}]}"#.utf8))
        ) { error in
            XCTAssertEqual(
                error.localizedDescription, UnifiedChecksError.unsupportedManifestVersion.localizedDescription)
        }
        XCTAssertThrowsError(
            try CIScopeManifest.decode(
                Data(#"{"version":1,"checks":[{"id":"lint","type":"code-linter"},{"id":"lint","type":"python-quality"}]}"#.utf8)
            )
        ) { error in
            XCTAssertEqual(error.localizedDescription, UnifiedChecksError.duplicateCheckID.localizedDescription)
        }
    }

    func testUnifiedReportRequiresMatchingRunIdentity() throws {
        let project = CIProject(
            id: "forkhorizon/soma", title: "Soma", repositoryOwner: "ForkHorizon",
            repositoryName: "Soma", repositorySlug: "ForkHorizon/Soma",
            remoteURL: "https://github.com/ForkHorizon/Soma.git")
        let run = GitHubRun(
            databaseId: 42, attempt: 2, status: "completed", conclusion: "success",
            displayTitle: "Unified", workflowName: "CI Scope", headBranch: "feature",
            headSha: "abc123", event: "pull_request", createdAt: "", updatedAt: "",
            url: "https://github.com/ForkHorizon/Soma/actions/runs/42")
        let valid = Data(
            #"{"version":1,"status":"passed","head":"abc123","run":{"repository":"ForkHorizon/Soma","run_id":"42","attempt":"2","checked_sha":"merge456"},"checks":[{"id":"lint","type":"code-linter","status":"passed","required":true,"duration_ms":10}],"timings":{"ordinary_ms":10,"ai_ms":0}}"#
                .utf8)
        let report = try UnifiedChecksReport.decode(valid, project: project, run: run)
        XCTAssertEqual(report.checks.first?.durationMs, 10)

        let wrongAttempt = Data(
            #"{"version":1,"status":"passed","head":"abc123","run":{"repository":"ForkHorizon/Soma","run_id":"42","attempt":"1","checked_sha":"merge456"},"checks":[]}"#
                .utf8)
        XCTAssertThrowsError(
            try UnifiedChecksReport.decode(wrongAttempt, project: project, run: run)
        ) { error in
            XCTAssertEqual(error.localizedDescription, UnifiedChecksError.reportIdentityMismatch.localizedDescription)
        }
    }

    func testUnifiedChecksSeedRendersPinnedWorkflowAndManifest() throws {
        XCTAssertTrue(AutomationScriptSeedProvider.defaultSeedIDs.contains("ci-scope-unified-checks"))
        let script = AutomationScriptSeedProvider.fallbackUnifiedChecksSeed()
        let project = CIProject(
            id: "forkhorizon/soma", title: "Soma", repositoryOwner: "ForkHorizon",
            repositoryName: "Soma", repositorySlug: "ForkHorizon/Soma",
            remoteURL: "https://github.com/ForkHorizon/Soma.git")
        let sha = String(repeating: "a", count: 40)
        let renderer = AutomationScriptRenderer(
            script: script,
            project: project,
            variableValues: ["gates_sha": sha],
            defaultBranch: "main")

        try renderer.validate()
        let files = try renderer.renderedFiles()
        XCTAssertEqual(Set(files.map(\.destinationPath)), [".ci-scope.json", ".github/workflows/ci-scope-checks.yml"])
        let workflow = try XCTUnwrap(files.first { $0.id == "workflow" }?.contents)
        XCTAssertTrue(workflow.contains("CI_SCOPE_GATES_SHA: \(sha)"))
        XCTAssertTrue(workflow.contains("git show \"$BASE_SHA:.ci-scope.json\""))
        XCTAssertTrue(workflow.contains("EVENT_NAME\" == \"pull_request\" || \"$EVENT_NAME\" == \"merge_group\""))
        XCTAssertTrue(workflow.contains("--config \"${{ steps.policy.outputs.config }}\""))
        XCTAssertTrue(workflow.contains("unsafe policy symlink"))
        XCTAssertTrue(workflow.contains("target.resolve(strict=False) != target"))
        XCTAssertFalse(workflow.contains("{{gates_sha}}"))
        XCTAssertNoThrow(
            try JSONSerialization.jsonObject(
                with: Data(try XCTUnwrap(files.first { $0.id == "manifest" }?.contents).utf8)))
    }

    func testUnifiedChecksSeedRejectsFloatingOrMalformedGatesRef() {
        let script = AutomationScriptSeedProvider.fallbackUnifiedChecksSeed()
        let project = CIProject(
            id: "forkhorizon/soma", title: "Soma", repositoryOwner: "ForkHorizon",
            repositoryName: "Soma", repositorySlug: "ForkHorizon/Soma",
            remoteURL: "https://github.com/ForkHorizon/Soma.git")
        let renderer = AutomationScriptRenderer(
            script: script,
            project: project,
            variableValues: ["gates_sha": "main"],
            defaultBranch: "main")

        XCTAssertThrowsError(try renderer.validate())
    }
}
