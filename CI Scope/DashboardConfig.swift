import Foundation

struct DashboardConfig {
    let repositoryOwner = "ForkHorizon"
    let repositoryName = "NexusUnity"
    let repositoryRoot = "/Users/daliys/Daliys/UnityProjects/UnityTestForNexus/Assets/NexusUnity"
    let runnerRoot = "/Users/daliys/actions-runners/nexus-doc-ai"
    let runnerServiceLabel = "actions.runner.ForkHorizon-NexusUnity.NexusUnity-DO-NOT-QUIT-Ollama-AI-Docs-GitHub-Runner"
    let runnerStdoutLog = "/Users/daliys/Library/Logs/actions.runner.ForkHorizon-NexusUnity.NexusUnity-DO-NOT-QUIT-Ollama-AI-Docs-GitHub-Runner/stdout.log"
    let runnerStderrLog = "/Users/daliys/Library/Logs/actions.runner.ForkHorizon-NexusUnity.NexusUnity-DO-NOT-QUIT-Ollama-AI-Docs-GitHub-Runner/stderr.log"
    let ollamaURL = URL(string: "http://127.0.0.1:11434")!
    let nexusUnityURL = URL(string: "http://127.0.0.1:8081/")!
    let unityEditorPath = "/Applications/Unity/Hub/Editor/6000.4.3f1/Unity.app/Contents/MacOS/Unity"
    let qualityModel = "qwen3-coder:30b-a3b-q4_K_M"

    var repositorySlug: String {
        "\(repositoryOwner)/\(repositoryName)"
    }

    var shellPath: String {
        [
            "/opt/homebrew/opt/python@3.14/libexec/bin",
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
            "/Library/Apple/usr/bin",
            "/opt/homebrew/opt/openjdk@17/bin",
            "/Users/daliys/.local/bin"
        ].joined(separator: ":")
    }
}
