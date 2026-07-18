import Combine
import Foundation
import Security

struct CIQueueSettingsSnapshot {
    var serverModeEnabled: Bool
    var serverURL: String
    var localToken: String
    var webhookSecret: String
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
    @Published var serverURL = "" { didSet { persist() } }
    @Published var localToken = "" { didSet { persistSecrets() } }
    @Published var webhookSecret = "" { didSet { persistSecrets() } }
    @Published var machineID = "" { didSet { persist() } }
    @Published var machineName = "" { didSet { persist() } }
    @Published var labelsText = "self-hosted, macOS, ARM64, ci-scope-broker" { didSet { persist() } }
    @Published var capacity = 1 {
        didSet {
            persist()
        }
    }
    @Published var autoMergeGatePRs = false { didSet { persist() } }

    static let autoMergeDefaultsKey = "ciScope.queue.autoMergeGatePRs"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let snapshot = Self.snapshot(defaults: defaults)
        serverModeEnabled = snapshot.serverModeEnabled
        serverURL = snapshot.serverURL
        localToken = snapshot.localToken
        webhookSecret = snapshot.webhookSecret
        machineID = snapshot.machineID
        machineName = snapshot.machineName
        labelsText = snapshot.labelsText
        capacity = snapshot.capacity
        autoMergeGatePRs = defaults.bool(forKey: Self.autoMergeDefaultsKey)
        persist()
    }

    static func snapshot(defaults: UserDefaults = .standard) -> CIQueueSettingsSnapshot {
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
            machineID: machineID,
            machineName: machineName,
            labelsText: labelsText,
            capacity: capacity
        )
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
    }
}

enum CIQueueKeychain {
    private static let service = "com.ForkHorizon.CI-Scope.queue"

    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard
            SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
            let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ value: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty, let data = value.data(using: .utf8) else { return }
        var item = query
        item[kSecValueData as String] = data
        SecItemAdd(item as CFDictionary, nil)
    }
}
