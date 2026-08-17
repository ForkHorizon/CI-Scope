import Foundation

public enum V2ClientControlCommand: String, Codable {
    case acquireControlLease
    case renewControlLease
    case resume
    case drain
    case emergencyStop
    case status
}

public struct V2ClientControlCommandPayload: Codable, Equatable {
    public let command: V2ClientControlCommand
    public let appInstanceId: String
    public let controlToken: String?
    public let drainDeadline: Date?

    public init(
        command: V2ClientControlCommand,
        appInstanceId: String,
        controlToken: String? = nil,
        drainDeadline: Date? = nil
    ) {
        self.command = command
        self.appInstanceId = appInstanceId
        self.controlToken = controlToken
        self.drainDeadline = drainDeadline
    }
}

