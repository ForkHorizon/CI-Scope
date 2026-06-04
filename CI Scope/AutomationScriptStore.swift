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
        _ = try? save(script, replacing: nil)
    }

    @discardableResult
    func save(_ script: AutomationScript, replacing oldID: String?) throws -> AutomationScript {
        let storedScript = normalizedForSave(script, replacing: oldID)
        try AutomationScriptValidator.validateForSave(storedScript)
        try ensureUnique(storedScript.id, replacing: oldID)
        try write(storedScript)
        if let oldID, oldID != storedScript.id {
            try? FileManager.default.removeItem(at: url(for: oldID))
        }
        reloadFromDisk(selecting: storedScript.id)
        return storedScript
    }

    func deleteSelectedScript() {
        guard let selectedScript else { return }
        if let seedID = defaultSeedID(for: selectedScript) {
            try? markDefaultSeedDeleted(seedID)
        }
        try? FileManager.default.removeItem(at: url(for: selectedScript.id))
        reloadFromDisk(selecting: nil)
    }

    func resetSelectedScriptToDefault() throws {
        guard let selectedScript, let seedID = selectedScript.defaultSeedID else { return }
        let seed = try AutomationScriptSeedProvider.loadSeed(seedID)
        try write(seed)
        try unmarkDefaultSeedDeleted(seedID)
        if selectedScript.id != seed.id {
            try? FileManager.default.removeItem(at: url(for: selectedScript.id))
        }
        reloadFromDisk(selecting: seed.id)
    }

    private func normalizedForSave(_ script: AutomationScript, replacing oldID: String?) -> AutomationScript {
        var storedScript = script
        storedScript.id = storedScript.id.trimmed
        storedScript.title = storedScript.title.trimmed

        if shouldRenameIDFromTitle(storedScript, replacing: oldID) {
            let baseID = AutomationScriptNaming.slug(title: storedScript.title, fallback: storedScript.id)
            storedScript.id = uniqueID(base: baseID, replacing: oldID)
        }

        return storedScript
    }

    private func shouldRenameIDFromTitle(_ script: AutomationScript, replacing oldID: String?) -> Bool {
        guard let oldID, script.id == oldID else { return false }
        guard let previousScript = scripts.first(where: { $0.id == oldID }) else { return false }

        let oldTitleSlug = AutomationScriptNaming.slug(title: previousScript.title, fallback: oldID)
        let newTitleSlug = AutomationScriptNaming.slug(title: script.title, fallback: oldID)
        guard oldTitleSlug != newTitleSlug else { return false }

        return isGeneratedID(oldID, from: oldTitleSlug) || isPlaceholderNewScriptID(oldID)
    }

    private func isGeneratedID(_ id: String, from slug: String) -> Bool {
        if id == slug { return true }
        guard id.hasPrefix("\(slug)-") else { return false }
        return Int(id.dropFirst(slug.count + 1)) != nil
    }

    private func isPlaceholderNewScriptID(_ id: String) -> Bool {
        isGeneratedID(id, from: "custom-script")
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
            guard let script = try? decoder.decode(AutomationScript.self, from: data) else { return nil }
            let migratedScript = migratedSwiftQualityGateScript(migratedLegacyReadabilityScript(script))
            if migratedScript != script {
                try? write(migratedScript)
            }
            return migratedScript
        }
    }

    private func seedDefaultsIfNeeded() throws {
        let storedScripts = loadScriptsFromDisk()
        let deletedSeedIDs = deletedDefaultSeedIDs()
        let storedSeedIDs = Set(storedScripts.compactMap(\.defaultSeedID))
        let storedScriptIDs = Set(storedScripts.map(\.id))

        for seed in try AutomationScriptSeedProvider.loadDefaultScripts() {
            let isAlreadyStored =
                storedScriptIDs.contains(seed.id)
                || storedSeedIDs.contains(seed.id)
            if !isAlreadyStored, !deletedSeedIDs.contains(seed.id) {
                try write(seed)
            }
        }
    }

    private func defaultSeedID(for script: AutomationScript) -> String? {
        if let seedID = script.defaultSeedID {
            return seedID
        }
        return AutomationScriptSeedProvider.defaultSeedIDs.contains(script.id) ? script.id : nil
    }

    private func markDefaultSeedDeleted(_ seedID: String) throws {
        var ids = deletedDefaultSeedIDs()
        ids.insert(seedID)
        try writeDeletedDefaultSeedIDs(ids)
    }

    private func unmarkDefaultSeedDeleted(_ seedID: String) throws {
        var ids = deletedDefaultSeedIDs()
        ids.remove(seedID)
        try writeDeletedDefaultSeedIDs(ids)
    }

    private func deletedDefaultSeedIDs() -> Set<String> {
        guard
            let data = try? Data(contentsOf: deletedDefaultsURL),
            let ids = try? decoder.decode([String].self, from: data)
        else {
            return []
        }
        return Set(ids)
    }

    private func writeDeletedDefaultSeedIDs(_ ids: Set<String>) throws {
        let data = try encoder.encode(ids.sorted())
        try data.write(to: deletedDefaultsURL, options: .atomic)
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

    private func uniqueID(base: String, replacing oldID: String? = nil) -> String {
        var index = 1
        var candidate = base
        var existing = Set(scripts.map(\.id))
        if let oldID {
            existing.remove(oldID)
        }
        while existing.contains(candidate) {
            index += 1
            candidate = "\(base)-\(index)"
        }
        return candidate
    }

    private func url(for id: String) -> URL {
        directoryURL.appendingPathComponent("\(id).json")
    }

    private var deletedDefaultsURL: URL {
        directoryURL.appendingPathComponent("deleted-default-scripts.json")
    }

    private static func storageDirectory(fileManager: FileManager) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("CI Scope/Scripts", isDirectory: true)
    }
}
