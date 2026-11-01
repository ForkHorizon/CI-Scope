import SwiftUI

/// One click to install the gate set that matches a repository's stack, as a
/// single pull request. Detects the stack, previews the gates (already-installed
/// ones excluded by default), and installs the selection via the shared installer.
struct RecommendedGatesButton: View {
    let project: CIProject
    let scripts: [AutomationScript]
    let isInstalled: (AutomationScript) -> Bool
    @ObservedObject var installViewModel: AutomationScriptInstallViewModel

    @State private var detected: [AutomationScript] = []
    @State private var selected: Set<String> = []
    @State private var isDetecting = false
    @State private var detectionError: String?
    @State private var isPresented = false
    @State private var stackProfile = "ts-web"

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

            if detected.isEmpty {
                Text("No matching gates were detected for this repository.")
                    .font(NothingTheme.body)
                    .foregroundStyle(NothingTheme.inkDim)
            } else {
                ForEach(detected) { script in
                    gateRow(script)
                }
            }

            AutomationScriptInstallStatusBox(status: installViewModel.bundleSnapshot(for: project))

            HStack {
                Spacer()
                Button("Close") { isPresented = false }.buttonStyle(.pill)
                Button(installLabel) { install() }
                    .buttonStyle(.pillPrimary)
                    .disabled(selected.isEmpty || installViewModel.bundleSnapshot(for: project).isInstalling)
            }
        }
        .padding(22)
        .frame(width: 480)
        .background(NothingTheme.canvas)
    }

    private func gateRow(_ script: AutomationScript) -> some View {
        Toggle(isOn: binding(for: script.id)) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(script.title).font(NothingTheme.body.weight(.semibold))
                    if isInstalled(script) {
                        Text("installed")
                            .font(NothingTheme.tiny.weight(.semibold))
                            .foregroundStyle(NothingTheme.inkDim)
                    }
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
            stackProfile = await detector.stackProfile(for: project)
            let matched = ids.compactMap { id in scripts.first { $0.defaultSeedID == id || $0.id == id } }
            detected = matched
            selected = Set(matched.filter { !isInstalled($0) }.map(\.id))
            isDetecting = false
            isPresented = true
        }
    }

    private func install() {
        let chosen = detected.filter { selected.contains($0.id) }
        installViewModel.installBundle(
            scripts: chosen, project: project, mode: .localRunner,
            variableOverrides: ["agent-toolkit": ["stack_profile": stackProfile]])
    }
}
