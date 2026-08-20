import Foundation

enum AutomationScriptVariableKind: String, Codable, CaseIterable, Identifiable {
    case text
    case multiline
    case boolean
    case number
    case option

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: "Text"
        case .multiline: "Multiline"
        case .boolean: "Boolean"
        case .number: "Number"
        case .option: "Option"
        }
    }
}

struct AutomationScriptVariable: Identifiable, Codable, Equatable {
    var id: String
    var title: String
    var kind: AutomationScriptVariableKind
    var isRequired: Bool
    var defaultValue: String
    var help: String
    var options: [String]

    static func empty() -> AutomationScriptVariable {
        AutomationScriptVariable(
            id: "variable",
            title: "Variable",
            kind: .text,
            isRequired: false,
            defaultValue: "",
            help: "",
            options: []
        )
    }
}
