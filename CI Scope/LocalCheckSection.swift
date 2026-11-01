import SwiftUI

/// Result of the last `scripts/check` run on this Mac, compared with CI for the same commit.
struct LocalCheckSection: View {
    let result: LocalCheckResult
    let runs: [GitHubRun]

    private var verdict: LocalCheckVerdict {
        LocalCheckComparison.verdict(local: result, runs: runs)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label("Local check (this Mac)", systemImage: "laptopcomputer")
                    .font(NothingTheme.body.weight(.semibold))
                Spacer()
                StatusDot(state: result.passed ? .online : .offline)
            }
            Text(summary)
                .font(NothingTheme.small)
                .foregroundStyle(NothingTheme.inkDim)
            if let message = verdictMessage {
                Text(message)
                    .font(NothingTheme.small.weight(.semibold))
                    .foregroundStyle(verdict.isDiscrepancy ? Color.orange : Color.secondary)
            }
            ForEach(result.failedChecks) { check in
                Text("\(check.id): \(check.status)")
                    .font(NothingTheme.small)
                    .foregroundStyle(.red)
            }
            if !result.slow.isEmpty {
                Text("Slow: " + result.slow.joined(separator: ", "))
                    .font(NothingTheme.small)
                    .foregroundStyle(NothingTheme.inkDim)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var summary: String {
        var parts = [result.passed ? "Passed" : "Failed"]
        if let tier = result.tier { parts.append(tier) }
        if let date = result.finishedDate {
            parts.append(date.formatted(.relative(presentation: .named)))
        }
        if let head = result.gitHead, !head.isEmpty { parts.append(String(head.prefix(7))) }
        if result.dirty { parts.append("uncommitted changes") }
        return parts.joined(separator: " · ")
    }

    private var verdictMessage: String? {
        switch verdict {
        case .agree: "Matches CI for this commit"
        case .localGreenCIRed: "Local is green but CI is red for this commit"
        case .localRedCIGreen: "Local is red but CI is green for this commit"
        case .ciPending: "CI is still running for this commit"
        case .ciNotRun: "CI has no run for this commit yet"
        case .unknownCommit: nil
        }
    }
}
