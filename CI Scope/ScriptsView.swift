import SwiftUI

struct ScriptsView: View {
    @ObservedObject var store: AutomationScriptStore
    @ObservedObject var installer: AutomationScriptInstallViewModel

    let projects: [CIProject]
    let selectedProject: CIProject?
    let onInstallSuccess: (CIProject) -> Void

    @State private var draft: AutomationScript?
    @State private var originalScriptID: String?
    @State private var selectedProjectID: CIProject.ID?
    @State private var variableValues: [String: String] = [:]
    @State private var runnerMode: AutomationScriptInstallMode = .localBroker
    @State private var errorMessage: String?
    @State private var editorSection: ScriptEditorSection = .details
    @State private var expandedScriptID: AutomationScript.ID?
    @State private var isEditorPresented = false
    @State private var isConfirmingDelete = false

    var body: some View {
        PanelShell(title: "Scripts Library", icon: "curlybraces.square") {
            VStack(spacing: 0) {
                toolbar

                if let currentErrorMessage {
                    ErrorBox(text: currentErrorMessage)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 10)
                }

                if store.scripts.isEmpty {
                    EmptyState(icon: "curlybraces.square", text: "No scripts saved")
                        .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(store.scripts) { script in
                                ScriptListRow(
                                    script: script,
                                    isSelected: script.id == store.selectedScriptID,
                                    isExpanded: script.id == expandedScriptID,
                                    projects: projects,
                                    selectedProjectID: $selectedProjectID,
                                    runnerMode: $runnerMode,
                                    variableValues: $variableValues,
                                    snapshot: installer.snapshot(for: script),
                                    onSelect: {
                                        select(script)
                                    },
                                    onOpenEditor: {
                                        openEditor(for: script)
                                    },
                                    onInstall: installDraft
                                )
                            }
                        }
                        .padding(10)
                    }
                }
            }
        }
        .padding(14)
        .sheet(isPresented: $isEditorPresented) {
            if let script = draftBinding {
                ScriptEditorPanel(
                    script: script,
                    section: $editorSection,
                    errorMessage: currentErrorMessage,
                    onSave: saveDraft,
                    onReset: resetDraft
                )
                .padding(14)
                .frame(width: 560, height: 640)
            } else {
                EmptyState(icon: "curlybraces.square", text: "No script selected")
                    .padding(14)
                    .frame(width: 420, height: 260)
            }
        }
        .confirmationDialog(
            "Delete Script?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button(deleteButtonTitle, role: .destructive, action: deleteSelected)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the selected script from CI Scope.")
        }
        .onAppear(perform: syncInitialState)
        .onChange(of: store.selectedScriptID) { _, _ in
            syncDraftFromStore()
        }
        .onChange(of: isEditorPresented) { _, isPresented in
            if !isPresented {
                syncDraftFromStore()
            }
        }
        .onChange(of: selectedProject?.id) { _, id in
            if selectedProjectID == nil {
                selectedProjectID = id
            }
        }
    }

    private var draftBinding: Binding<AutomationScript>? {
        guard draft != nil else { return nil }
        return Binding(
            get: { draft ?? AutomationScript.empty(uniqueID: "script") },
            set: { draft = $0 }
        )
    }

    private var currentErrorMessage: String? {
        errorMessage ?? store.errorMessage
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Text(scriptCountText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()

            Button(action: createScript) {
                Label("New", systemImage: "plus")
            }

            Button(role: .destructive) {
                isConfirmingDelete = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(store.selectedScript == nil)
        }
        .font(.caption.weight(.semibold))
        .buttonStyle(.bordered)
        .padding(10)
        .background(Color.secondary.opacity(0.035))
    }

    private var scriptCountText: String {
        store.scripts.count == 1 ? "1 script" : "\(store.scripts.count) scripts"
    }

    private var deleteButtonTitle: String {
        guard let title = store.selectedScript?.title else { return "Delete Script" }
        return "Delete \(title)"
    }

    private func syncInitialState() {
        selectedProjectID = selectedProjectID ?? selectedProject?.id ?? projects.first?.id
        syncDraftFromStore()
    }

    private func syncDraftFromStore() {
        draft = store.selectedScript
        originalScriptID = draft?.id
        variableValues = defaultValues(for: draft)
        errorMessage = nil
    }

    private func select(_ script: AutomationScript) {
        store.select(script)
        syncDraftFromStore()
        expandedScriptID = script.id
    }

    private func createScript() {
        store.createScript()
        expandedScriptID = nil
        syncDraftFromStore()
        isEditorPresented = true
    }

    private func deleteSelected() {
        expandedScriptID = nil
        isEditorPresented = false
        store.deleteSelectedScript()
        syncDraftFromStore()
    }

    private func openEditor(for script: AutomationScript) {
        if store.selectedScriptID != script.id {
            store.select(script)
        }
        syncDraftFromStore()
        expandedScriptID = script.id
        editorSection = .details
        isEditorPresented = true
    }

    private func saveDraft() {
        guard let draft else { return }
        do {
            let wasExpanded = expandedScriptID == originalScriptID
            let savedScript = try store.save(draft, replacing: originalScriptID)
            errorMessage = nil
            syncDraftFromStore()
            if wasExpanded {
                expandedScriptID = savedScript.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resetDraft() {
        do {
            try store.resetSelectedScriptToDefault()
            syncDraftFromStore()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func installDraft() {
        guard let draft else { return }
        do {
            let savedScript = try store.save(draft, replacing: originalScriptID)
            let project = projects.first { $0.id == selectedProjectID }
            installer.install(script: savedScript, project: project, variableValues: installValues(for: savedScript), mode: runnerMode) {
                if let project {
                    onInstallSuccess(project)
                }
            }
            errorMessage = nil
            syncDraftFromStore()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func defaultValues(for script: AutomationScript?) -> [String: String] {
        guard let script else { return [:] }
        return Dictionary(uniqueKeysWithValues: script.variables.map { ($0.id, $0.defaultValue) })
    }

    private func installValues(for script: AutomationScript) -> [String: String] {
        var result = defaultValues(for: script)
        variableValues.forEach { result[$0.key] = $0.value }
        return result
    }
}

enum ScriptEditorSection: String, CaseIterable, Identifiable {
    case details
    case variables
    case files

    var id: String { rawValue }

    var title: String {
        switch self {
        case .details: "Details"
        case .variables: "Variables"
        case .files: "Files"
        }
    }
}
