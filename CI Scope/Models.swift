import Foundation

enum ServiceState: String {
    case online = "Online"
    case warning = "Warning"
    case offline = "Offline"
    case unknown = "Unknown"
}

struct RunnerStatus {
    var state: ServiceState = .unknown
    var launchctlState = "unknown"
    var servicePID: Int?
    var listenerPID: Int?
    var uptime = "-"
    var lastLine = "No local runner output yet."
    var error: String?
}

struct GitHubRun: Identifiable, Decodable {
    let databaseId: Int
    let status: String
    let conclusion: String?
    let displayTitle: String
    let workflowName: String
    let headBranch: String
    let event: String
    let createdAt: String
    let updatedAt: String
    let url: String

    var id: Int { databaseId }

    var compactConclusion: String {
        conclusion ?? status
    }
}

struct GitHubWorkflow: Identifiable, Decodable {
    let id: Int
    let name: String
    let path: String?
    let state: String
}

struct ProjectCISnapshot {
    let projectID: CIProject.ID
    var state: ServiceState = .unknown
    var workflows: [GitHubWorkflow] = []
    var runs: [GitHubRun] = []
    var error: String?
    var refreshedAt = Date()
}

struct OllamaLoadedModel: Identifiable, Decodable {
    let name: String
    let model: String
    let size: Int64?
    let digest: String?
    let expiresAt: String?
    let sizeVRAM: Int64?
    let contextLength: Int?

    var id: String { name + (digest ?? "") }

    enum CodingKeys: String, CodingKey {
        case name
        case model
        case size
        case digest
        case expiresAt = "expires_at"
        case sizeVRAM = "size_vram"
        case contextLength = "context_length"
    }
}

struct OllamaTagModel: Identifiable, Decodable {
    let name: String
    let model: String?
    let size: Int64?
    let modifiedAt: String?

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name
        case model
        case size
        case modifiedAt = "modified_at"
    }
}

struct OllamaStatus {
    var state: ServiceState = .unknown
    var loadedModels: [OllamaLoadedModel] = []
    var availableModels: [OllamaTagModel] = []
    var error: String?

    var loadedSummary: String {
        if loadedModels.isEmpty {
            return "No loaded models"
        }
        return loadedModels.map(\.name).joined(separator: ", ")
    }
}

struct NexusUnityStatus: Decodable {
    let serverAlive: Bool?
    let state: String?
    let busyReason: String?
    let lastError: String?
    let port: Int?
    let sessionId: String?
    let processId: Int?
    let projectPath: String?
    let unityVersion: String?
    let editorConnected: Bool?
    let mainThreadResponsive: Bool?
    let lastHeartbeatUtc: String?
    let editorState: EditorState?
    let commandState: CommandState?

    struct EditorState: Decodable {
        let isPlaying: Bool?
        let isCompiling: Bool?
        let isImporting: Bool?
        let isPaused: Bool?
        let isPlayModeTransition: Bool?
    }

    struct CommandState: Decodable {
        let acceptsReadCommands: Bool?
        let acceptsWriteCommands: Bool?
        let busyReason: String?
    }
}

struct NexusUnitySnapshot {
    var state: ServiceState = .unknown
    var status: NexusUnityStatus?
    var error: String?
}

struct LogSnapshot {
    var stdoutTail = ""
    var stderrTail = ""
    var latestRunnerDiagTail = ""
    var latestWorkerDiagTail = ""
    var latestRunnerDiagName = "Runner diag"
    var latestWorkerDiagName = "Worker diag"
}

struct ScriptStage: Identifiable {
    let id = UUID()
    let source: String
    let title: String
    let detail: String
    let command: String?
}

struct DashboardSnapshot {
    var runner = RunnerStatus()
    var runs: [GitHubRun] = []
    var ollama = OllamaStatus()
    var nexusUnity = NexusUnitySnapshot()
    var logs = LogSnapshot()
    var stages: [ScriptStage] = []
    var refreshedAt = Date()
    var errors: [String] = []
}

struct JSONRPCResponse<T: Decodable>: Decodable {
    let result: T?
    let error: JSONRPCError?
}

struct JSONRPCError: Decodable {
    let code: Int?
    let message: String?
}
