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
    @Published var labelsText = "self-hosted, macOS, ARM64, ci-scope, ci-scope-v2" {
        didSet { persist() }
    }
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

    nonisolated static func migrateLabelsText(_ raw: String?) -> String {
        guard let raw = raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "self-hosted, macOS, ARM64, ci-scope, ci-scope-v2"
        }
        var labels =
            raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let lower = Set(labels.map { $0.lowercased() })
        if !lower.contains("ci-scope-v2") {
            labels.append("ci-scope-v2")
        }
        return labels.joined(separator: ", ")
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
            labelsText: migrateLabelsText(defaults.string(forKey: "ciScope.queue.labelsText")),
            capacity: max(1, defaults.integer(forKey: "ciScope.queue.capacity"))
        )
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
