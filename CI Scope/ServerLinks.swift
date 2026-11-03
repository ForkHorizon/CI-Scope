// Addresses on the CI Scope website that the app opens for adding projects and changing protection.
import Foundation

enum ServerLinks {
    static let site = URL(string: "https://ci.forkhorizon.com/")!

    static func project(_ repository: String) -> URL {
        URL(string: "#/project/\(repository)", relativeTo: site)!.absoluteURL
    }

    static let alerts = URL(string: "#/alerts", relativeTo: site)!.absoluteURL
    static let projects = URL(string: "#/projects", relativeTo: site)!.absoluteURL
}
