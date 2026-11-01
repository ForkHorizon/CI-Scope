// Tests that the stack profile follows the dominant language and that an installed toolkit is recognized.
import XCTest

@testable import CI_Scope

final class DominantStackXCTest: XCTestCase {
    func testTypeScriptRepoWithAFewPythonScriptsIsTypeScript() {
        // ForkHorizon/Shardrail_Web: 350 KB TypeScript, 24 KB JavaScript, 47 KB Rust, 6 KB Python.
        let bytes = ["typescript": 349_645, "rust": 46_755, "css": 32_571, "javascript": 24_100, "python": 6_098]
        XCTAssertEqual(ProjectStackDetector.dominantLanguage(bytes), "typescript")
    }

    func testSwiftAppWithGoAgentIsSwift() {
        let bytes = ["swift": 559_712, "go": 299_992, "python": 33_800, "shell": 19_656]
        XCTAssertEqual(ProjectStackDetector.dominantLanguage(bytes), "swift")
    }

    func testRustOnlyHasNoDominantStack() {
        XCTAssertNil(ProjectStackDetector.dominantLanguage(["rust": 1_200_000, "shell": 10_000]))
        XCTAssertNil(ProjectStackDetector.dominantLanguage([:]))
    }

    func testRootPackageJSONOnlyCountsForTypeScript() {
        XCTAssertFalse(ProjectStackDetector.hasStackGate(languages: [], isUnity: false, hasRootPackageJSON: true))
        XCTAssertTrue(
            ProjectStackDetector.hasStackGate(languages: ["typescript"], isUnity: false, hasRootPackageJSON: true))
    }

    func testInstalledToolkitIsRecognizedEvenWithAManifest() {
        let types: Set<String> = ["code-linter", "python-quality", "file-roles", "test-protection"]
        XCTAssertEqual(
            RecommendedGateStatus.status(
                seedID: "agent-toolkit", hasWorkflow: false, manifestTypes: types, toolkitInstalled: true),
            .installed)
        XCTAssertEqual(
            RecommendedGateStatus.status(
                seedID: "agent-toolkit", hasWorkflow: false, manifestTypes: types, toolkitInstalled: false),
            .addViaPolicy)
    }
}
