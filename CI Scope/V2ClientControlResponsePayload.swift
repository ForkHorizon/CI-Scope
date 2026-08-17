import Foundation

struct V2ClientControlResponsePayload: Codable, Equatable {
    let controlToken: String?
    let expiresAt: Int64?
    let processAlive: Bool?
    let schedulerHealthy: Bool?
    let controlLeaseActive: Bool?
    let serverConnected: Bool?
    let readyToClaim: Bool?
    let draining: Bool?
    let recoveryBlocked: Bool?
    let projectionLagging: Bool?
    let state: String?
    let localEpoch: Int64?
    let serverSessionEpoch: Int64?
    let controlLeaseExpiresAt: Int64?

    var statusProjection: V2ClientStatusProjection? {
        guard let processAlive, let schedulerHealthy, let controlLeaseActive,
            let serverConnected, let draining, let recoveryBlocked,
            let projectionLagging
        else { return nil }
        return V2ClientStatusProjection(
            health: V2ClientStatusHealth(
                processAlive: processAlive,
                schedulerHealthy: schedulerHealthy,
                controlLeaseActive: controlLeaseActive,
                serverConnected: serverConnected
            ),
            safety: V2ClientStatusSafety(
                draining: draining,
                recoveryBlocked: recoveryBlocked,
                projectionLagging: projectionLagging
            ),
            details: V2ClientStatusDetails(
                state: state,
                localEpoch: localEpoch,
                serverSessionEpoch: serverSessionEpoch,
                controlLeaseExpiresAt: controlLeaseExpiresAt
            )
        )
    }

    private enum CodingKeys: String, CodingKey {
        case controlToken
        case expiresAt
        case processAlive
        case schedulerHealthy
        case controlLeaseActive
        case serverConnected
        case readyToClaim
        case draining
        case recoveryBlocked
        case projectionLagging
        case state
        case localEpoch
        case serverSessionEpoch
        case controlLeaseExpiresAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        controlToken = try container.decodeIfPresent(String.self, forKey: .controlToken)
        expiresAt = try container.decodeIfPresent(Int64.self, forKey: .expiresAt)
        processAlive = try container.decodeIfPresent(Bool.self, forKey: .processAlive)
        schedulerHealthy = try container.decodeIfPresent(Bool.self, forKey: .schedulerHealthy)
        controlLeaseActive = try container.decodeIfPresent(Bool.self, forKey: .controlLeaseActive)
        serverConnected = try container.decodeIfPresent(Bool.self, forKey: .serverConnected)
        readyToClaim = try container.decodeIfPresent(Bool.self, forKey: .readyToClaim)
        draining = try container.decodeIfPresent(Bool.self, forKey: .draining)
        recoveryBlocked = try container.decodeIfPresent(Bool.self, forKey: .recoveryBlocked)
        projectionLagging = try container.decodeIfPresent(Bool.self, forKey: .projectionLagging)
        state = try container.decodeIfPresent(String.self, forKey: .state)
        localEpoch = try container.decodeIfPresent(Int64.self, forKey: .localEpoch)
        serverSessionEpoch = try container.decodeIfPresent(Int64.self, forKey: .serverSessionEpoch)
        controlLeaseExpiresAt = try container.decodeIfPresent(Int64.self, forKey: .controlLeaseExpiresAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(controlToken, forKey: .controlToken)
        try container.encodeIfPresent(expiresAt, forKey: .expiresAt)
        try container.encodeIfPresent(processAlive, forKey: .processAlive)
        try container.encodeIfPresent(schedulerHealthy, forKey: .schedulerHealthy)
        try container.encodeIfPresent(controlLeaseActive, forKey: .controlLeaseActive)
        try container.encodeIfPresent(serverConnected, forKey: .serverConnected)
        try container.encodeIfPresent(readyToClaim, forKey: .readyToClaim)
        try container.encodeIfPresent(draining, forKey: .draining)
        try container.encodeIfPresent(recoveryBlocked, forKey: .recoveryBlocked)
        try container.encodeIfPresent(projectionLagging, forKey: .projectionLagging)
        try container.encodeIfPresent(state, forKey: .state)
        try container.encodeIfPresent(localEpoch, forKey: .localEpoch)
        try container.encodeIfPresent(serverSessionEpoch, forKey: .serverSessionEpoch)
        try container.encodeIfPresent(controlLeaseExpiresAt, forKey: .controlLeaseExpiresAt)
    }
}

