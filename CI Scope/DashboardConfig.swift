import Foundation

struct DashboardConfig {
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
            "\(NSHomeDirectory())/.local/bin",
        ].joined(separator: ":")
    }
}
