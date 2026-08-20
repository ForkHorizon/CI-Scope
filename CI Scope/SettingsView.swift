import SwiftUI

struct SettingsView: View {
  @ObservedObject var store: CIQueueSettingsStore
  @ObservedObject var v2Control: V2ClientControlSession
  @State private var message: String?
  @State private var isWorking = false
  @State private var confirmEmergencyStop = false

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

      Toggle("Enable V2 Agent status (read-only)", isOn: $store.v2StatusAdapterEnabled)
        .font(.callout.weight(.semibold))

      Toggle(
        "Enable V2 authority (explicit)",
        isOn: Binding(
          get: { store.v2AuthorityEnabled },
          set: { store.setV2AuthorityEnabled($0) }
        )
      )
      .font(.callout.weight(.semibold))
      .disabled(v2Control.isDisablingAuthority)

      v2ControlSection

      Text(
        "Legacy broker remains authoritative by default. Enabling V2 only opts in this app; authority starts after a successful control-lease acquisition."
      )
      .font(.caption)
      .foregroundStyle(.secondary)

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
          restartAgent()
        } label: {
          Label("Install / Restart Agent", systemImage: "arrow.clockwise")
        }
        .disabled(isWorking)
      }
      .buttonStyle(.bordered)
    }
    .padding(10)
    .background(Color.secondary.opacity(0.055))
    .clipShape(RoundedRectangle(cornerRadius: 8))
  }

  private var v2ControlSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      LabeledContent("V2 control") {
        Text(v2Control.authorityState.displayName)
          .font(.caption.weight(.semibold))
          .foregroundStyle(v2Control.authorityState.allowsMutation ? .orange : .secondary)
      }

      if v2Control.isV2ControlVisible {
        HStack(spacing: 8) {
          Button("Acquire lease") {
            runV2 { await store.acquireV2Lease() }
          }
          .disabled(!v2Control.canAcquire)

          Button("Renew") {
            runV2 { await store.renewV2Lease() }
          }
          .disabled(
            v2Control.isWorking || !v2Control.hasActiveLease || !v2Control.hasLiveAgentSession)

          Button("Resume") {
            runV2 { await store.resumeV2() }
          }
          .disabled(
            v2Control.isWorking || !v2Control.hasActiveLease || !v2Control.hasLiveAgentSession)

          Button("Drain") {
            runV2 { await store.drainV2() }
          }
          .disabled(
            v2Control.isWorking || !v2Control.hasActiveLease || !v2Control.hasLiveAgentSession)

          Button("Emergency stop", role: .destructive) {
            confirmEmergencyStop = true
          }
          .disabled(v2Control.isWorking || !v2Control.isDraining || !v2Control.hasLiveAgentSession)
        }
        .buttonStyle(.bordered)

        if v2Control.isDisablingAuthority {
          Text("Waiting for the Agent to finish draining before returning to the legacy broker.")
            .font(.caption)
            .foregroundStyle(.orange)
        } else if !v2Control.hasLiveAgentSession {
          Text(
            v2Control.isConfigured
              ? "Agent session/socket is offline. Authority controls are locked until a live status response arrives."
              : "Agent session is not configured on this Mac."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }

        if let projection = v2Control.statusProjection {
          Text(projection.readyToClaim ? "Agent ready to claim." : "Agent is not claim-ready.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      if let error = v2Control.lastError {
        Text(error)
          .font(.caption.monospaced())
          .foregroundStyle(.red)
          .textSelection(.enabled)
      }
    }
    .confirmationDialog(
      "Stop the V2 runner now?",
      isPresented: $confirmEmergencyStop,
      titleVisibility: .visible
    ) {
      Button("Emergency stop", role: .destructive) {
        runV2 { await store.emergencyStopV2() }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This sends the Agent emergency-stop command. Use it only after draining.")
    }
  }

  private var githubIntakeSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label("GitHub Intake", systemImage: "arrow.down.forward.circle")
        .font(.callout.weight(.semibold))

      Text(
        store.snapshot.webhookURL.isEmpty
          ? "Set a server URL to get the webhook endpoint." : store.snapshot.webhookURL
      )
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
        SecureField(
          "Must match CI_SCOPE_GITHUB_WEBHOOK_SECRET on the Worker", text: $store.webhookSecret
        )
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
        "Passed to the agent as DEEPSEEK_API_KEY, so JIT runners can call it for ci-gates' advisory slop-review step. Empty means that step just skips itself — it never blocks a merge either way. Restart the agent after changing this."
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
