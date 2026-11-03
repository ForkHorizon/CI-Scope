import SwiftUI

/// One click to install the gate set that matches a repository's stack, as a
/// single pull request. Detects the stack, previews the gates (already-installed
/// ones excluded by default), and installs the selection via the shared installer.
struct RecommendedGatesButton: View {
    let project: CIProject
    let scripts: [AutomationScript]
    let isInstalled: (AutomationScript) -> Bool
    /// Check types of the repository's Unified Checks manifest, nil when it has none.
    let manifestCheckTypes: Set<String>?
    /// Switches the workspace to the Policy tab, where checks missing from a Unified Checks manifest are added.
    let openPolicy: () -> Void
    @ObservedObject var installViewModel: AutomationScriptInstallViewModel

    @State private var detected: [AutomationScript] = []
    @State private var selected: Set<String> = []
    @State private var isDetecting = false
    @State private var detectionError: String?
    @State private var isPresented = false
    @State private var stackProfile = "ts-web"
    @State private var hasStackChecks = true
    @State private var toolkitInstalled = false

    var body: some View {
        Button(action: detect) {
            Text(isDetecting ? "Detecting…" : "Install recommended gates")
        }
        .buttonStyle(.pillPrimary)
        .disabled(isDetecting)
        .help("Detect the repository's stack and install the matching gates in one PR")
        .sheet(isPresented: $isPresented) {
            sheet
        }
    }

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recommended gates").nothingDisplay(24)
            Text(project.repositorySlug).nothingCaption()

            ForEach(detected) { script in
                gateRow(script)
            }

            if let message = guidance.message {
                Text(message).font(NothingTheme.small).foregroundStyle(NothingTheme.inkDim)
            }

            AutomationScriptInstallStatusBox(status: installViewModel.bundleSnapshot(for: project))

            HStack {
                Spacer()
                Button("Close") { isPresented = false }.buttonStyle(.pill)
                switch guidance {
                case .installSelected:
                    Button(installLabel) { install() }
                        .buttonStyle(.pillPrimary)
                        .disabled(selected.isEmpty || installViewModel.bundleSnapshot(for: project).isInstalling)
                case .openPolicy:
                    Button("Open Policy") {
                        isPresented = false
                        openPolicy()
                    }
                    .buttonStyle(.pillPrimary)
                case .nothingToDo, .nothingDetected:
                    EmptyView()
                }
            }
        }
        .padding(22)
        .frame(width: 480)
        .background(NothingTheme.canvas)
    }

    private func status(of script: AutomationScript) -> RecommendedGateStatus {
        RecommendedGateStatus.status(
            seedID: script.defaultSeedID ?? script.id, hasWorkflow: isInstalled(script),
            manifestTypes: manifestCheckTypes, toolkitInstalled: toolkitInstalled)
    }

    private var guidance: RecommendedGatesGuidance {
        RecommendedGatesGuidance.guidance(for: detected.map { status(of: $0) })
    }

    /// A gate that cannot be installed here is shown as a plain row, not as a switch that looks broken.
    @ViewBuilder
    private func gateRow(_ script: AutomationScript) -> some View {
        let status = status(of: script)
        if status.isSelectable { selectableRow(script, status: status) } else { infoRow(script, status: status) }
    }

    private func infoRow(_ script: AutomationScript, status: RecommendedGateStatus) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Text(script.title).font(NothingTheme.body.weight(.semibold))
                if let label = status.label { statusLabel(label, status: status) }
            }
            Text(script.summary).font(NothingTheme.small).foregroundStyle(NothingTheme.inkDim)
        }
        .opacity(0.75)
    }

    private func statusLabel(_ label: String, status: RecommendedGateStatus) -> some View {
        Text(label)
            .font(NothingTheme.tiny.weight(.semibold))
            .foregroundStyle(status == .addViaPolicy ? NothingTheme.amber : NothingTheme.inkDim)
    }

    private func selectableRow(_ script: AutomationScript, status: RecommendedGateStatus) -> some View {
        Toggle(isOn: binding(for: script.id)) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(script.title).font(NothingTheme.body.weight(.semibold))
                    if let label = status.label { statusLabel(label, status: status) }
                }
                Text(script.summary).font(NothingTheme.small).foregroundStyle(NothingTheme.inkDim)
            }
        }
        .toggleStyle(NothingToggleStyle())
    }

    private var installLabel: String {
        selected.isEmpty ? "Install" : "Install \(selected.count) gate\(selected.count == 1 ? "" : "s")"
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { selected.contains(id) },
            set: { isOn in
                if isOn { selected.insert(id) } else { selected.remove(id) }
            }
        )
    }

    private func detect() {
        isDetecting = true
        detectionError = nil
        Task {
            let detector = ProjectStackDetector(config: DashboardConfig())
            let ids = await detector.recommendedSeedIDs(for: project)
            let choice = await detector.stackChoice(for: project)
            stackProfile = choice.profile
            hasStackChecks = choice.hasStackChecks
            toolkitInstalled = choice.toolkitInstalled
            let matched = ids.compactMap { id in scripts.first { $0.defaultSeedID == id || $0.id == id } }
            detected = matched
            selected = Set(matched.filter { status(of: $0).isSelectable }.map(\.id))
            isDetecting = false
            isPresented = true
        }
    }

    private func install() {
        let chosen = detected.filter { selected.contains($0.id) }
        installViewModel.installBundle(
            scripts: chosen, project: project, mode: .localRunner,
            variableOverrides: [
                "agent-toolkit": ["stack_profile": stackProfile, "stack_checks": hasStackChecks ? "true" : "false"]
            ])
    }
}
