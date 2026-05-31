import Foundation
import Combine

@MainActor
final class AutomationScriptStore: ObservableObject {
    @Published private(set) var scripts: [AutomationScript] = []
    @Published var selectedScriptID: AutomationScript.ID?
    @Published private(set) var errorMessage: String?

    private let directoryURL: URL
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default) {
        self.directoryURL = Self.storageDirectory(fileManager: fileManager)
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        load()
    }

    var selectedScript: AutomationScript? {
        guard let selectedScriptID else { return nil }
        return scripts.first { $0.id == selectedScriptID }
    }

    func select(_ script: AutomationScript) {
        selectedScriptID = script.id
    }

    func createScript() {
        let script = AutomationScript.empty(uniqueID: uniqueID(base: "custom-script"))
        scripts.append(script)
        selectedScriptID = script.id
        try? save(script, replacing: nil)
    }

    func save(_ script: AutomationScript, replacing oldID: String?) throws {
        let storedScript = normalizedForSave(script)
        try AutomationScriptValidator.validateForSave(storedScript)
        try ensureUnique(storedScript.id, replacing: oldID)
        try write(storedScript)
        if let oldID, oldID != storedScript.id {
            try? FileManager.default.removeItem(at: url(for: oldID))
        }
        reloadFromDisk(selecting: storedScript.id)
    }

    func deleteSelectedScript() {
        guard let selectedScript else { return }
        guard selectedScript.defaultSeedID == nil else { return }
        try? FileManager.default.removeItem(at: url(for: selectedScript.id))
        reloadFromDisk(selecting: nil)
    }

    func resetSelectedScriptToDefault() throws {
        guard let selectedScript, let seedID = selectedScript.defaultSeedID else { return }
        let seed = try AutomationScriptSeedProvider.loadSeed(seedID)
        try write(seed)
        if selectedScript.id != seed.id {
            try? FileManager.default.removeItem(at: url(for: selectedScript.id))
        }
        reloadFromDisk(selecting: seed.id)
    }

    private func normalizedForSave(_ script: AutomationScript) -> AutomationScript {
        var storedScript = script
        if let seedID = script.defaultSeedID, seedID != script.id {
            storedScript.defaultSeedID = nil
        }
        return storedScript
    }

    private func load() {
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try seedDefaultsIfNeeded()
            reloadFromDisk(selecting: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reloadFromDisk(selecting preferredID: String?) {
        scripts = loadScriptsFromDisk().sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        selectedScriptID = preferredID ?? selectedScriptID ?? scripts.first?.id
        if selectedScriptID.flatMap({ id in scripts.first { $0.id == id } }) == nil {
            selectedScriptID = scripts.first?.id
        }
    }

    private func loadScriptsFromDisk() -> [AutomationScript] {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil) else {
            return []
        }
        return urls.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(AutomationScript.self, from: data)
        }
    }

    private func seedDefaultsIfNeeded() throws {
        for seed in try AutomationScriptSeedProvider.loadDefaultScripts() {
            if !FileManager.default.fileExists(atPath: url(for: seed.id).path) {
                try write(seed)
            }
        }
    }

    private func write(_ script: AutomationScript) throws {
        let data = try encoder.encode(script)
        try data.write(to: url(for: script.id), options: .atomic)
    }

    private func ensureUnique(_ id: String, replacing oldID: String?) throws {
        if oldID == id { return }
        guard !scripts.contains(where: { $0.id == id }) else {
            throw AutomationScriptError.duplicateScript(id)
        }
    }

    private func uniqueID(base: String) -> String {
        var index = 1
        var candidate = base
        let existing = Set(scripts.map(\.id))
        while existing.contains(candidate) {
            index += 1
            candidate = "\(base)-\(index)"
        }
        return candidate
    }

    private func url(for id: String) -> URL {
        directoryURL.appendingPathComponent("\(id).json")
    }

    private static func storageDirectory(fileManager: FileManager) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("CI Scope/Scripts", isDirectory: true)
    }
}
