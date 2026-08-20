import Foundation

enum AutomationScriptValidator {
  static func validateForSave(_ script: AutomationScript) throws {
    try validateScriptIdentity(script)
    try validateFiles(script.files)
    try validateVariables(script.variables)
    guard !script.commitMessage.trimmed.isEmpty else {
      throw AutomationScriptError.invalidValue("Commit message is required.")
    }
    guard !script.pullRequestTitle.trimmed.isEmpty else {
      throw AutomationScriptError.invalidValue("Pull request title is required.")
    }
  }

  static func validateForInstall(
    _ script: AutomationScript,
    values: [String: String],
    branchName: String
  ) throws {
    try validateForSave(script)
    try validateBranchName(branchName)
    for variable in script.variables {
      let value = values[variable.id] ?? variable.defaultValue
      try validateValue(value, variable: variable)
    }
  }

  static func validatePath(_ path: String) throws {
    let value = path.trimmed
    guard !value.isEmpty else {
      throw AutomationScriptError.invalidValue("File destination path is required.")
    }
    guard !value.hasPrefix("/"), !value.contains("..") else {
      throw AutomationScriptError.invalidValue(
        "File path must be relative and cannot contain '..'.")
    }
    let invalid = CharacterSet.newlines.union(CharacterSet(charactersIn: "\0"))
    guard value.rangeOfCharacter(from: invalid) == nil else {
      throw AutomationScriptError.invalidValue("File path cannot contain line breaks.")
    }
  }

  private static func validateScriptIdentity(_ script: AutomationScript) throws {
    guard isSafeIdentifier(script.id) else {
      throw AutomationScriptError.invalidValue(
        "Script id can use letters, numbers, '.', '_' and '-'.")
    }
    guard !script.title.trimmed.isEmpty else {
      throw AutomationScriptError.invalidValue("Script title is required.")
    }
    guard !script.files.isEmpty else {
      throw AutomationScriptError.invalidValue("Script must include at least one file.")
    }
    guard !script.runnerLabels.isEmpty else {
      throw AutomationScriptError.invalidValue("Runner labels / runs-on is required.")
    }
  }

  private static func validateFiles(_ files: [AutomationScriptFile]) throws {
    var seen = Set<String>()
    for file in files {
      try validatePath(file.destinationPath)
      let key = file.destinationPath.trimmed.lowercased()
      guard !seen.contains(key) else {
        throw AutomationScriptError.invalidValue("Duplicate file path: \(file.destinationPath).")
      }
      seen.insert(key)
    }
  }

  private static func validateVariables(_ variables: [AutomationScriptVariable]) throws {
    var seen = Set<String>()
    for variable in variables {
      guard isSafeIdentifier(variable.id) else {
        throw AutomationScriptError.invalidValue("Variable id \(variable.id) is not valid.")
      }
      guard !seen.contains(variable.id) else {
        throw AutomationScriptError.invalidValue("Duplicate variable id: \(variable.id).")
      }
      seen.insert(variable.id)
    }
  }

  private static func validateValue(_ value: String, variable: AutomationScriptVariable) throws {
    let trimmed = value.trimmed
    if variable.isRequired, trimmed.isEmpty {
      throw AutomationScriptError.invalidValue("\(variable.title) is required.")
    }
    if variable.kind == .number, !trimmed.isEmpty, Double(trimmed) == nil {
      throw AutomationScriptError.invalidValue("\(variable.title) must be a number.")
    }
    if variable.kind == .option, !trimmed.isEmpty, !variable.options.contains(trimmed) {
      throw AutomationScriptError.invalidValue("\(variable.title) must match one of its options.")
    }
  }

  private static func validateBranchName(_ branch: String) throws {
    let value = branch.trimmed
    let blocked = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "~^:?*[\\"))
    guard !value.isEmpty, value.rangeOfCharacter(from: blocked) == nil else {
      throw AutomationScriptError.invalidValue("Rendered branch name is not valid.")
    }
    guard !value.hasPrefix("-"), !value.hasPrefix("/"), !value.hasSuffix("/"), !value.contains("..")
    else {
      throw AutomationScriptError.invalidValue("Rendered branch name is not valid.")
    }
  }

  private static func isSafeIdentifier(_ value: String) -> Bool {
    guard !value.isEmpty else { return false }
    let allowed = CharacterSet(
      charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
    return value.unicodeScalars.allSatisfy { allowed.contains($0) }
  }
}

extension String {
  var trimmed: String {
    trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
