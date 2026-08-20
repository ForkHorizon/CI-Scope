import Foundation

enum AutomationScriptNaming {
  static func slug(title: String, fallback: String) -> String {
    let folded =
      title
      .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
      .lowercased()

    var result = ""
    var lastWasSeparator = false

    for scalar in folded.unicodeScalars {
      if scalar.isASCIIAlphanumeric {
        result.unicodeScalars.append(scalar)
        lastWasSeparator = false
      } else if !lastWasSeparator {
        result.append("-")
        lastWasSeparator = true
      }
    }

    let trimmed = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    if !trimmed.isEmpty {
      return trimmed
    }

    let fallbackSlug =
      fallback
      .lowercased()
      .unicodeScalars
      .map { $0.isASCIIAlphanumeric ? String($0) : "-" }
      .joined()
      .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

    return fallbackSlug.isEmpty ? "automation-script" : fallbackSlug
  }
}

extension UnicodeScalar {
  fileprivate var isASCIIAlphanumeric: Bool {
    ("a"..."z").contains(String(self)) || ("0"..."9").contains(String(self))
  }
}

extension AutomationScript {
  var scriptSlug: String {
    AutomationScriptNaming.slug(title: title, fallback: id)
  }
}
