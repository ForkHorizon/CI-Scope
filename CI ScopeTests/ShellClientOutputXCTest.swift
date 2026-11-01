/// Regression test: a child process that fills the pipe must not be held until the timeout.
import XCTest

@testable import CI_Scope

final class ShellClientOutputXCTest: XCTestCase {
    func testLargeOutputDoesNotStallTheChildProcess() async {
        let start = Date()
        let result = await ShellClient.run(
            "head -c 400000 /dev/zero | tr '\\0' a", timeout: 15, config: DashboardConfig())
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.output.count, 400_000)
        XCTAssertLessThan(Date().timeIntervalSince(start), 10, "a full pipe used to hold the process until the timeout")
    }
}
