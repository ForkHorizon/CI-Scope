import Foundation

// Tunable limits the Code Linter gate exposes in its install sheet.
// Mirrors the `variables` array in AutomationScriptSeeds/code-linter.json.
extension AutomationScriptSeedProvider {
  static var fallbackVariables: [AutomationScriptVariable] {
    [
      AutomationScriptVariable(
        id: "max_file_lines",
        title: "Max file lines",
        kind: .number,
        isRequired: true,
        defaultValue: "300",
        help: "Largest allowed source file length.",
        options: []
      ),
      AutomationScriptVariable(
        id: "max_function_lines",
        title: "Max function lines",
        kind: .number,
        isRequired: true,
        defaultValue: "50",
        help: "Largest allowed function or method length.",
        options: []
      ),
      AutomationScriptVariable(
        id: "max_nesting_depth",
        title: "Max nesting depth",
        kind: .number,
        isRequired: true,
        defaultValue: "4",
        help: "Deepest allowed control-flow nesting inside a function.",
        options: []
      ),
      AutomationScriptVariable(
        id: "max_parameters",
        title: "Max parameters",
        kind: .number,
        isRequired: true,
        defaultValue: "5",
        help: "Largest allowed parameter count on a function or method.",
        options: []
      ),
      AutomationScriptVariable(
        id: "max_comment_lines",
        title: "Max comment block lines",
        kind: .number,
        isRequired: true,
        defaultValue: "5",
        help:
          "Longest allowed run of consecutive comment lines. Doc comments and the file header are exempt.",
        options: []
      ),
      AutomationScriptVariable(
        id: "max_types_per_file",
        title: "Max types per file",
        kind: .number,
        isRequired: true,
        defaultValue: "2",
        help:
          "Largest allowed number of top-level types in one file. Nested types are not counted.",
        options: []
      ),
    ]
  }
}
