// Tests that the recommender respects an existing Unified Checks manifest instead of duplicating it.
import XCTest

@testable import CI_Scope

final class RecommendedGateStatusXCTest: XCTestCase {
    /// ForkHorizon/CI-Scope: Swift + Go + Python with a signed manifest that has no go-quality.
    private let ciScopeManifest: Set<String> = [
        "code-linter", "python-quality", "swift-quality", "swift-compile",
        "file-roles", "agent-docs-stable", "test-protection",
    ]

    private func status(_ seed: String, workflow: Bool = false, manifest: Set<String>?) -> RecommendedGateStatus {
        RecommendedGateStatus.status(seedID: seed, hasWorkflow: workflow, manifestTypes: manifest)
    }

    func testChecksAlreadyInTheManifestAreNotReinstalled() {
        for seed in ["code-linter", "swift-quality-gate", "swift-compile-gate", "python-quality-gate"] {
            XCTAssertEqual(status(seed, manifest: ciScopeManifest), .inUnifiedChecks, seed)
        }
    }

    func testMissingChecksInAManifestRepoGoThroughPolicy() {
        XCTAssertEqual(status("go-quality-gate", manifest: ciScopeManifest), .addViaPolicy)
        XCTAssertEqual(status("agent-toolkit", manifest: ciScopeManifest), .addViaPolicy)
        XCTAssertFalse(RecommendedGateStatus.addViaPolicy.isSelectable)
    }

    func testReposWithoutAManifestKeepInstallingStandaloneGates() {
        XCTAssertEqual(status("go-quality-gate", manifest: nil), .installable)
        XCTAssertEqual(status("agent-toolkit", manifest: nil), .installable)
        XCTAssertEqual(status("code-linter", workflow: true, manifest: nil), .installed)
        XCTAssertTrue(RecommendedGateStatus.installable.isSelectable)
    }
}
