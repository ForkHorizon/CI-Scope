import Combine
import Foundation

/// The gate definitions the app offers.
///
/// Default gates are read from the bundled seeds on every launch and are never
/// copied to disk, so they cannot go stale: renaming a gate or changing what it
/// installs takes effect immediately, with nothing to migrate. Disk holds only
/// scripts the user authored or edited — an edited default keeps its
/// `defaultSeedID` and shadows the seed until it is reset.
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
        try? write(script)
        reload(selecting: script.id)
    }

    @discardableResult
    func save(_ script: AutomationScript, replacing oldID: String?) throws -> AutomationScript {
        let storedScript = normalizedForSave(script, replacing: oldID)
        try AutomationScriptValidator.validateForSave(storedScript)
        try ensureUnique(storedScript.id, replacing: oldID)
        try write(storedScript)
        if let oldID, oldID != storedScript.id {
            removeStoredFile(for: oldID)
        }
        reload(selecting: storedScript.id)
        return storedScript
    }

    func deleteSelectedScript() {
        guard let selectedScript else { return }
        if let seedID = seedID(for: selectedScript) {
            try? markDefaultSeedDeleted(seedID)
        }
        removeStoredFile(for: selectedScript.id)
        reload(selecting: nil)
    }

    /// Drops the user's edits so the gate comes from the bundled seed again.
    func resetSelectedScriptToDefault() throws {
        guard let selectedScript, let seedID = seedID(for: selectedScript) else { return }
        removeStoredFile(for: selectedScript.id)
        try unmarkDefaultSeedDeleted(seedID)
        let seed = try AutomationScriptSeedProvider.loadSeed(seedID)
        reload(selecting: seed.id)
    }

    private func load() {
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            reload(selecting: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reload(selecting preferredID: String?) {
        scripts = (userScripts() + availableSeeds())
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        selectedScriptID = preferredID ?? selectedScriptID ?? scripts.first?.id
        if selectedScriptID.flatMap({ id in scripts.first { $0.id == id } }) == nil {
            selectedScriptID = scripts.first?.id
        }
    }

    private func userScripts() -> [AutomationScript] {
        let contents = try? FileManager.default.contentsOfDirectory(
            at: directoryURL, includingPropertiesForKeys: nil)
        return (contents ?? []).compactMap { url in
            guard url.pathExtension == "json", url.lastPathComponent != Self.deletedDefaultsFileName
            else { return nil }
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(AutomationScript.self, from: data)
        }
    }

    /// Seeds the user has neither hidden nor taken over with an edited copy.
    private func availableSeeds() -> [AutomationScript] {
        let stored = userScripts()
        let shadowed = Set(stored.compactMap(\.defaultSeedID)).union(stored.map(\.id))
        let deleted = deletedDefaultSeedIDs()
        // Loaded one at a time so a single unreadable seed hides that gate
        // instead of every gate.
        return AutomationScriptSeedProvider.defaultSeedIDs
            .filter { !shadowed.contains($0) && !deleted.contains($0) }
            .compactMap { try? AutomationScriptSeedProvider.loadSeed($0) }
    }

    private func seedID(for script: AutomationScript) -> String? {
        if let seedID = script.defaultSeedID,
            AutomationScriptSeedProvider.defaultSeedIDs.contains(seedID)
        {
            return seedID
        }
        return AutomationScriptSeedProvider.defaultSeedIDs.contains(script.id) ? script.id : nil
    }

    private func normalizedForSave(_ script: AutomationScript, replacing oldID: String?)
        -> AutomationScript
    {
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
        try data.write(to: try url(for: script.id), options: .atomic)
    }

    private func removeStoredFile(for id: String) {
        if let scriptURL = try? url(for: id) {
            try? FileManager.default.removeItem(at: scriptURL)
        }
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

    private func url(for id: String) throws -> URL {
        try directoryURL.safelyAppendingPathComponent("\(id).json")
    }

    private static let deletedDefaultsFileName = "deleted-default-scripts.json"

    private var deletedDefaultsURL: URL {
        try! directoryURL.safelyAppendingPathComponent(Self.deletedDefaultsFileName)
    }

    private static func storageDirectory(fileManager: FileManager) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return try! base.safelyAppendingPathComponent("CI Scope/Scripts", isDirectory: true)
    }
}
