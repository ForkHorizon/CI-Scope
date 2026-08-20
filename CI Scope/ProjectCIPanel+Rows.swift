import SwiftUI

extension ProjectCIPanel {
  var runnerAccessRow: some View {
    HStack(spacing: 8) {
      Image(systemName: "point.3.filled.connected.trianglepath.dotted")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.secondary)
        .frame(width: 18)

      VStack(alignment: .leading, spacing: 2) {
        Text("MacBook runner")
          .font(.callout.weight(.semibold))
          .lineLimit(1)
        Text(isV2Managed ? "V2 Managed" : "No MacBook runner access")
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Spacer()
      if isV2Managed {
        StatusDot(state: .online)
      } else {
        Button("Attach") {
          onAttachToRunner()
        }
        .font(.caption.weight(.semibold))
        .buttonStyle(.bordered)
        .controlSize(.small)
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 7)
    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    .background(Color.secondary.opacity(0.055))
    .clipShape(RoundedRectangle(cornerRadius: 7))
  }

  var v2StatusRow: some View {
    let projection = snapshot?.v2Status
    let state: ServiceState =
      projection == nil ? .warning : (projection?.readyToClaim == true ? .online : .warning)
    let value: String
    if let projection {
      value = projection.readyToClaim ? "Agent ready" : "Agent not claim-ready"
    } else {
      value = snapshot?.v2StatusError ?? "Not configured"
    }
    return LimitedStatusRow(
      title: "V2 Agent", value: value, icon: "arrow.triangle.2.circlepath", state: state)
  }

  var v2ControlRow: some View {
    LimitedStatusRow(
      title: "V2 control",
      value: v2Control.isDisablingAuthority
        ? "Draining before fallback"
        : (v2Control.hasLiveAgentSession
          ? v2Control.authorityState.displayName : "Agent session offline"),
      icon: "lock.shield",
      state: v2Control.authorityState.allowsMutation && v2Control.hasLiveAgentSession
        ? .online : .warning
    )
  }
}

struct ProjectLiveWorkSection: View {
  let items: [RunnerWorkItem]

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      Label("Running now", systemImage: "waveform.path.ecg")
        .font(.callout.weight(.semibold))
        .foregroundStyle(Color.accentColor)

      ForEach(items) { item in
        LiveWorkCard(item: item, compact: true)
      }
    }
  }
}
