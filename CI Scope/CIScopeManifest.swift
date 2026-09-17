import Foundation

struct CIScopeManifest: Decodable, Equatable {
    let version: Int
    let checks: [CIScopeManifestCheck]

    static func decode(_ data: Data) throws -> Self {
        let manifest = try JSONDecoder().decode(Self.self, from: data)
        guard manifest.version == 1 else { throw UnifiedChecksError.unsupportedManifestVersion }
        guard !manifest.checks.isEmpty else { throw UnifiedChecksError.emptyManifest }
        guard Set(manifest.checks.map(\.id)).count == manifest.checks.count else {
            throw UnifiedChecksError.duplicateCheckID
        }
        return manifest
    }
}

struct CIScopeManifestCheck: Decodable, Equatable, Identifiable {
    let id: String
    let type: String
}
