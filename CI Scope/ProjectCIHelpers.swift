import Foundation

extension ProjectCIService {
    func trimmedError(_ output: String, fallback: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    func cloneURL(for project: CIProject) -> String {
        if project.remoteURL.hasPrefix("git@") || project.remoteURL.hasPrefix("https://") {
            return project.remoteURL
        }
        return "git@github.com:\(project.repositorySlug).git"
    }

    func workflowName(from path: String) -> String {
        let filename = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        return
            filename
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    func sanitizeAuthOutput(_ output: String) -> String {
        output
            .components(separatedBy: .newlines)
            .map { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("- Token:") {
                    return line.replacingOccurrences(of: trimmed, with: "- Token: hidden")
                }
                return line
            }
            .joined(separator: "\n")
    }

    func accountName(from output: String) -> String? {
        guard let range = output.range(of: "account ") else {
            return nil
        }

        let suffix = output[range.upperBound...]
        let terminators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "("))
        return
            suffix
            .prefix { character in
                String(character).rangeOfCharacter(from: terminators) == nil
            }
            .nilIfEmpty
            .map(String.init)
    }

    func readRunnerConfiguration(path: String) -> RunnerConfiguration? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return nil
        }

        let jsonData: Data
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            jsonData = data.dropFirst(3)
        } else {
            jsonData = data
        }

        return try? JSONDecoder().decode(RunnerConfiguration.self, from: jsonData)
    }

    func gitHubSlug(from value: String?) -> String? {
        guard var value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        if value.hasPrefix("git@github.com:") {
            value = String(value.dropFirst("git@github.com:".count))
        } else if value.hasPrefix("https://github.com/") {
            value = String(value.dropFirst("https://github.com/".count))
        } else if value.hasPrefix("http://github.com/") {
            value = String(value.dropFirst("http://github.com/".count))
        }

        value =
            value
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        if value.hasSuffix(".git") {
            value = String(value.dropLast(4))
        }

        let parts = value.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count >= 2 else { return nil }
        return "\(parts[0])/\(parts[1])"
    }

    func gitHubOwner(from value: String?) -> String? {
        guard var value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        if value.hasPrefix("git@github.com:") {
            value = String(value.dropFirst("git@github.com:".count))
        } else if value.hasPrefix("https://github.com/") {
            value = String(value.dropFirst("https://github.com/".count))
        } else if value.hasPrefix("http://github.com/") {
            value = String(value.dropFirst("http://github.com/".count))
        }

        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if value.hasSuffix(".git") {
            value = String(value.dropLast(4))
        }

        return value.split(separator: "/", omittingEmptySubsequences: true)
            .first
            .map(String.init)
    }

    func processUptime(pid: Int?) async -> String {
        guard let pid else { return "-" }
        let result = await ShellClient.run("ps -p \(pid) -o etime= | xargs", timeout: 3, config: config)
        let uptime = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return uptime.isEmpty ? "-" : uptime
    }

    func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1 else { return nil }
        guard let valueRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[valueRange])
    }

    func intMatch(in text: String, pattern: String) -> Int? {
        firstMatch(in: text, pattern: pattern).flatMap(Int.init)
    }

    func quoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
