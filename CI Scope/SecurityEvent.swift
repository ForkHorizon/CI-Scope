// A tampering attempt or unverified merge the server wants the owner to see.
import Foundation

struct SecurityEvent: Codable, Equatable, Identifiable {
    var id: Int
    var repository: String
    var kind: String
    var detail: String
    var createdAt: Int

    /// Short headline for the notification and the list.
    var title: String {
        switch kind {
        case "protected_files_changed": "Protected files were changed"
        case "config_weakening_refused": "Someone tried to weaken the checks"
        case "baseline_change_refused": "Someone tried to change the protected-file baseline"
        case "merge_without_green_check": "A commit reached the main branch without a green check"
        default: "Security event"
        }
    }
}
