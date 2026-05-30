import Foundation

struct OllamaPsResponse: Decodable {
    let models: [OllamaLoadedModel]
}

struct OllamaTagsResponse: Decodable {
    let models: [OllamaTagModel]
}

enum DashboardServiceError: LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let output):
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Command failed." : trimmed
        }
    }
}
