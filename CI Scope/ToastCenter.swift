// Our own notifications: a floating stack of cards in the top-right corner, shown even when the app is in the background.
import AppKit
import Combine
import SwiftUI

struct Toast: Identifiable, Equatable {
    enum Kind { case queued, running, passed, failed, alert, info }

    let id = UUID()
    var kind: Kind
    var title: String
    var detail: String
    /// Screen to open when the card is clicked.
    var destination: WorkspaceTab = .activity

    /// Alerts stay longer than progress updates.
    var lifetime: Double { kind == .alert || kind == .failed ? 10 : 6 }
}

@MainActor
final class ToastCenter: ObservableObject {
    static let shared = ToastCenter()

    static let width: CGFloat = 340
    static let cardHeight: CGFloat = 78
    static let gap: CGFloat = 10
    static let margin: CGFloat = 16
    /// Transparent room around the cards inside the window, so their glow is never cut off at the window edge.
    static let glow: CGFloat = 32
    private static let limit = 4

    @Published private(set) var toasts: [Toast] = []
    /// Set by the root view: brings the app forward and shows the screen a card points at.
    var onOpen: (WorkspaceTab) -> Void = { _ in }

    private var panel: NSPanel?

    func post(_ toast: Toast) {
        toasts.insert(toast, at: 0)
        if toasts.count > Self.limit { toasts.removeLast(toasts.count - Self.limit) }
        if toast.kind == .alert || toast.kind == .failed { NSSound(named: "Funk")?.play() }
        show()
    }

    func dismiss(_ id: Toast.ID) {
        toasts.removeAll { $0.id == id }
        // Let the card finish sliding out before the window shrinks around it.
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            layout()
        }
    }

    func open(_ toast: Toast) {
        dismiss(toast.id)
        NSApp.activate()
        onOpen(toast.destination)
    }

    private func show() {
        if panel == nil {
            let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.level = .statusBar
            panel.hidesOnDeactivate = false
            panel.isMovable = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            let host = NSHostingView(rootView: ToastStack(center: self))
            host.sizingOptions = []
            panel.contentView = host
            self.panel = panel
        }
        layout()
        panel?.orderFrontRegardless()
    }

    /// Sizes the window to exactly the visible cards so it never swallows clicks meant for what is underneath.
    private func layout() {
        guard let panel else { return }
        guard !toasts.isEmpty, let screen = NSScreen.main else { panel.orderOut(nil); return }
        let count = CGFloat(toasts.count)
        let height = count * Self.cardHeight + (count - 1) * Self.gap + 2 * Self.glow
        let area = screen.visibleFrame
        let frame = NSRect(x: area.maxX - Self.width - Self.margin - Self.glow, y: area.maxY - Self.margin + Self.glow - height, width: Self.width + 2 * Self.glow, height: height)
        panel.setFrame(frame, display: true)
    }
}

private struct ToastStack: View {
    @ObservedObject var center: ToastCenter

    var body: some View {
        VStack(spacing: ToastCenter.gap) {
            ForEach(center.toasts) { toast in
                ToastCard(toast: toast, center: center)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
            }
            Spacer(minLength: 0)
        }
        .padding(ToastCenter.glow)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(duration: 0.45, bounce: 0.25), value: center.toasts)
    }
}

