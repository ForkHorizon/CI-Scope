import Foundation

public struct V2ClientStatusHealth {
    public let processAlive: Bool
    public let schedulerHealthy: Bool
    public let controlLeaseActive: Bool
    public let serverConnected: Bool

    public init(
        processAlive: Bool,
        schedulerHealthy: Bool,
        controlLeaseActive: Bool,
        serverConnected: Bool
    ) {
        self.processAlive = processAlive
        self.schedulerHealthy = schedulerHealthy
        self.controlLeaseActive = controlLeaseActive
        self.serverConnected = serverConnected
    }
}

public struct V2ClientStatusSafety {
    public let draining: Bool
    public let recoveryBlocked: Bool
    public let projectionLagging: Bool

    public init(
        draining: Bool,
        recoveryBlocked: Bool,
        projectionLagging: Bool
    ) {
        self.draining = draining
        self.recoveryBlocked = recoveryBlocked
        self.projectionLagging = projectionLagging
    }
}

