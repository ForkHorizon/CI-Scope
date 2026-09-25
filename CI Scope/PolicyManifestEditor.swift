import Foundation

enum PolicyManifestError: LocalizedError, Equatable {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let reason): reason
        }
    }
}

/// Text-preserving edits to `.ci-scope.json`: only the toggled check's object changes,
/// so the policy diff stays one small block. Every edit is validated before it can be
/// pushed, so a broken manifest never reaches a protected branch.
enum PolicyManifestEditor {
    static let knownTypes: Set = [
        "code-linter", "python-quality", "go-quality", "swift-quality", "swift-compile", "slop-review",
    ]

    static let templates: [String: String] = [
        "code-linter":
            #"{"id": "code-linter", "type": "code-linter", "config": ".code-linter.json", "params": {"mode": "auto"}}"#,
        "python-quality": #"{"id": "python-quality", "type": "python-quality"}"#,
        "go-quality": #"{"id": "go-quality", "type": "go-quality"}"#,
        "swift-quality":
            #"{"id": "swift-quality", "type": "swift-quality", "config": ".swift-quality-gate.json", "params": {"run_build": false}, "resources": ["xcode"]}"#,
        "swift-compile":
            #"{"id": "swift-compile", "type": "swift-compile", "config": ".swift-compile-gate.json", "resources": ["xcode"]}"#,
    ]

    static func checkIDs(in text: String) -> [String] {
        (try? checks(in: text))?.compactMap { $0["id"] as? String } ?? []
    }

    static func removing(_ id: String, from text: String) throws -> String {
        guard let key = text.range(of: #""id"\s*:\s*"\#(NSRegularExpression.escapedPattern(for: id))""#, options: .regularExpression)
        else { throw PolicyManifestError.invalid("Check \(id) is not in the manifest.") }
        let chars = Array(text)
        let keyIndex = text.distance(from: text.startIndex, to: key.lowerBound)
        var start = try enclosingOpen(chars, before: keyIndex)
        var end = try matchingClose(chars, from: start, open: "{", close: "}") + 1
        if let comma = previousNonSpace(chars, before: start), chars[comma] == "," {
            start = comma
        } else if let comma = nextNonSpace(chars, from: end), chars[comma] == "," {
            end = comma + 1
        }
        let edited = String(chars[..<start]) + String(chars[end...])
        try validate(edited)
        return edited
    }

    static func adding(_ type: String, to text: String) throws -> String {
        guard let entry = templates[type] else { throw PolicyManifestError.invalid("No template for \(type).") }
        guard !checkIDs(in: text).contains(type) else { throw PolicyManifestError.invalid("\(type) is already on.") }
        let chars = Array(text)
        guard let key = text.range(of: #""checks"\s*:\s*\["#, options: .regularExpression) else {
            throw PolicyManifestError.invalid("The manifest has no checks array.")
        }
        let open = text.distance(from: text.startIndex, to: key.upperBound) - 1
        let close = try matchingClose(chars, from: open, open: "[", close: "]")
        let indent = elementIndent(chars, after: open) ?? "    "
        let last = previousNonSpace(chars, before: close) ?? open
        let separator = last == open ? "" : ","
        let edited =
            String(chars[...last]) + separator + "\n" + indent + entry + String(chars[(last + 1)...])
        try validate(edited)
        return edited
    }

    static func validate(_ text: String) throws {
        let entries = try checks(in: text)
        let ids = entries.compactMap { $0["id"] as? String }
        guard ids.count == entries.count, Set(ids).count == ids.count else {
            throw PolicyManifestError.invalid("Every check needs a unique id.")
        }
        if let unknown = entries.compactMap({ $0["type"] as? String }).first(where: { !knownTypes.contains($0) }) {
            throw PolicyManifestError.invalid("Unknown check type \(unknown).")
        }
        guard ids.contains(where: { $0 != "slop-review" }) else {
            throw PolicyManifestError.invalid("At least one required check must stay on.")
        }
        for entry in entries {
            let missing = (entry["depends_on"] as? [String] ?? []).filter { !ids.contains($0) }
            if let dependency = missing.first {
                throw PolicyManifestError.invalid("\(entry["id"] ?? "A check") depends on \(dependency); turn that off first.")
            }
        }
    }

    private static func checks(in text: String) throws -> [[String: Any]] {
        guard let data = text.data(using: .utf8),
            let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            value["version"] as? Int == 1, let checks = value["checks"] as? [[String: Any]]
        else { throw PolicyManifestError.invalid("The manifest is not valid version-1 JSON.") }
        return checks
    }
}
