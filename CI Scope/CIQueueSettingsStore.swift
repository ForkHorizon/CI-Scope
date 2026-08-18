import Combine
import Foundation
import Security

struct CIQueueSettingsSnapshot {
    var serverModeEnabled: Bool
    var serverURL: String
    var localToken: String
    var webhookSecret: String
    var deepSeekAPIKey: String
    var machineID: String
    var machineName: String
    var labelsText: String
    var capacity: Int

    var normalizedServerURL: String {
        serverURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    var labels: [String] {
        labelsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var webhookURL: String {
        normalizedServerURL.isEmpty ? "" : "\(normalizedServerURL)/api/ci/github/webhook"
    }
}

@MainActor
final class CIQueueSettingsStore: ObservableObject {
    @Published var serverModeEnabled = false { didSet { persist() } }
    @Published var v2StatusAdapterEnabled = false { didSet { persist() } }
    @Published private(set) var v2AuthorityEnabled = false
    @Published var serverURL = "" { didSet { persist() } }
    @Published var localToken = "" { didSet { persistSecrets() } }
    @Published var webhookSecret = "" { didSet { persistSecrets() } }
    /// Passed to the broker's launchd environment as DEEPSEEK_API_KEY, which JIT
    /// runner processes inherit — lets ci-gates' slop-review step call DeepSeek.
    /// Empty means that advisory step just skips itself (it never fails the job).
    @Published var deepSeekAPIKey = "" { didSet { persistSecrets() } }
    @Published var machineID = "" { didSet { persist() } }
    @Published var machineName = "" { didSet { persist() } }
    @Published var labelsText = "self-hosted, macOS, ARM64, ci-scope-broker" { didSet { persist() } }
    @Published var capacity = 1 {
        didSet {
            persist()
        }
    }
    @Published var autoMergeGatePRs = false { didSet { persist() } }

    nonisolated static let autoMergeDefaultsKey = "ciScope.queue.autoMergeGatePRs"

    private let defaults: UserDefaults
    let v2Control: V2ClientControlSession

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.v2Control = V2ClientControlSession(defaults: defaults)
        let snapshot = Self.snapshot(defaults: defaults)
        serverModeEnabled = snapshot.serverModeEnabled
        v2StatusAdapterEnabled = defaults.bool(forKey: V2ClientFeature.statusAdapterKey)
        v2AuthorityEnabled = defaults.bool(forKey: V2ClientFeature.explicitAuthorityEnabledKey)
        if v2AuthorityEnabled { v2StatusAdapterEnabled = true }
        serverURL = snapshot.serverURL
        localToken = snapshot.localToken
        webhookSecret = snapshot.webhookSecret
        deepSeekAPIKey = snapshot.deepSeekAPIKey
        machineID = snapshot.machineID
        machineName = snapshot.machineName
        labelsText = snapshot.labelsText
        capacity = snapshot.capacity
        autoMergeGatePRs = defaults.bool(forKey: Self.autoMergeDefaultsKey)
        v2Control.setExplicitAuthorityEnabled(v2AuthorityEnabled)
        persist()
    }

    nonisolated static func snapshot(defaults: UserDefaults = .standard) -> CIQueueSettingsSnapshot {
        let fallbackName = Host.current().localizedName ?? "Mac"
        let machineIDKey = "ciScope.queue.machineID"
        let machineID = defaults.string(forKey: machineIDKey) ?? UUID().uuidString
        if defaults.string(forKey: machineIDKey) == nil {
            defaults.set(machineID, forKey: machineIDKey)
        }
        return CIQueueSettingsSnapshot(
            serverModeEnabled: defaults.bool(forKey: "ciScope.queue.serverModeEnabled"),
            serverURL: defaults.string(forKey: "ciScope.queue.serverURL") ?? "",
            localToken: CIQueueKeychain.read(account: "localToken") ?? "",
            webhookSecret: CIQueueKeychain.read(account: "webhookSecret") ?? "",
            deepSeekAPIKey: CIQueueKeychain.read(account: "deepSeekAPIKey") ?? "",
            machineID: machineID,
            machineName: defaults.string(forKey: "ciScope.queue.machineName") ?? fallbackName,
            labelsText: defaults.string(forKey: "ciScope.queue.labelsText") ?? "self-hosted, macOS, ARM64, ci-scope-broker",
            capacity: max(1, defaults.integer(forKey: "ciScope.queue.capacity"))
        )
    }

    var snapshot: CIQueueSettingsSnapshot {
        CIQueueSettingsSnapshot(
            serverModeEnabled: serverModeEnabled,
            serverURL: serverURL,
            localToken: localToken,
            webhookSecret: webhookSecret,
            deepSeekAPIKey: deepSeekAPIKey,
            machineID: machineID,
            machineName: machineName,
            labelsText: labelsText,
            capacity: capacity
        )
    }

    var v2AuthorityState: V2ClientAuthorityState {
        v2Control.authorityState
    }

    func startV2Lifecycle() {
        v2Control.startLifecycle()
    }

    func stopV2Lifecycle() {
        v2Control.stopLifecycle()
    }

    func setV2AuthorityEnabled(_ enabled: Bool) {
        if enabled { v2StatusAdapterEnabled = true }
        v2AuthorityEnabled = enabled
        defaults.set(enabled, forKey: V2ClientFeature.explicitAuthorityEnabledKey)
        v2Control.setExplicitAuthorityEnabled(enabled)
    }

    func acquireV2Lease() async {
        await v2Control.acquire()
    }

    func renewV2Lease() async {
        await v2Control.renew()
    }

    func resumeV2() async {
        await v2Control.resume()
    }

    func drainV2() async {
        await v2Control.drain()
    }

    func emergencyStopV2() async {
        await v2Control.emergencyStop()
    }

    func testConnection() async throws -> String {
        let settings = snapshot
        guard settings.serverModeEnabled else { return "Server mode is off." }
        guard !settings.normalizedServerURL.isEmpty, let url = URL(string: "\(settings.normalizedServerURL)/api/ci/local/heartbeat") else {
            return "Server URL is missing."
        }
        guard !settings.localToken.isEmpty else { return "Local token is missing." }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(settings.localToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "machineId": settings.machineID,
            "name": settings.machineName,
            "status": "online",
            "labels": settings.labels,
            "capacity": settings.capacity,
        ])
        let (_, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (200..<300).contains(status) ? "Connected." : "Server returned HTTP \(status)."
    }

    private func persist() {
        defaults.set(serverModeEnabled, forKey: "ciScope.queue.serverModeEnabled")
        defaults.set(v2StatusAdapterEnabled, forKey: V2ClientFeature.statusAdapterKey)
        defaults.set(serverURL, forKey: "ciScope.queue.serverURL")
        defaults.set(machineID, forKey: "ciScope.queue.machineID")
        defaults.set(machineName, forKey: "ciScope.queue.machineName")
        defaults.set(labelsText, forKey: "ciScope.queue.labelsText")
        defaults.set(capacity, forKey: "ciScope.queue.capacity")
        defaults.set(autoMergeGatePRs, forKey: Self.autoMergeDefaultsKey)
    }

    private func persistSecrets() {
        CIQueueKeychain.write(localToken, account: "localToken")
        CIQueueKeychain.write(webhookSecret, account: "webhookSecret")
        CIQueueKeychain.write(deepSeekAPIKey, account: "deepSeekAPIKey")
    }
}
