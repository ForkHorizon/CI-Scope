import Foundation
import CryptoKit

public enum V2ClientPayloadHasher {
    public static func canonicalData<T: Encodable>(_ payload: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(payload)
    }

    public static func sha256<T: Encodable>(_ payload: T) throws -> String {
        SHA256.hash(data: try canonicalData(payload))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

