import Foundation

nonisolated enum V2ClientControlCommand: String, Codable, Sendable {
  case acquireControlLease
  case renewControlLease
  case resume
  case drain
  case emergencyStop
  case status
}

nonisolated struct V2ClientControlCommandPayload: Codable, Equatable, Sendable {
  let command: V2ClientControlCommand
  let appInstanceId: String
  let controlToken: String?
  let drainDeadline: Date?

  init(
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