private struct ToastCard: View {
    let toast: Toast
    let center: ToastCenter
    @State private var hovering = false
    @State private var remaining: Double
    @State private var drag: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(toast: Toast, center: ToastCenter) {
        self.toast = toast
        self.center = center
        _remaining = State(initialValue: toast.lifetime)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ToastGlyph(kind: toast.kind).padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.system(size: 10, design: .monospaced)).tracking(1.4).textCase(.uppercase).foregroundStyle(tint)
                Text(toast.title).font(NothingTheme.body.weight(.semibold)).foregroundStyle(NothingTheme.ink).lineLimit(1)
                Text(toast.detail).font(NothingTheme.small).foregroundStyle(NothingTheme.inkDim).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: ToastCenter.width, height: ToastCenter.cardHeight, alignment: .topLeading)
        .background(Color(white: hovering ? 0.08 : 0.045), in: RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .bottom) { timer }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(hovering ? tint.opacity(0.9) : NothingTheme.lineStrong, lineWidth: 1))
        .overlay(alignment: .topTrailing) { close }
        .shadow(color: tint.opacity(hovering ? 0.26 : 0.1), radius: hovering ? 16 : 10, y: 6)
        .scaleEffect(hovering ? 1.02 : 1)
        .offset(x: drag)
        .opacity(1 - Double(max(0, drag)) / 260)
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture { center.open(toast) }
        .gesture(
            DragGesture(minimumDistance: 6)
                .onChanged { drag = max(0, $0.translation.width) }
                .onEnded { value in
                    if value.translation.width > 70 { center.dismiss(toast.id) } else { withAnimation(.spring(duration: 0.3, bounce: 0.3)) { drag = 0 } }
                }
        )
        .onHover { hovering = $0 }
        .pointerStyle(.link)
        .animation(.smooth(duration: 0.2), value: hovering)
        .task {
            // Counts down only while the pointer is away, so a card you are reading never vanishes.
            while remaining > 0 {
                try? await Task.sleep(for: .milliseconds(50))
                if Task.isCancelled { return }
                if !hovering && drag == 0 { remaining -= 0.05 }
            }
            center.dismiss(toast.id)
        }
    }

    private var timer: some View {
        GeometryReader { proxy in
            Rectangle().fill(tint.opacity(0.7)).frame(width: proxy.size.width * max(0, remaining / toast.lifetime), height: 2)
                .animation(.linear(duration: 0.05), value: remaining)
        }
        .frame(height: 2)
        .opacity(reduceMotion ? 0 : 1)
    }

    private var close: some View {
        Button { center.dismiss(toast.id) } label: {
            Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(NothingTheme.inkDim).frame(width: 22, height: 22)
                .background(Color.white.opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain)
        .padding(8)
        .opacity(hovering ? 1 : 0)
        .scaleEffect(hovering ? 1 : 0.6)
    }

    private var tint: Color {
        switch toast.kind {
        case .queued, .running: NothingTheme.amber
        case .passed: NothingTheme.green
        case .failed, .alert: NothingTheme.red
        case .info: NothingTheme.ink
        }
    }

    private var label: String {
        switch toast.kind {
        case .queued: "Queued"
        case .running: "Running"
        case .passed: "Passed"
        case .failed: "Failed"
        case .alert: "Security alert"
        case .info: "CI Scope"
        }
    }
}

/// Status glyph: hollow dot for queued, spinning arc while running, filled circle with a mark when finished.
private struct ToastGlyph: View {
    let kind: Toast.Kind

    var body: some View {
        ZStack {
            switch kind {
            case .queued:
                Circle().stroke(NothingTheme.amber, lineWidth: 1.5).frame(width: 14, height: 14)
                ripple(NothingTheme.amber, period: 1.4)
            case .running:
                Circle().stroke(NothingTheme.amber.opacity(0.25), lineWidth: 1.5).frame(width: 14, height: 14)
                Loop(period: 0.9) { phase in
                    Circle().trim(from: 0, to: 0.3).stroke(NothingTheme.amber, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        .frame(width: 14, height: 14).rotationEffect(.degrees(phase * 360))
                }
            case .passed:
                Circle().fill(NothingTheme.green).frame(width: 14, height: 14)
                Image(systemName: "checkmark").font(.system(size: 8, weight: .black)).foregroundStyle(.black)
            case .failed, .alert:
                Circle().fill(NothingTheme.red).frame(width: 14, height: 14)
                ripple(NothingTheme.red, period: 1.2)
                Image(systemName: kind == .alert ? "exclamationmark" : "xmark").font(.system(size: 8, weight: .black)).foregroundStyle(.white)
            case .info:
                Circle().fill(NothingTheme.ink).frame(width: 14, height: 14)
            }
        }
        .frame(width: 18, height: 18)
    }

    private func ripple(_ color: Color, period: Double) -> some View {
        Loop(period: period) { phase in
            Circle().stroke(color, lineWidth: 1).frame(width: 14, height: 14).scaleEffect(1 + phase * 1.2).opacity(0.8 * (1 - phase))
        }
    }
}
