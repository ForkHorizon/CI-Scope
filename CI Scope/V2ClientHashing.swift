import Foundation
import CryptoKit

public nonisolated enum V2ClientPayloadHasher {
    public nonisolated static func canonicalData<T: Encodable>(_ payload: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(payload)
    }

    public nonisolated static func sha256<T: Encodable>(_ payload: T) throws -> String {
        SHA256.hash(data: try canonicalData(payload))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
