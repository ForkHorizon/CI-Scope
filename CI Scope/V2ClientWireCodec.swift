import Foundation

public enum V2ClientWireCodec {
    public static func encodeFrame<T: Encodable>(_ value: T, maximumBytes: Int) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value)
        guard data.count + 1 <= maximumBytes else { throw V2ClientBridgeError.frameTooLarge }
        data.append(0x0A)
        return data
    }

    public static func decodeFrame<T: Decodable>(
        _ data: Data,
        as type: T.Type,
        maximumBytes: Int
    ) throws -> T {
        guard data.count <= maximumBytes, data.last == 0x0A else {
            throw V2ClientBridgeError.malformedFrame
        }
        return try JSONDecoder().decode(T.self, from: data.dropLast())
    }
}

