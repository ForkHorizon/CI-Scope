import Combine
import Foundation

enum ProjectStoreError: LocalizedError {
    case emptyInput
    case invalidRepositoryURL
    case duplicateProject(String)

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            "Enter a GitHub repository URL."
        case .invalidRepositoryURL:
            "Use owner/repo, https://github.com/owner/repo, or git@github.com:owner/repo.git."
        case .duplicateProject(let slug):
            "\(slug) is already in Projects."
        }
    }
}
