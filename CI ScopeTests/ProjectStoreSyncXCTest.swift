// The sidebar mirrors the server's registered projects.
import XCTest

@testable import CI_Scope

@MainActor
final class ProjectStoreSyncXCTest: XCTestCase {
    private func store() -> ProjectStore { ProjectStore(defaults: UserDefaults(suiteName: "sync-\(UUID())")!) }

    func testSyncDropsUnregisteredAndAddsRegisteredKeepingSelection() throws {
        let store = store()
        _ = try store.addProject(from: "ForkHorizon/Old")
        _ = try store.addProject(from: "ForkHorizon/Keep")
        store.select(store.projects[1])
        store.sync(with: ["forkhorizon/keep", "ForkHorizon/New"])
        XCTAssertEqual(store.projects.map(\.repositorySlug), ["ForkHorizon/Keep", "ForkHorizon/New"])
        XCTAssertEqual(store.selectedProject?.repositorySlug, "ForkHorizon/Keep")
    }

    func testSelectionFallsBackAndEmptyServerListEmptiesTheSidebar() throws {
        let store = store()
        _ = try store.addProject(from: "ForkHorizon/Gone")
        store.sync(with: ["ForkHorizon/New"])
        XCTAssertEqual(store.selectedProject?.repositorySlug, "ForkHorizon/New")
        store.sync(with: [])
        XCTAssertTrue(store.projects.isEmpty)
        XCTAssertNil(store.selectedProject)
    }
}
