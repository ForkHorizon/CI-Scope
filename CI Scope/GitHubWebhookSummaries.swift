import Foundation

struct GitHubWebhookSummary: Decodable {
  let config: GitHubWebhookConfigSummary
}

struct GitHubWebhookConfigSummary: Decodable {
  let url: String?
}
