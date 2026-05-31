import Foundation
import Combine

enum LocalCommandPreset: String, CaseIterable, Identifiable {
    case staticValidation
    case quick
    case checklistAI
    case qualityAI
    case unitySmoke

    var id: String { rawValue }

    var title: String {
        switch self {
        case .staticValidation: "Static"
        case .quick: "Quick"
        case .checklistAI: "Checklist AI"
        case .qualityAI: "Quality AI"
        case .unitySmoke: "Unity Smoke"
        }
    }

    var systemImage: String {
        switch self {
        case .staticValidation: "checklist.checked"
        case .quick: "bolt"
        case .checklistAI: "list.clipboard"
        case .qualityAI: "brain"
        case .unitySmoke: "cube"
        }
    }

    func command(config: DashboardConfig) -> String {
        switch self {
        case .staticValidation:
            return "bash scripts/prepush-validate.sh --static-only"
        case .quick:
            return "NEXUS_UNITY_HOOK_LIVE=auto bash scripts/prepush-validate.sh --quick"
        case .checklistAI:
            return "bash scripts/prepush-validate.sh --checklist-ai"
        case .qualityAI:
            return "bash scripts/prepush-validate.sh --quality-ai"
        case .unitySmoke:
            return unitySmokeCommand(config: config)
        }
    }

    private func unitySmokeCommand(config: DashboardConfig) -> String {
        [
            unitySmokeSetupScript(unityEditorPath: quote(config.unityEditorPath)),
            unitySmokeManifestScript(),
            unitySmokeImportScript(),
            unitySmokeDependencyCheckScript()
        ].joined(separator: "\n\n")
    }

    private func unitySmokeSetupScript(unityEditorPath: String) -> String {
        """
        set -euo pipefail
        UNITY_EDITOR_PATH=\(unityEditorPath)
        test -x "$UNITY_EDITOR_PATH"

        export SMOKE_ROOT="${TMPDIR:-/tmp}/nexus-unity-package-smoke-local-$(date +%s)"
        export SMOKE_CREATE_LOG="${SMOKE_ROOT}-create.log"
        export SMOKE_IMPORT_LOG="${SMOKE_ROOT}-import.log"

        rm -rf "$SMOKE_ROOT"
        "$UNITY_EDITOR_PATH" -batchmode -quit -createProject "$SMOKE_ROOT" -logFile "$SMOKE_CREATE_LOG"
        """
    }

    private func unitySmokeManifestScript() -> String {
        """
        python3 - <<'PY'
        import json
        import os
        from pathlib import Path

        project_root = Path(os.environ["SMOKE_ROOT"])
        manifest_path = project_root / "Packages" / "manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        dependencies = manifest.setdefault("dependencies", {})
        dependencies["com.forkhorizon.nexus.unity"] = f"file:{os.environ['PACKAGE_ROOT']}"
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\\n", encoding="utf-8")
        PY
        """
    }

    private func unitySmokeImportScript() -> String {
        """
        if ! "$UNITY_EDITOR_PATH" -batchmode -quit -projectPath "$SMOKE_ROOT" -logFile "$SMOKE_IMPORT_LOG"; then
          echo "::error::Unity package smoke import failed."
          tail -n 200 "$SMOKE_IMPORT_LOG" || true
          exit 1
        fi

        failure_pattern='error CS|Scripts have compiler errors|A meta data file \\(.meta\\) exists but its asset|Couldn.t delete .*immutable folder|CS0234|CS0246|Assembly has reference errors|Package Manager error'
        if grep -E "$failure_pattern" "$SMOKE_IMPORT_LOG"; then
          echo "::error::Unity package smoke found package import or compile errors."
          tail -n 200 "$SMOKE_IMPORT_LOG" || true
          exit 1
        fi
        """
    }

    private func unitySmokeDependencyCheckScript() -> String {
        """
        python3 - <<'PY'
        import json
        import os
        import sys
        from pathlib import Path

        lock_path = Path(os.environ["SMOKE_ROOT"]) / "Packages" / "packages-lock.json"
        if not lock_path.exists():
            print(f"::error::Missing Unity package lock file: {lock_path}")
            sys.exit(1)

        dependencies = json.loads(lock_path.read_text(encoding="utf-8")).get("dependencies", {})
        required = [
            "com.forkhorizon.nexus.unity",
            "com.unity.inputsystem",
            "com.unity.nuget.newtonsoft-json",
            "com.unity.project-auditor",
            "com.unity.project-auditor-rules",
        ]
        missing = [package for package in required if package not in dependencies]
        if missing:
            print(f"::error::Unity package smoke did not resolve dependencies: {', '.join(missing)}")
            sys.exit(1)

        print("Unity package smoke resolved Nexus Unity and required dependencies.")
        PY
        """
    }

    private func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

@MainActor
final class LocalCommandRunner: ObservableObject {
    @Published var isRunning = false
    @Published var activeTitle: String?
    @Published var output = "No command has been run in this session."
    @Published var lastExitCode: Int32?

    private let config: DashboardConfig
    private var activeProcess: Process?

    init(config: DashboardConfig) {
        self.config = config
    }

    func run(_ preset: LocalCommandPreset) {
        guard !isRunning else { return }

        isRunning = true
        activeTitle = preset.title
        lastExitCode = nil
        output = "$ \(preset.command(config: config))\n\n"

        let process = Process()
        activeProcess = process

        let command = preset.command(config: config)
        let cwd = config.repositoryRoot
        let environment = commandEnvironment()

        Task.detached(priority: .userInitiated) { [weak self, process] in
            await self?.execute(process: process, command: command, cwd: cwd, environment: environment)
        }
    }

    func stop() {
        activeProcess?.terminate()
        append("\nTerminated by user.\n")
    }

    private nonisolated func execute(
        process: Process,
        command: String,
        cwd: String,
        environment: [String: String]
    ) async {
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in
                self?.append(chunk)
            }
        }

        do {
            try process.run()
            process.waitUntilExit()
            pipe.fileHandleForReading.readabilityHandler = nil
            let code = process.terminationStatus
            await MainActor.run {
                self.lastExitCode = code
                self.isRunning = false
                self.activeProcess = nil
                self.append("\nProcess exited with code \(code).\n")
            }
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            await MainActor.run {
                self.lastExitCode = 127
                self.isRunning = false
                self.activeProcess = nil
                self.append("\nFailed to start process: \(error.localizedDescription)\n")
            }
        }
    }

    private func commandEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = config.shellPath
        env["PACKAGE_ROOT"] = config.repositoryRoot
        env["SMOKE_ROOT"] = ""
        env["NEXUS_OLLAMA_URL"] = config.ollamaURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        env["NEXUS_DOC_AI_MODEL"] = config.qualityModel
        env["NEXUS_DOC_AI_MAX_PARALLEL"] = "1"
        env["NEXUS_DOC_AI_KEEP_ALIVE"] = "30s"
        env["NEXUS_DOC_AI_UNLOAD_ON_EXIT"] = "true"
        env["NEXUS_DOC_AI_TIMEOUT_SECONDS"] = "300"
        env["UNITY_EDITOR_PATH"] = config.unityEditorPath
        return env
    }

    private func append(_ text: String) {
        output += text
        if output.count > 120_000 {
            output = String(output.suffix(100_000))
        }
    }
}
