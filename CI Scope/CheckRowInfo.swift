import Foundation

/// One row's worth of display data for `UnifiedChecksSection`, built from
/// either a finished `UnifiedCheckResult` or a still-pending manifest entry.
/// Bundled into one value so the view doesn't pass six loose parameters.
struct CheckRowInfo {
    let id: String
    let type: String?
    let status: String
    let detail: String?
    let durationMs: Int?
    let required: Bool?

    init(check: UnifiedCheckResult) {
        id = check.id
        type = check.type
        status = check.status
        detail = check.detail ?? check.reason
        durationMs = check.durationMs
        required = check.required
    }

    init(pending check: CIScopeManifestCheck, status: String) {
        id = check.id
        type = check.type
        self.status = status
        detail = nil
        durationMs = nil
        required = nil
    }
}
