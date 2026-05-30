import Foundation

extension DashboardService {
    func parseWorkflow(_ text: String, sourcePath: String) -> [ScriptStage] {
        var stages: [ScriptStage] = []
        var inJobs = false
        var currentJob: String?
        var currentJobName: String?

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line == "jobs:" {
                inJobs = true
                continue
            }
            guard inJobs else { continue }

            if rawLine.hasPrefix("  "), !rawLine.hasPrefix("    "), line.hasSuffix(":") {
                appendWorkflowJob(&stages, job: currentJob, name: currentJobName, sourcePath: sourcePath)
                currentJob = String(line.dropLast())
                currentJobName = nil
                continue
            }

            if currentJob != nil, line.hasPrefix("name:"), currentJobName == nil {
                currentJobName = String(line.dropFirst("name:".count)).trimmingCharacters(in: .whitespaces)
            }

            if currentJob != nil, line.hasPrefix("- name:") {
                let title = String(line.dropFirst("- name:".count)).trimmingCharacters(in: .whitespaces)
                stages.append(ScriptStage(source: "validate.yml", title: title, detail: "step", command: nil, sourcePath: sourcePath))
            }
        }

        appendWorkflowJob(&stages, job: currentJob, name: currentJobName, sourcePath: sourcePath)
        return stages
    }

    func parseValidationScript(_ text: String, sourcePath: String) -> [ScriptStage] {
        let commandByFunction: [String: String] = [
            "run_static_validation": "bash scripts/prepush-validate.sh --static-only",
            "run_ai_quality_validation": "bash scripts/prepush-validate.sh --quality-ai",
            "run_checklist_ai_validation": "bash scripts/prepush-validate.sh --checklist-ai",
            "run_quick_live_smoke": "bash scripts/prepush-validate.sh --quick",
            "run_local_integration_validation": "bash scripts/prepush-validate.sh --integration"
        ]

        return text.components(separatedBy: .newlines).compactMap { line in
            guard line.hasSuffix("() {") else { return nil }
            let function = line.replacingOccurrences(of: "() {", with: "").trimmingCharacters(in: .whitespaces)
            guard function.hasPrefix("run_") else { return nil }
            let title = function
                .replacingOccurrences(of: "run_", with: "")
                .replacingOccurrences(of: "_", with: " ")
            return ScriptStage(
                source: "prepush-validate.sh",
                title: title,
                detail: "function: \(function)",
                command: commandByFunction[function],
                sourcePath: sourcePath
            )
        }
    }

    private func appendWorkflowJob(
        _ stages: inout [ScriptStage],
        job: String?,
        name: String?,
        sourcePath: String
    ) {
        guard let job else { return }
        stages.append(ScriptStage(
            source: "validate.yml",
            title: name ?? job,
            detail: "job: \(job)",
            command: nil,
            sourcePath: sourcePath
        ))
    }
}
