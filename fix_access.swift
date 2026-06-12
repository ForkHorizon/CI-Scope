import Foundation

let path = "CI Scope/ProjectCIHelpers.swift"
var content = try! String(contentsOfFile: path, encoding: .utf8)
content = content.replacingOccurrences(of: "private static let stateRegex", with: "static let stateRegex")
content = content.replacingOccurrences(of: "private static let pidRegex", with: "static let pidRegex")
try! content.write(toFile: path, atomically: true, encoding: .utf8)
