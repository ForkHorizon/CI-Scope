// Motion and hover building blocks: dot-matrix counter, screen entrance, interactive rows, live-feed arrivals.
import SwiftUI

/// Dot-matrix number that scrambles digit by digit (left to right) into its value whenever it appears or changes.
struct DotCounter: View {
    let value: Int
    var size: CGFloat = 34
    var color: Color = NothingTheme.ink
    @State private var shown: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ value: Int, size: CGFloat = 34, color: Color = NothingTheme.ink) {
        self.value = value
        self.size = size
        self.color = color
        _shown = State(initialValue: String(value))
    }

    var body: some View {
        Text(shown)
            .nothingDisplay(size)
            .foregroundStyle(color)
            .animation(.smooth(duration: 0.3), value: color)
            .task(id: value) {
                let final = String(value)
                guard !reduceMotion else { shown = final; return }
                let start = ContinuousClock.now
                let total = 380 + final.count * 140
                while !Task.isCancelled {
                    let elapsed = Int((ContinuousClock.now - start) / .milliseconds(1))
                    if elapsed >= total { break }
                    shown = String(final.enumerated().map { index, digit in elapsed > 380 + index * 140 ? digit : Character(String(Int.random(in: 0...9))) })
                    try? await Task.sleep(for: .milliseconds(45))
                }
                if !Task.isCancelled { shown = final }
            }
    }
}

/// Fades, lifts and un-blurs a view in when it appears; `index` staggers siblings.
struct NothingEntrance: ViewModifier {
    let index: Int
    /// Off for rows that arrive live: they come in through a list transition instead.
    var enabled = true
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let visible = shown || reduceMotion || !enabled
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 12)
            .blur(radius: visible ? 0 : 4)
            .onAppear { withAnimation(.smooth(duration: 0.5).delay(Double(min(index, 12)) * 0.05)) { shown = true } }
    }
}

/// Hairline row that reacts to the pointer (wash, bar and nudge) and can flash once when it arrives live.
struct NothingRow: ViewModifier {
    var fresh = false
    var tint: Color = NothingTheme.ink
    /// Any change of this value (a job's status, say) flashes the row once, like a live arrival.
    var changeToken = ""
    @State private var hovering = false
    @State private var flash = false

    func body(content: Content) -> some View {
        content
            .padding(.leading, hovering ? 10 : 0)
            .padding(.vertical, 9)
            .background { Rectangle().fill(hovering ? Color.white.opacity(0.045) : tint.opacity(flash ? 0.28 : 0)) }
            .overlay(alignment: .bottom) { Rectangle().fill(NothingTheme.line).frame(height: 1) }
            .overlay(alignment: .leading) {
                Capsule().fill(NothingTheme.ink).frame(width: 2).padding(.vertical, 9).opacity(hovering ? 1 : 0).scaleEffect(y: hovering ? 1 : 0.2)
            }
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .animation(.smooth(duration: 0.2), value: hovering)
            .task(id: fresh) { if fresh { await lightUp() } }
            .onChange(of: changeToken) { Task { await lightUp() } }
    }

    private func lightUp() async {
        flash = true
        try? await Task.sleep(for: .milliseconds(60))
        withAnimation(.easeOut(duration: 1.6)) { flash = false }
    }
}

/// One springy beat on the trailing edge whenever `trigger` changes: the moment a check ends.
struct ResultPulse: ViewModifier {
    let trigger: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion { content } else {
            content.keyframeAnimator(initialValue: 1.0, trigger: trigger) { view, scale in
                view.scaleEffect(scale, anchor: .trailing)
            } keyframes: { _ in
                SpringKeyframe(1.22, duration: 0.14)
                SpringKeyframe(1.0, duration: 0.45, spring: .bouncy)
            }
        }
    }
}

/// A job's state as a dot with its own rhythm: waiting breathes, claimed pulses a ring, running spins an arc.
struct JobDot: View {
    let status: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            switch status {
            case "queued":
                if reduceMotion { Circle().fill(NothingTheme.amber) } else {
                    Loop(period: 2.6) { phase in
                        let wave = 0.5 - 0.5 * cos(phase * 2 * .pi)
                        Circle().fill(NothingTheme.amber).opacity(0.35 + 0.65 * wave).scaleEffect(0.8 + 0.3 * wave)
                    }
                }
            case "leased":
                Circle().fill(NothingTheme.amber)
                if !reduceMotion {
                    Loop(period: 1.1) { phase in
                        Circle().stroke(NothingTheme.amber, lineWidth: 1).scaleEffect(1 + phase * 1.4).opacity(0.8 * (1 - phase))
                    }
                }
            case "running":
                Circle().stroke(NothingTheme.lineStrong, lineWidth: 1.5)
                if reduceMotion { Circle().fill(NothingTheme.amber).frame(width: 4, height: 4) } else {
                    Loop(period: 0.8) { phase in
                        Circle().trim(from: 0, to: 0.3).stroke(NothingTheme.amber, style: StrokeStyle(lineWidth: 1.5, lineCap: .round)).rotationEffect(.degrees(phase * 360))
                    }
                }
            case "succeeded": Circle().fill(NothingTheme.green)
            case "failed": Circle().fill(NothingTheme.red)
            default: Circle().stroke(NothingTheme.lineStrong, lineWidth: 1)
            }
        }
        .frame(width: 9, height: 9)
        .id(status)
        .transition(.opacity)
        .animation(.smooth(duration: 0.3), value: status)
    }
}

/// Tile that lifts and brightens its border under the pointer.
struct NothingTile: ViewModifier {
    var alarm = false
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(hovering ? Color(white: 0.09) : NothingTheme.panel, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(hovering ? (alarm ? NothingTheme.red : NothingTheme.ink) : NothingTheme.line, lineWidth: 1))
            .shadow(color: (alarm ? NothingTheme.red : Color.white).opacity(hovering ? 0.18 : 0), radius: 14, y: 8)
            .offset(y: hovering ? -3 : 0)
            .onHover { hovering = $0 }
            .animation(.smooth(duration: 0.22), value: hovering)
    }
}

/// Remembers which ids were already on screen so rows that arrive later can flash once.
struct FreshSet<ID: Hashable> {
    private var known: Set<ID>?
    private(set) var fresh: Set<ID> = []

    var isSeeded: Bool { known != nil }

    mutating func seed(_ ids: [ID]) { known = Set(ids) }

    mutating func update(_ ids: [ID]) {
        let current = Set(ids)
        if let known { fresh = current.subtracting(known) }
        known = current
    }
}

extension View {
    func nothingEntrance(_ index: Int = 0, enabled: Bool = true) -> some View { modifier(NothingEntrance(index: index, enabled: enabled)) }
    func resultPulse(_ trigger: String) -> some View { modifier(ResultPulse(trigger: trigger)) }
    func nothingTile(alarm: Bool = false) -> some View { modifier(NothingTile(alarm: alarm)) }
}

/// Endless looping value 0..<1 driven by the clock. Unlike `repeatForever` animations it never leaks into the layout transactions around it.
struct Loop<Content: View>: View {
    let period: Double
    @ViewBuilder var content: (Double) -> Content

    var body: some View {
        TimelineView(.animation) { context in
            content(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period)
        }
    }
}
