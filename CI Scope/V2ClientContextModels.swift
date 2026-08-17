import Foundation

public struct V2ClientSessionContext: Codable, Equatable {
    public let machineId: String
    public let bootId: String
    public let agentInstanceId: String
    public let sessionId: String
    public let sessionEpoch: Int64

    public init(
        machineId: String,
        bootId: String,
        agentInstanceId: String,
        sessionId: String,
        sessionEpoch: Int64
    ) {
        self.machineId = machineId
        self.bootId = bootId
        self.agentInstanceId = agentInstanceId
        self.sessionId = sessionId
        self.sessionEpoch = sessionEpoch
    }
}

public struct V2ClientFencingContext: Codable, Equatable {
    public let localOwnerEpoch: Int64
    public let sessionEpoch: Int64
    public let fencingToken: String?
    public let runnerInstanceId: String?

    public init(
        localOwnerEpoch: Int64,
        sessionEpoch: Int64,
        fencingToken: String? = nil,
        runnerInstanceId: String? = nil
    ) {
        self.localOwnerEpoch = localOwnerEpoch
        self.sessionEpoch = sessionEpoch
        self.fencingToken = fencingToken
        self.runnerInstanceId = runnerInstanceId
    }
}

