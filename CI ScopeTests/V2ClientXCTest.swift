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

    func testAgentToolkitSeedRendersProfilesAndPinnedCheckScript() throws {
        let scripts = [
            try AutomationScriptSeedProvider.loadSeed("agent-toolkit"),
            AutomationScriptSeedProvider.fallbackAgentToolkitSeed(),
        ]
        XCTAssertTrue(AutomationScriptSeedProvider.defaultSeedIDs.contains("agent-toolkit"))
        let project = CIProject(
            id: "forkhorizon/demo", title: "Demo", repositoryOwner: "ForkHorizon",
            repositoryName: "Demo", repositorySlug: "ForkHorizon/Demo",
            remoteURL: "https://github.com/ForkHorizon/Demo.git")
        let sha = String(repeating: "a", count: 40)
        for script in scripts {
            XCTAssertEqual(script.variables.first(where: { $0.id == "stack_profile" })?.options, ["ts-web", "go", "python"])
            for (profile, expectedType) in [
                ("ts-web", "web-test"), ("go", "go-quality"), ("python", "python-pytest"),
            ] {
                let renderer = AutomationScriptRenderer(
                    script: script, project: project,
                    variableValues: ["gates_sha": sha, "stack_profile": profile], defaultBranch: "main")
                try renderer.validate()
                let files = try renderer.renderedFiles()
                let manifest = try XCTUnwrap(files.first { $0.id == "manifest" }?.contents)
                XCTAssertTrue(manifest.contains("\"type\" : \"\(expectedType)\""))
                XCTAssertTrue(manifest.contains("forbidden-constructs"))
                XCTAssertTrue(manifest.contains("duplicate-blocks"))
                let check = try XCTUnwrap(files.first { $0.id == "check" }?.contents)
                XCTAssertTrue(check.contains("gates_sha=\"\(sha)\""))
                XCTAssertTrue(
                    check.contains("if ! gates_status=\"$(git -C \"$gates_root\" status --porcelain --untracked-files=all)\"; then"))
                XCTAssertTrue(check.contains("Unable to verify ci-gates checkout status."))
                XCTAssertTrue(check.contains("refusing to run unpinned code"))
                XCTAssertFalse(check.contains("{{gates_sha}}"))
            }
        }
    }

    func testAgentToolkitHooksReportFailuresToAgentViaExitTwo() throws {
        let file = try XCTUnwrap(
            AutomationScriptSeedProvider.fallbackAgentToolkitSeed().files.first { $0.destinationPath == ".claude/settings.json" })
        let settings = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(file.contents.utf8)) as? [String: Any])
        let hooks = try XCTUnwrap(settings["hooks"] as? [String: [[String: Any]]])
        for event in ["PostToolUse", "Stop"] {
            let entry = try XCTUnwrap(hooks[event]?.first?["hooks"] as? [[String: Any]])
            let command = try XCTUnwrap(entry.first?["command"] as? String)
            XCTAssertTrue(command.contains("exit 2"), event)
            XCTAssertTrue(command.contains(">&2"), event)
            XCTAssertFalse(command.contains("--quiet"), event)
        }
    }

    func testManagedInstallPreservesUserHookThatRunsScriptsCheck() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let userCommand = "scripts/check --quiet # user's own hook"
        let url = root.appendingPathComponent(".claude/settings.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try #"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"scripts/check --quiet # user's own hook"}]}]}}"#
            .write(to: url, atomically: true, encoding: .utf8)
        let file = try XCTUnwrap(
            AutomationScriptSeedProvider.fallbackAgentToolkitSeed().files.first { $0.destinationPath == ".claude/settings.json" })

        try AutomationScriptManagedFiles.install([file], in: root)
        try AutomationScriptManagedFiles.remove([file], from: root)
        let settings = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(String(contentsOf: url, encoding: .utf8).utf8)) as? [String: Any])
        let hooks = try XCTUnwrap(settings["hooks"] as? [String: [[String: Any]]])
        let stopHooks = try XCTUnwrap(hooks["Stop"])
        XCTAssertEqual(stopHooks.count, 1)
        XCTAssertEqual((stopHooks[0]["hooks"] as? [[String: Any]])?.first?["command"] as? String, userCommand)
    }

    func testManagedInstallPreservesUnrecognizedClaudeHooksShape() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = #"{"hooks":{"custom":"preserve me"}}"#
        let url = root.appendingPathComponent(".claude/settings.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try original.write(to: url, atomically: true, encoding: .utf8)
        let file = try XCTUnwrap(
            AutomationScriptSeedProvider.fallbackAgentToolkitSeed().files.first { $0.destinationPath == ".claude/settings.json" })

        XCTAssertThrowsError(try AutomationScriptManagedFiles.install([file], in: root))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), original)
    }

    func testManagedInstallIsIdempotentAndRemovalPreservesUserContent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let project = CIProject(
            id: "forkhorizon/demo", title: "Demo", repositoryOwner: "ForkHorizon",
            repositoryName: "Demo", repositorySlug: "ForkHorizon/Demo",
            remoteURL: "https://github.com/ForkHorizon/Demo.git")
        let files = try AutomationScriptRenderer(
            script: AutomationScriptSeedProvider.fallbackAgentToolkitSeed(), project: project,
            variableValues: ["gates_sha": String(repeating: "b", count: 40)], defaultBranch: "main"
        ).renderedFiles()
        let agents = root.appendingPathComponent("AGENTS.md")
        try "Project-specific instructions.\n".write(to: agents, atomically: true, encoding: .utf8)
        let claude = root.appendingPathComponent(".claude/settings.json")
        try FileManager.default.createDirectory(at: claude.deletingLastPathComponent(), withIntermediateDirectories: true)
        try #"{"theme":"dark","hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo user"}]}]}}"#
            .write(to: claude, atomically: true, encoding: .utf8)
        try AutomationScriptManagedFiles.install(files, in: root)
        let firstAgents = try String(contentsOf: agents, encoding: .utf8)
        let firstClaude = try String(contentsOf: claude, encoding: .utf8)
        try AutomationScriptManagedFiles.install(files, in: root)
        XCTAssertEqual(try String(contentsOf: agents, encoding: .utf8), firstAgents)
        XCTAssertEqual(try String(contentsOf: claude, encoding: .utf8), firstClaude)
        let editedClaude = firstClaude.replacingOccurrences(
            of: AutomationScriptManagedFiles.hookMarker, with: "# user-edited-hook")
        try editedClaude.write(to: claude, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try AutomationScriptManagedFiles.install(files, in: root))
        XCTAssertThrowsError(try AutomationScriptManagedFiles.remove(files, from: root))
        try firstClaude.write(to: claude, atomically: true, encoding: .utf8)
        try AutomationScriptManagedFiles.remove(files, from: root)
        XCTAssertEqual(try String(contentsOf: agents, encoding: .utf8), "Project-specific instructions.")
        let settings = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(String(contentsOf: claude, encoding: .utf8).utf8)) as? [String: Any])
        XCTAssertEqual(settings["theme"] as? String, "dark")
        let hooks = try XCTUnwrap(settings["hooks"] as? [String: [[String: Any]]])
        XCTAssertEqual((hooks["Stop"]?.first?["hooks"] as? [[String: Any]])?.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("scripts/check").path))
    }

    func testManagedInstallRefusesModifiedFilesAndBlocks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = AutomationScriptFile(id: "check", destinationPath: "scripts/check", isExecutable: true, contents: "original\n")
        let check = root.appendingPathComponent("scripts/check")
        try FileManager.default.createDirectory(at: check.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "user edit\n".write(to: check, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try AutomationScriptManagedFiles.install([file], in: root))
        let agents = AutomationScriptFile(
            id: "agents", destinationPath: "AGENTS.md", isExecutable: false,
            contents: "\(AutomationScriptManagedFiles.agentsStart)\nManaged line.\n\(AutomationScriptManagedFiles.agentsEnd)")
        let modifiedBlock = "\(AutomationScriptManagedFiles.agentsStart)\nChanged managed line.\n\(AutomationScriptManagedFiles.agentsEnd)"
        try modifiedBlock.write(to: root.appendingPathComponent("AGENTS.md"), atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try AutomationScriptManagedFiles.install([agents], in: root))
        XCTAssertThrowsError(try AutomationScriptManagedFiles.remove([file], from: root))
    }
}
