import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: CIQueueSettingsStore
    @ObservedObject var v2Control: V2ClientControlSession
    @AppStorage(ToastSettings.enabledKey) private var toastsEnabled = true
    @AppStorage(ToastSettings.animationKey) private var toastAnimation = ToastSettings.defaultAnimation
    @AppStorage(ToastSettings.durationKey) private var toastDuration = ToastSettings.defaultDuration
    @State private var message: String?
    @State private var isWorking = false
    @State private var confirmEmergencyStop = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                notificationsSection
                websiteSection
                agentSection
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

    private var notificationsSection: some View {
        SettingsSection(title: "Notifications") {
            SettingsRow(title: "Show notifications", hint: "CI Scope's own cards in the corner of the screen, not macOS notifications") {
                Toggle("", isOn: $toastsEnabled).labelsHidden()
            }
            SettingsRow(title: "Animation", hint: "How long a card takes to slide in and out") {
                seconds($toastAnimation, range: 0.1...1.5, step: 0.05, digits: 2)
            }
            SettingsRow(title: "Stays on screen", hint: "Alerts and failures stay 60% longer") {
                seconds($toastDuration, range: 2...20, step: 1, digits: 0)
            }
            SettingsRow(title: "Preview", hint: "Shows a card with the current settings") {
                HStack(spacing: 8) {
                    Button("Check passed") {
                        ToastCenter.shared.post(Toast(kind: .passed, title: "ForkHorizon/CI-Scope #184", detail: "All checks passed · 3f9a1c2"), preview: true)
                    }.buttonStyle(.pill)
                    Button("Alert") {
                        ToastCenter.shared.post(Toast(kind: .alert, title: "Protected files changed", detail: "ForkHorizon/CI-Scope · .github/workflows", destination: .alerts), preview: true)
                    }.buttonStyle(.pillDanger)
                }
            }
        }
    }

    private func seconds(_ value: Binding<Double>, range: ClosedRange<Double>, step: Double, digits: Int) -> some View {
        HStack(spacing: 12) {
            Slider(value: value, in: range, step: step).frame(maxWidth: 180).pointerStyle(.link)
            Text(String(format: "%.\(digits)f s", value.wrappedValue)).font(NothingTheme.small).foregroundStyle(NothingTheme.inkDim).frame(width: 52, alignment: .trailing)
        }
    }

    private var websiteSection: some View {
        SettingsSection(title: "Website") {
            SettingsRow(title: "CI Scope", hint: "Add projects and change protection here; Touch ID approves weakening") {
                Button("Open website") { NSWorkspace.shared.open(ServerLinks.site) }.buttonStyle(.pillPrimary)
            }
        }
    }

    private var agentSection: some View {
        SettingsSection(title: "Agent") {
            SettingsRow(title: "This Mac", hint: "Runs the checks for pull requests") {
                Button("Install / Restart", action: restartAgent).buttonStyle(.pillPrimary).disabled(isWorking)
            }
            SettingsRow(title: "Agent status", hint: "Read-only view of the agent on this Mac") {
                Toggle("", isOn: $store.v2StatusAdapterEnabled).labelsHidden()
            }
            SettingsRow(title: "Agent control", hint: "Take a control lease to drain, resume or stop the agent") {
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
            Text("Waiting for the agent to finish draining before the control lease is released.")
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

    private func restartAgent() {
        isWorking = true
        message = "Restarting the agent..."
        Task {
            do {
                let path = try await V2AgentLaunchManager(config: DashboardConfig())
                    .installOrUpdateLaunchAgent()
                message = "Agent installed at \(path)."
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
