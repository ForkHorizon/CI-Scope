import Combine
import Foundation

/// State of the Test protection tab: open alerts from accepted commits, the owner's decision history,
/// and the Touch ID-gated approve / revert actions. Mute is local to this Mac and needs no login.
@MainActor
final class TestProtectionViewModel: ObservableObject {
    @Published private(set) var alerts: [TestAlert] = []
    @Published private(set) var history: [TestDecision] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isActing = false
    @Published var selectedID: TestAlert.ID?
    @Published var message: String?

    var scanner = TestProtectionService(github: PolicyGitHub(config: DashboardConfig()))
    var consent = TestConsentClient()
    var server = PolicyServerClient()
    var revert = TestRevertService(config: DashboardConfig())
    private let cache = TestScanCache()
    private let defaults = UserDefaults.standard
    private var hasLoaded = false

    var openAlerts: [TestAlert] {
        alerts.filter { $0.isOpen() && !isMutedLocally($0) }
            .sorted { ($0.severity, $0.committedAt) > ($1.severity, $1.committedAt) }
    }

    var openCount: Int { openAlerts.count }
    var selected: TestAlert? { openAlerts.first { $0.id == selectedID } ?? openAlerts.first }

    func load(projects: [CIProject]) async {
        isLoading = true
        defer { isLoading = false }
        let readToken = try? await PolicyAuthorizer.readToken()
        var found: [TestAlert] = []
        var recorded: [TestDecision] = []
        var failures = 0
        for project in projects {
            let slug = project.repositorySlug
            do {
                var repositoryAlerts = try await scanner.alerts(repository: slug, cache: cache)
                if let readToken {
                    let decisions = try await consent.decisions(repository: slug, readToken: readToken)
                    recorded += decisions
                    for index in repositoryAlerts.indices {
                        repositoryAlerts[index].decision = decisions.first { $0.sha == repositoryAlerts[index].sha }
                    }
                }
                found += repositoryAlerts
            } catch {
                failures += 1
                found += alerts.filter { $0.repository == slug }
            }
        }
        alerts = found
        history = recorded.sorted { $0.decidedAt > $1.decidedAt }
        message = failures == 0 ? nil : "Couldn't check \(failures) repo(s); showing the last known alerts."
        if readToken == nil { message = "Couldn't read the policy token from the server, so decisions aren't shown." }
        notifyNewHighAlerts()
    }

    func approve(_ alert: TestAlert) async {
        await act("approve the changed test in \(alert.repository) \(alert.shortSHA)") { [self] admin in
            let path = alert.findings.first?.path
            try await consent.record(
                TestDecisionDraft(repository: alert.repository, sha: alert.sha, decision: "approved", path: path),
                admin: admin)
        }
    }

    func revertAlert(_ alert: TestAlert) async {
        await act("record the revert of \(alert.repository) \(alert.shortSHA)") { [self] admin in
            let url = try await revert.openRevertPullRequest(alert)
            try await consent.record(
                TestDecisionDraft(repository: alert.repository, sha: alert.sha, decision: "reverted", note: url),
                admin: admin)
            message = "Opened \(url)"
        }
    }

    func mute(_ alert: TestAlert, hours: Double = 24) {
        var mutes = defaults.dictionary(forKey: Self.muteKey) as? [String: Double] ?? [:]
        mutes[alert.id] = Date().addingTimeInterval(hours * 3600).timeIntervalSince1970
        defaults.set(mutes, forKey: Self.muteKey)
        objectWillChange.send()
    }

    private static let muteKey = "testProtection.mutes"
    private static let notifiedKey = "testProtection.notified"

    private func isMutedLocally(_ alert: TestAlert) -> Bool {
        let mutes = defaults.dictionary(forKey: Self.muteKey) as? [String: Double] ?? [:]
        return (mutes[alert.id] ?? 0) > Date().timeIntervalSince1970
    }

    /// One Touch ID prompt, then the server confirms the admin login before anything is written.
    private func act(_ reason: String, _ body: @escaping ((user: String, password: String)) async throws -> Void) async {
        guard !isActing else { return }
        isActing = true
        defer { isActing = false }
        message = nil
        do {
            let password = try await PolicyAuthorizer.adminPassword(reason: reason)
            let user = try await scanner.github.login()
            try await server.verifyAdmin(user: user, password: password)
            try await body((user, password))
        } catch {
            message = error.localizedDescription
        }
        await reloadDecisions()
    }

    private func reloadDecisions() async {
        guard let readToken = try? await PolicyAuthorizer.readToken() else { return }
        for repository in Set(alerts.map(\.repository)) {
            guard let decisions = try? await consent.decisions(repository: repository, readToken: readToken) else {
                continue
            }
            for index in alerts.indices where alerts[index].repository == repository {
                alerts[index].decision = decisions.first { $0.sha == alerts[index].sha }
            }
            history = (history.filter { $0.repository != repository } + decisions).sorted { $0.decidedAt > $1.decidedAt }
        }
    }

    private func notifyNewHighAlerts() {
        var notified = Set(defaults.stringArray(forKey: Self.notifiedKey) ?? [])
        defer { defaults.set(Array(notified.suffix(500)), forKey: Self.notifiedKey) }
        let fresh = openAlerts.filter { $0.severity == .high && !notified.contains($0.id) }
        // The first load only records what already exists, so opening the app doesn't replay old alerts.
        if hasLoaded { fresh.forEach { NotificationManager.shared.notifyTestAlert($0) } }
        hasLoaded = true
        fresh.forEach { notified.insert($0.id) }
    }
}
