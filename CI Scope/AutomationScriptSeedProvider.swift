import Foundation

enum AutomationScriptSeedProvider {
    static let defaultSeedIDs = [
        "ai-readability", "swift-quality-gate", "swift-compile-gate",
        "web-quality-gate", "python-quality-gate", "unity-quality-gate",
        "slop-review",
    ]

    static func loadDefaultScripts() throws -> [AutomationScript] {
        try defaultSeedIDs.map { try loadSeed($0) }
    }

    static func loadSeed(_ id: String) throws -> AutomationScript {
        if let script = try loadBundledSeed(id) {
            return script
        }
        switch id {
        case "ai-readability":
            return fallbackReadabilitySeed()
        case "swift-quality-gate":
            return fallbackSwiftQualityGateSeed()
        case "swift-compile-gate":
            return fallbackSwiftCompileGateSeed()
        case "web-quality-gate":
            return fallbackWebQualityGateSeed()
        case "python-quality-gate":
            return fallbackPythonQualityGateSeed()
        case "unity-quality-gate":
            return fallbackUnityQualityGateSeed()
        case "slop-review":
            return fallbackSlopReviewSeed()
        default:
            throw AutomationScriptError.missingSeed(id)
        }
    }

    private static func loadBundledSeed(_ id: String) throws -> AutomationScript? {
        let nestedURL = Bundle.main.url(
            forResource: id,
            withExtension: "json",
            subdirectory: "AutomationScriptSeeds"
        )
        let rootURL = Bundle.main.url(forResource: id, withExtension: "json")
        guard let url = nestedURL ?? rootURL else {
            return nil
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(AutomationScript.self, from: data)
    }
}
