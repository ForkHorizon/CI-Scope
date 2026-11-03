import Foundation

enum ServiceState: String, Equatable {
    case online = "Online"
    case warning = "Warning"
    case offline = "Offline"
    case unknown = "Unknown"
}
