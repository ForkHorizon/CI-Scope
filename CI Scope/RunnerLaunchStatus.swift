import Foundation

struct BrokerWebhookStatus: Codable, Equatable {
  var enabled: Bool
  var port: Int?
  var path: String?
  var lastDeliveryAt: String?
  var lastDeliveryID: String?
  var lastAction: String?
  var lastRepository: String?
  var lastJob: String?
  var lastError: String?

  private enum CodingKeys: String, CodingKey {
    case enabled
    case port
    case path
    case lastDeliveryAt
    case lastDeliveryID = "lastDeliveryId"
    case lastAction
    case lastRepository
    case lastJob
    case lastError
  }
}

struct RunnerLaunchStatus {
  let state: ServiceState
  let launchctlState: String
  let pid: Int?
  let uptime: String
}
