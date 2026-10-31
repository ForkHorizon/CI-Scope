import Foundation

enum AutomationScriptManagedFiles {
    static let agentsStart = "<!-- >>> ci-scope agent toolkit >>> -->"
    static let agentsEnd = "<!-- <<< ci-scope agent toolkit <<< -->"
    static let hookMarker = "# ci-scope-agent-toolkit"

    static func install(_ files: [AutomationScriptFile], in root: URL) throws {
        for file in files {
            let url = try root.safelyAppendingPathComponent(file.destinationPath)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let old = try readIfExists(url)
            let updated: String
            switch file.destinationPath {
            case "AGENTS.md": updated = try mergeAgents(old ?? "", block: file.contents)
            case ".claude/settings.json": updated = try mergeClaudeSettings(old, contents: file.contents)
            default:
                if let old, old != file.contents {
                    throw AutomationScriptError.invalidValue(
                        "Refusing to overwrite modified \(file.destinationPath).")
                }
                updated = file.contents
            }
            try updated.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    static func remove(_ files: [AutomationScriptFile], from root: URL) throws {
        for file in files {
            let url = try root.safelyAppendingPathComponent(file.destinationPath)
            guard let old = try readIfExists(url) else { continue }
            switch file.destinationPath {
            case "AGENTS.md":
                let updated = try mergeAgents(old, block: file.contents, removing: true)
                if updated.isEmpty {
                    try FileManager.default.removeItem(at: url)
                } else {
                    try updated.write(to: url, atomically: true, encoding: .utf8)
                }
            case ".claude/settings.json":
                let updated = try mergeClaudeSettings(old, contents: file.contents, removing: true)
                try updated.write(to: url, atomically: true, encoding: .utf8)
            default:
                guard old == file.contents else {
                    throw AutomationScriptError.invalidValue(
                        "Refusing to remove modified \(file.destinationPath).")
                }
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    private static func mergeAgents(_ old: String, block: String, removing: Bool = false) throws -> String {
        let startCount = old.components(separatedBy: agentsStart).count - 1
        let endCount = old.components(separatedBy: agentsEnd).count - 1
        guard startCount == endCount, startCount <= 1 else {
            throw AutomationScriptError.invalidValue("AGENTS.md has invalid CI Scope markers.")
        }
        let cleanBlock = block.trimmingCharacters(in: .whitespacesAndNewlines)
        if startCount == 1 {
            guard let start = old.range(of: agentsStart),
                let end = old.range(of: agentsEnd, range: start.upperBound..<old.endIndex)
            else {
                throw AutomationScriptError.invalidValue("AGENTS.md has invalid CI Scope markers.")
            }
            let range = start.lowerBound..<end.upperBound
            let managed = String(old[range])
            if managed != cleanBlock {
                throw AutomationScriptError.invalidValue("Refusing to overwrite modified CI Scope block in AGENTS.md.")
            }
            if !removing { return old }
            return old.replacingCharacters(in: range, with: removing ? "" : cleanBlock)
                .trimmingCharacters(in: .newlines)
        }
        guard !cleanBlock.isEmpty, !removing else { return old }
        return old.trimmingCharacters(in: .newlines) + (old.isEmpty ? "" : "\n\n") + cleanBlock + "\n"
    }

    private static func mergeClaudeSettings(_ old: String?, contents: String, removing: Bool = false) throws -> String {
        var settings: [String: Any] = [:]
        if let old, let data = old.data(using: .utf8) {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw AutomationScriptError.invalidValue(".claude/settings.json must contain a JSON object.")
            }
            settings = parsed
        }
        let managed = try JSONSerialization.jsonObject(with: Data(contents.utf8)) as? [String: Any] ?? [:]
        let managedHooks = managed["hooks"] as? [String: [[String: Any]]] ?? [:]
        var hooks: [String: [[String: Any]]] = [:]
        if let existingHooks = settings["hooks"] {
            guard let parsedHooks = existingHooks as? [String: [[String: Any]]] else {
                throw AutomationScriptError.invalidValue(
                    ".claude/settings.json hooks must map event names to hook arrays.")
            }
            hooks = parsedHooks
        }
        for (event, groups) in managedHooks {
            let existingGroups = hooks[event] ?? []
            let markedGroups = existingGroups.filter { group in
                isManagedHookGroup(group)
            }
            if removing {
                if !markedGroups.isEmpty && !sameJSON(markedGroups, groups) {
                    throw AutomationScriptError.invalidValue("Refusing to remove modified CI Scope hooks from .claude/settings.json.")
                }
            } else if !markedGroups.isEmpty && !sameJSON(markedGroups, groups) {
                throw AutomationScriptError.invalidValue("Refusing to overwrite modified CI Scope hooks in .claude/settings.json.")
            }
            let retainedGroups = existingGroups.filter { group in
                !isManagedHookGroup(group)
            }
            if removing {
                hooks[event] = retainedGroups
            } else {
                hooks[event] = retainedGroups + groups
            }
            if hooks[event]?.isEmpty == true { hooks.removeValue(forKey: event) }
        }
        if hooks.isEmpty { settings.removeValue(forKey: "hooks") } else { settings["hooks"] = hooks }
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    private static func sameJSON(_ left: Any, _ right: Any) -> Bool {
        guard let left = try? JSONSerialization.data(withJSONObject: left, options: [.sortedKeys]),
            let right = try? JSONSerialization.data(withJSONObject: right, options: [.sortedKeys])
        else {
            return false
        }
        return left == right
    }

    private static func readIfExists(_ url: URL) throws -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func isManagedHookGroup(_ group: [String: Any]) -> Bool {
        (group["hooks"] as? [[String: Any]] ?? []).contains { hook in
            guard let command = hook["command"] as? String else { return false }
            return command.contains(hookMarker)
                || (command.contains("output=$(scripts/check 2>&1); status=$?;")
                    && command.contains("exit 2"))
        }
    }
}
