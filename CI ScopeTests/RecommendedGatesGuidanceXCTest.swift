// Tests what the recommended-gates sheet tells the owner when nothing can be installed from it.
import XCTest

@testable import CI_Scope

final class RecommendedGatesGuidanceXCTest: XCTestCase {
    private func guidance(_ statuses: [RecommendedGateStatus]) -> RecommendedGatesGuidance {
        RecommendedGatesGuidance.guidance(for: statuses)
    }

    func testAnInstallableGateKeepsTheInstallButton() {
        XCTAssertEqual(guidance([.inUnifiedChecks, .installable]), .installSelected)
    }

    func testAManifestRepoWithMissingChecksPointsToThePolicyTab() {
        // The CI-Scope-Web case: code-linter and web-quality are in the manifest, the toolkit is not.
        let result = guidance([.inUnifiedChecks, .inUnifiedChecks, .addViaPolicy])
        XCTAssertEqual(result, .openPolicy)
        XCTAssertNotNil(result.message)
    }

    func testEverythingAlreadyInPlaceNeedsNothing() {
        XCTAssertEqual(guidance([.installed, .inUnifiedChecks]), .nothingToDo)
    }

    func testNoDetectedGatesSaysSo() {
        XCTAssertEqual(guidance([]), .nothingDetected)
        XCTAssertNil(guidance([.installable]).message)
    }
}
