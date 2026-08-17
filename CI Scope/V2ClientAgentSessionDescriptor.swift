import Foundation

struct V2ClientAgentSessionDescriptor: Decodable {
    let machineID: String
    let bootID: String
    let agentInstanceID: String
    let sessionID: String
    let sessionEpoch: Int
    let localOwnerEpoch: Int
    let fencingToken: String
    let socketPath: String

    static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CI-Scope", isDirectory: true)
            .appendingPathComponent("agent-session.json", isDirectory: false)
    }

    static func load() -> Self? {
        guard let data = try? Data(contentsOf: url),
            let descriptor = try? JSONDecoder().decode(Self.self, from: data),
            !descriptor.machineID.isEmpty,
            !descriptor.bootID.isEmpty,
            !descriptor.agentInstanceID.isEmpty,
            !descriptor.sessionID.isEmpty,
            descriptor.sessionEpoch > 0,
            descriptor.localOwnerEpoch > 0,
            !descriptor.fencingToken.isEmpty,
            !descriptor.socketPath.isEmpty
        else { return nil }
        return descriptor
    }
}

/// Read-only, opt-in bridge to the Agent. It is deliberately not a source of
/// truth for the legacy snapshot; callers may render this as an extra status.

