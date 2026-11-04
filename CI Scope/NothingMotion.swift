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
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let visible = shown || reduceMotion
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
            .task(id: fresh) {
                guard fresh else { return }
                flash = true
                try? await Task.sleep(for: .milliseconds(60))
                withAnimation(.easeOut(duration: 1.6)) { flash = false }
            }
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

    mutating func seed(_ ids: [ID]) { known = Set(ids) }

    mutating func update(_ ids: [ID]) {
        let current = Set(ids)
        if let known { fresh = current.subtracting(known) }
        known = current
    }
}

extension View {
    func nothingEntrance(_ index: Int = 0) -> some View { modifier(NothingEntrance(index: index)) }
    func nothingTile(alarm: Bool = false) -> some View { modifier(NothingTile(alarm: alarm)) }
}
