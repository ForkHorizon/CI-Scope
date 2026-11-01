import SwiftUI

extension ProjectCIPanel {
    var runnerAccessRow: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("MacBook runner")
                    .font(NothingTheme.body.weight(.semibold))
                    .lineLimit(1)
                Text(isV2Managed ? "V2 Managed" : "No MacBook runner access")
                    .font(NothingTheme.small)
                    .foregroundStyle(NothingTheme.inkDim)
                    .lineLimit(1)
            }
            Spacer()
            if isV2Managed {
                StatusDot(state: .online)
            } else {
                Button("Attach") {
                    onAttachToRunner()
                }
                .buttonStyle(.pill)
            }
        }
        .nothingRow()
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
            title: "V2 Agent", value: value, state: state)
    }

    var v2ControlRow: some View {
        LimitedStatusRow(
            title: "V2 control",
            value: v2Control.isDisablingAuthority
                ? "Draining before fallback"
                : (v2Control.hasLiveAgentSession
                    ? v2Control.authorityState.displayName : "Agent session offline"),
            state: v2Control.authorityState.allowsMutation && v2Control.hasLiveAgentSession
                ? .online : .warning
        )
    }
}

struct ProjectLiveWorkSection: View {
    let items: [RunnerWorkItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Running now").nothingCaption()

            ForEach(items) { item in
                LiveWorkCard(item: item, compact: true)
            }
        }
    }
}

struct UnifiedChecksSection: View {
    let snapshot: UnifiedChecksSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("CI Scope / Checks").nothingCaption()
                Spacer()
                if let run = snapshot.run, let url = URL(string: run.url) {
                    Link("Open run", destination: url)
                        .font(NothingTheme.small.weight(.semibold))
                        .foregroundStyle(NothingTheme.ink)
                        .underline()
                }
            }

            HStack(spacing: 6) {
                Text(snapshot.run?.compactConclusion ?? "No runs")
                Text("·")
                Text(snapshot.artifact.description)
                if let timings = snapshot.report?.timings {
                    Text("·")
                    Text("checks \(duration(timings.ordinaryMs)) · AI \(duration(timings.aiMs))")
                }
            }
            .font(NothingTheme.small)
            .foregroundStyle(NothingTheme.inkDim)

            if let report = snapshot.report {
                ForEach(report.checks) { check in
                    checkRow(CheckRowInfo(check: check))
                }
            } else {
                let pendingStatus = snapshot.run?.status == "completed" ? "unavailable" : "queued"
                ForEach(snapshot.manifest.checks) { check in
                    checkRow(CheckRowInfo(pending: check, status: pendingStatus))
                }
            }
        }
    }

    private func checkRow(_ row: CheckRowInfo) -> some View {
        HStack(spacing: 8) {
            StatusDot(state: state(status: row.status, required: row.required))
            VStack(alignment: .leading, spacing: 2) {
                Text(row.id)
                    .font(NothingTheme.body.weight(.semibold))
                Text([row.type, row.detail].compactMap { $0 }.joined(separator: " · "))
                    .font(NothingTheme.small)
                    .foregroundStyle(NothingTheme.inkDim)
                    .lineLimit(1)
            }
            Spacer()
            Text(row.durationMs.map(duration) ?? row.status)
                .font(NothingTheme.small.monospacedDigit())
                .foregroundStyle(NothingTheme.inkDim)
        }
        .nothingRow()
    }

    private func state(status: String, required: Bool?) -> ServiceState {
        switch status {
        case "passed": .online
        case "queued", "running", "skipped", "cancelled": .warning
        case "failed", "timed_out", "infra_error": required == false ? .warning : .offline
        default: .unknown
        }
    }

    private func duration(_ milliseconds: Int) -> String {
        milliseconds < 1_000 ? "\(milliseconds) ms" : "\(milliseconds / 1_000) s"
    }
}
