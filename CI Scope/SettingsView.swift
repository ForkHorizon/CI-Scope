import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: CIQueueSettingsStore
    @ObservedObject var v2Control: V2ClientControlSession
    @State private var message: String?
    @State private var isWorking = false
    @State private var confirmEmergencyStop = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                runnerSection
                v2Section
                githubIntakeSection
                gateInstallSection
                aiReviewSection
                if let message {
                    Text(message)
                        .font(NothingTheme.small.monospaced())
                        .foregroundStyle(NothingTheme.inkDim)
                        .textSelection(.enabled)
                }
            }
            .padding(22)
            .toggleStyle(NothingToggleStyle())
        }
    }

    private var runnerSection: some View {
        SettingsSection(title: "This Mac") {
            SettingsRow(title: "Server queue mode", hint: "Take jobs from the shared queue") {
                Toggle("", isOn: $store.serverModeEnabled).labelsHidden()
            }
            SettingsRow(title: "Server URL") {
                TextField("https://", text: $store.serverURL).textFieldStyle(NothingFieldStyle())
            }
            SettingsRow(title: "Local token") {
                SecureField("Bearer token", text: $store.localToken).textFieldStyle(NothingFieldStyle())
            }
            SettingsRow(title: "Machine ID") {
                TextField("", text: $store.machineID).textFieldStyle(NothingFieldStyle())
            }
            SettingsRow(title: "Machine name") {
                TextField("", text: $store.machineName).textFieldStyle(NothingFieldStyle())
            }
            SettingsRow(title: "Labels") {
                TextField("comma separated", text: $store.labelsText).textFieldStyle(NothingFieldStyle())
            }
            SettingsRow(title: "Capacity", hint: "Parallel jobs on this Mac") {
                Stepper("\(store.capacity)", value: $store.capacity, in: 1...8)
                    .font(NothingTheme.body.monospacedDigit())
            }
            SettingsRow(title: "Agent") {
                HStack(spacing: 8) {
                    Button("Test", action: runTest).buttonStyle(.pill)
                    Button("Install / Restart", action: restartAgent).buttonStyle(.pillPrimary)
                }
                .disabled(isWorking)
            }
        }
    }

    private var v2Section: some View {
        SettingsSection(title: "V2 control") {
            SettingsRow(title: "Agent status", hint: "Read-only view of the V2 Agent") {
                Toggle("", isOn: $store.v2StatusAdapterEnabled).labelsHidden()
            }
            SettingsRow(
                title: "V2 authority",
                hint: "Legacy broker stays authoritative until a control lease is acquired"
            ) {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { store.v2AuthorityEnabled },
                        set: { store.setV2AuthorityEnabled($0) }
                    )
                )
                .labelsHidden()
                .disabled(v2Control.isDisablingAuthority)
            }
            SettingsRow(title: "State") {
                Text(v2Control.authorityState.displayName)
                    .font(NothingTheme.body)
                    .foregroundStyle(v2Control.authorityState.allowsMutation ? NothingTheme.amber : NothingTheme.inkDim)
            }
            v2ControlSection
        }
    }

    @ViewBuilder private var v2ControlSection: some View {
        if v2Control.isV2ControlVisible {
            SettingsRow(title: "Controls") { v2Buttons }
            v2Notes
        }
        if let error = v2Control.lastError {
            Text(error).font(NothingTheme.small.monospaced()).foregroundStyle(NothingTheme.red)
                .textSelection(.enabled).padding(.vertical, 10)
        }
    }

    private var v2Buttons: some View {
        let locked = v2Control.isWorking || !v2Control.hasActiveLease || !v2Control.hasLiveAgentSession
        return HStack(spacing: 8) {
            Button("Acquire") { runV2 { await store.acquireV2Lease() } }
                .buttonStyle(.pillPrimary).disabled(!v2Control.canAcquire)
            Button("Renew") { runV2 { await store.renewV2Lease() } }.buttonStyle(.pill).disabled(locked)
            Button("Resume") { runV2 { await store.resumeV2() } }.buttonStyle(.pill).disabled(locked)
            Button("Drain") { runV2 { await store.drainV2() } }.buttonStyle(.pill).disabled(locked)
            Button("Stop") { confirmEmergencyStop = true }
                .buttonStyle(.pillDanger)
                .disabled(v2Control.isWorking || !v2Control.isDraining || !v2Control.hasLiveAgentSession)
        }
        .confirmationDialog(
            "Stop the V2 runner now?",
            isPresented: $confirmEmergencyStop,
            titleVisibility: .visible
        ) {
            Button("Emergency stop", role: .destructive) { runV2 { await store.emergencyStopV2() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This sends the Agent emergency-stop command. Use it only after draining.")
        }
    }

    @ViewBuilder private var v2Notes: some View {
        if v2Control.isDisablingAuthority {
            Text("Waiting for the Agent to finish draining before returning to the legacy broker.")
                .font(NothingTheme.small).foregroundStyle(NothingTheme.amber).padding(.vertical, 8)
        } else if !v2Control.hasLiveAgentSession {
            Text(
                v2Control.isConfigured
                    ? "Agent session/socket is offline. Controls are locked until a live status response arrives."
                    : "Agent session is not configured on this Mac."
            )
            .font(NothingTheme.small).foregroundStyle(NothingTheme.inkDim).padding(.vertical, 8)
        }
        if let projection = v2Control.statusProjection {
            Text(projection.readyToClaim ? "Agent ready to claim." : "Agent is not claim-ready.")
                .font(NothingTheme.small).foregroundStyle(NothingTheme.inkDim).padding(.bottom, 8)
        }
    }

    private var githubIntakeSection: some View {
        SettingsSection(title: "GitHub intake") {
            SettingsRow(title: "Webhook endpoint", hint: "Events: workflow_job") {
                Text(store.snapshot.webhookURL.isEmpty ? "Set a server URL first" : store.snapshot.webhookURL)
                    .font(NothingTheme.small.monospaced()).textSelection(.enabled)
                    .foregroundStyle(NothingTheme.ink).multilineTextAlignment(.trailing)
            }
            SettingsRow(title: "Webhook secret", hint: "Attaching a project creates its repo webhook with this secret") {
                SecureField("CI_SCOPE_GITHUB_WEBHOOK_SECRET", text: $store.webhookSecret)
                    .textFieldStyle(NothingFieldStyle())
            }
        }
    }

    private var gateInstallSection: some View {
        SettingsSection(title: "Gate installs") {
            SettingsRow(
                title: "Auto-merge gate PRs",
                hint: "Best effort: needs auto-merge allowed on the repo, otherwise the PR stays open"
            ) {
                Toggle("", isOn: $store.autoMergeGatePRs).labelsHidden()
            }
        }
    }

    private var aiReviewSection: some View {
        SettingsSection(title: "AI slop review") {
            SettingsRow(
                title: "DeepSeek key",
                hint: "Passed to the agent as DEEPSEEK_API_KEY. Empty skips the advisory step. Restart the agent after changing."
            ) {
                SecureField("sk-...", text: $store.deepSeekAPIKey).textFieldStyle(NothingFieldStyle())
            }
        }
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

    private func restartAgent() {
        isWorking = true
        message = "Restarting V2 agent..."
        Task {
            do {
                let path = try await V2AgentLaunchManager(config: DashboardConfig())
                    .installOrUpdateLaunchAgent()
                message = "V2 Agent installed at \(path)."
            } catch {
                message = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func runV2(_ operation: @escaping () async -> Void) {
        isWorking = true
        Task {
            await operation()
            isWorking = false
        }
    }
}
