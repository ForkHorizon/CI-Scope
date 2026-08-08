import AppKit
import SwiftUI

struct RunnerWebhookStrip: View {
    let webhook: BrokerWebhookStatus?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(statusColor)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Webhook")
                        .font(.caption.weight(.semibold))
                    Text(statusText)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                }

                Text(detailText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 8)
        }
        .padding(9)
        .background(statusColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(statusColor.opacity(0.16))
        )
    }

    private var statusColor: Color {
        guard let webhook else { return .secondary }
        if webhook.lastError != nil { return .orange }
        return webhook.enabled ? .green : .secondary
    }

    private var statusText: String {
        guard let webhook else { return "pending" }
        if webhook.lastError != nil { return "warning" }
        return webhook.enabled ? "listening" : "off"
    }

    private var detailText: String {
        guard let webhook else {
            return "Waiting for broker state."
        }

        if let error = webhook.lastError, !error.isEmpty {
            return error
        }

        let port = webhook.port.map(String.init) ?? "-"
        let path = webhook.path ?? "/github/workflow-job"
        let endpoint = "127.0.0.1:\(port)\(path)"
        guard let lastDelivery = webhook.lastDeliveryAt, !lastDelivery.isEmpty else {
            return "\(endpoint) · no deliveries yet"
        }

        let action = webhook.lastAction ?? "delivery"
        let repository = webhook.lastRepository ?? "GitHub"
        return "\(endpoint) · \(action) · \(repository) · \(shortDate(lastDelivery))"
    }

    private func shortDate(_ value: String) -> String {
        value
            .replacingOccurrences(of: "T", with: " ")
            .replacingOccurrences(of: "+00:00", with: "Z")
    }
}

struct RunnerErrorStrip: View {
    let errors: [String]

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(.red)
            Text(errors.joined(separator: "\n"))
                .font(.caption.monospaced())
                .foregroundStyle(.red)
                .textSelection(.enabled)
                .lineLimit(4)
            Spacer()
        }
        .padding(9)
        .background(Color.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.red.opacity(0.18))
        )
    }
}

func color(for state: ServiceState) -> Color {
    switch state {
    case .online: .green
    case .warning: .orange
    case .offline: .red
    case .unknown: .secondary
    }
}
