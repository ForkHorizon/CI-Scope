import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: CIQueueSettingsStore
    @State private var message: String?
    @State private var isWorking = false

    var body: some View {
        PanelShell(title: "Settings", icon: "gearshape") {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    localComputerSection
                    githubIntakeSection
                    gateInstallSection
                    aiReviewSection
                    if let message {
                        Text(message)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .padding(12)
            }
        }
        .padding(14)
    }

    private var localComputerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Server queue mode", isOn: $store.serverModeEnabled)
                .font(.callout.weight(.semibold))

            LabeledTextField(title: "Server URL", text: $store.serverURL)

            HStack(spacing: 8) {
                Text("Local token")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 92, alignment: .leading)
                SecureField("Bearer token", text: $store.localToken)
                    .textFieldStyle(.roundedBorder)
            }

            LabeledTextField(title: "Machine ID", text: $store.machineID)
            LabeledTextField(title: "Machine name", text: $store.machineName)
            LabeledTextField(title: "Labels", text: $store.labelsText)

            Stepper("Capacity: \(store.capacity)", value: $store.capacity, in: 1...8)

            HStack {
                Button {
                    runTest()
                } label: {
                    Label("Test", systemImage: "network")
                }
                .disabled(isWorking)

                Button {
                    restartBroker()
                } label: {
                    Label("Install / Restart Broker", systemImage: "arrow.clockwise")
                }
                .disabled(isWorking)
            }
            .buttonStyle(.bordered)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var githubIntakeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("GitHub Intake", systemImage: "arrow.down.forward.circle")
                .font(.callout.weight(.semibold))

            Text(store.snapshot.webhookURL.isEmpty ? "Set a server URL to get the webhook endpoint." : store.snapshot.webhookURL)
                .font(.caption.monospaced())
                .textSelection(.enabled)

            Text("Events: workflow_job")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text("Webhook secret")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 92, alignment: .leading)
                SecureField("Must match CI_SCOPE_GITHUB_WEBHOOK_SECRET on the Worker", text: $store.webhookSecret)
                    .textFieldStyle(.roundedBorder)
            }

            Text("Attaching a project auto-creates its repo webhook (if missing) using this secret.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var gateInstallSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Gate installs", systemImage: "checklist")
                .font(.callout.weight(.semibold))

            Toggle("Auto-merge gate PRs when checks pass", isOn: $store.autoMergeGatePRs)

            Text(
                "Enables GitHub auto-merge on PRs this app opens, so gate installs land once their checks pass. Best effort — needs auto-merge allowed on the repo; otherwise the PR stays open for you to merge."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var aiReviewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("AI slop review", systemImage: "sparkles")
                .font(.callout.weight(.semibold))

            HStack(spacing: 8) {
                Text("DeepSeek key")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 92, alignment: .leading)
                SecureField("sk-...", text: $store.deepSeekAPIKey)
                    .textFieldStyle(.roundedBorder)
            }

            Text(
                "Passed to the broker as DEEPSEEK_API_KEY, so JIT runners can call it for ci-gates' advisory slop-review step. Empty means that step just skips itself — it never blocks a merge either way. Restart the broker after changing this."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func runTest() {
        isWorking = true
        message = "Testing..."
        Task {
            do {
                message = try await store.testConnection()
            } catch {
                message = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func restartBroker() {
        isWorking = true
        message = "Restarting broker..."
        Task {
            do {
                let path = try await LocalBrokerService(config: DashboardConfig()).installOrUpdateLaunchAgent()
                message = "Broker installed at \(path)."
            } catch {
                message = error.localizedDescription
            }
            isWorking = false
        }
    }
}
