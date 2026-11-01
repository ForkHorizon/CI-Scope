import Foundation

/// One suspicious accepted commit, with the owner's latest decision when there is one.
struct TestAlert: Identifiable, Equatable {
    let repository: String
    let sha: String
    let committedAt: String
    let message: String
    let findings: [TestFinding]
    var decision: TestDecision?

    var id: String { "\(repository)@\(sha)" }
    var severity: TestAlertSeverity { findings.map(\.severity).max() ?? .medium }
    var shortSHA: String { String(sha.prefix(7)) }
    var title: String {
        switch findings.first?.ruleID {
        case "test-modified": "Existing test changed"
        case "test-deleted": "Existing test deleted"
        case "test-renamed": "Existing test renamed"
        case "runner-config-changed": "Test runner configuration changed"
        case "test-skip-added": "Skip added to a test"
        default: "Test protection"
        }
    }

    /// Needs the owner's attention: no decision, or a mute that has run out.
    func isOpen(now: Date = Date()) -> Bool {
        guard let decision else { return true }
        return decision.isMuteExpired(now: now)
    }
}

struct TestDecision: Equatable {
    let repository: String
    let sha: String
    let decision: String
    let path: String?
    let note: String?
    let mutedUntil: String?
    let decidedBy: String
    let decidedAt: String

    func isMuteExpired(now: Date) -> Bool {
        guard decision == "muted", let mutedUntil,
            let until = ISO8601DateFormatter().date(from: mutedUntil)
        else { return false }
        return until <= now
    }
}
