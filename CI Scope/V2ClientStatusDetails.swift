import Foundation

public struct V2ClientStatusDetails {
    public let state: String?
    public let localEpoch: Int64?
    public let serverSessionEpoch: Int64?
    public let controlLeaseExpiresAt: Int64?

    public init(
        state: String? = nil,
        localEpoch: Int64? = nil,
        serverSessionEpoch: Int64? = nil,
        controlLeaseExpiresAt: Int64? = nil
    ) {
        self.state = state
        self.localEpoch = localEpoch
        self.serverSessionEpoch = serverSessionEpoch
        self.controlLeaseExpiresAt = controlLeaseExpiresAt
    }
}

