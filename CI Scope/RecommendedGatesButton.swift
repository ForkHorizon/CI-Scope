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

    var body: some View {
        Button(action: detect) {
            Label(isDetecting ? "Detecting…" : "Install recommended gates", systemImage: "wand.and.stars")
                .font(.caption.weight(.semibold))
        }
        .buttonStyle(.borderedProminent)
        .disabled(isDetecting)
        .help("Detect the repository's stack and install the matching gates in one PR")
        .sheet(isPresented: $isPresented) {
            sheet
        }
    }

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recommended gates for \(project.repositorySlug)")
                .font(.headline)

            if detected.isEmpty {
                Text("No matching gates were detected for this repository.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(detected) { script in
                    gateRow(script)
                }
            }

            AutomationScriptInstallStatusBox(status: installViewModel.bundleSnapshot(for: project))

            HStack {
                Spacer()
                Button("Close") { isPresented = false }
                Button(installLabel) { install() }
                    .buttonStyle(.borderedProminent)
                    .disabled(selected.isEmpty || installViewModel.bundleSnapshot(for: project).isInstalling)
            }
        }
        .padding(18)
        .frame(width: 460)
    }

    private func gateRow(_ script: AutomationScript) -> some View {
        Toggle(isOn: binding(for: script.id)) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(script.title).font(.callout.weight(.semibold))
                    if isInstalled(script) {
                        Text("installed")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(script.summary).font(.caption).foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.checkbox)
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
            let matched = ids.compactMap { id in scripts.first { $0.defaultSeedID == id || $0.id == id } }
            detected = matched
            selected = Set(matched.filter { !isInstalled($0) }.map(\.id))
            isDetecting = false
            isPresented = true
        }
    }

    private func install() {
        let chosen = detected.filter { selected.contains($0.id) }
        installViewModel.installBundle(scripts: chosen, project: project, mode: .localBroker)
    }
}
