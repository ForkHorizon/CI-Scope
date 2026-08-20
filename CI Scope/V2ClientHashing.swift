import CryptoKit
import Foundation

nonisolated enum V2ClientPayloadHasher {
    nonisolated static func canonicalData<T: Encodable>(_ payload: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(payload)
    }

    nonisolated static func sha256<T: Encodable>(_ payload: T) throws -> String {
        SHA256.hash(data: try canonicalData(payload))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
