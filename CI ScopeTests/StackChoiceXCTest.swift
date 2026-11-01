// Tests that repos without a matching stack gate get a manifest with only the universal checks.
import XCTest

@testable import CI_Scope

final class StackChoiceXCTest: XCTestCase {
    func testRustWorkspaceWithSubPackageTypeScriptHasNoStackGate() {
        // ForkHorizon/Shardrail_Core: Rust, TypeScript only under packages/*, no root package.json.
        XCTAssertFalse(
            ProjectStackDetector.hasStackGate(
                languages: ["rust", "typescript", "shell"], isUnity: false, hasRootPackageJSON: false))
    }

    func testKnownStacksHaveAStackGate() {
        XCTAssertTrue(
            ProjectStackDetector.hasStackGate(languages: ["typescript"], isUnity: false, hasRootPackageJSON: true))
        XCTAssertTrue(
            ProjectStackDetector.hasStackGate(languages: ["go"], isUnity: false, hasRootPackageJSON: false))
        XCTAssertTrue(
            ProjectStackDetector.hasStackGate(languages: ["python"], isUnity: false, hasRootPackageJSON: false))
        XCTAssertTrue(
            ProjectStackDetector.hasStackGate(languages: ["swift"], isUnity: false, hasRootPackageJSON: false))
        XCTAssertTrue(
            ProjectStackDetector.hasStackGate(languages: ["c#"], isUnity: true, hasRootPackageJSON: false))
    }

    func testManifestWithoutStackChecksKeepsOnlyUniversalChecks() {
        let manifest = AutomationScriptSeedProvider.agentToolkitManifest("ts-web", includeStackChecks: false)
        XCTAssertFalse(manifest.contains("web-quality"))
        XCTAssertFalse(manifest.contains("web-test"))
        for id in ["code-linter", "file-roles", "agent-docs-stable", "test-protection"] {
            XCTAssertTrue(manifest.contains("\"\(id)\""), id)
        }
        XCTAssertTrue(AutomationScriptSeedProvider.agentToolkitManifest("ts-web").contains("web-quality"))
    }
}
