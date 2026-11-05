// Nothing-style design tokens, dot-matrix display font and pill/card styles shared by all screens.
import AppKit
import CoreText
import SwiftUI

/// Design tokens for the Nothing-style look: black canvas, white ink, one red accent, dot-matrix display type.
enum NothingTheme {
    static let canvas = Color.black
    static let panel = Color(white: 0.055)
    static let line = Color(white: 0.16)
    static let lineStrong = Color(white: 0.32)
    static let ink = Color(white: 0.95)
    static let inkDim = Color(white: 0.68)
    static let red = Color(red: 0.84, green: 0.10, blue: 0.13)
    /// Signal colors: green = healthy/installed, amber = needs a look. Red stays reserved for alarms.
    static let green = Color(red: 0.30, green: 0.85, blue: 0.52)
    static let amber = Color(red: 1.0, green: 0.69, blue: 0.13)

    /// Readable type sizes (the app's old caption sizes were too small on black).
    static let body = Font.system(size: 13)
    static let small = Font.system(size: 12)
    static let tiny = Font.system(size: 11)

    /// Dot-matrix display face (bundled Doto, OFL). Falls back to bold monospaced when unavailable.
    static func display(_ size: CGFloat) -> Font {
        NSFont(name: "Doto-Black_Bold", size: size).map { Font($0) } ?? .system(size: size, weight: .black, design: .monospaced)
    }

    /// Registers the bundled font once at launch.
    static func registerFonts() {
        guard let url = Bundle.main.url(forResource: "Doto", withExtension: "ttf") else { return }
        var error: Unmanaged<CFError>?
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
    }
}

/// Small uppercase mono label, used for captions and section names.
struct NothingCaption: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 10, weight: .regular, design: .monospaced))
            .tracking(1.4)
            .textCase(.uppercase)
            .foregroundStyle(NothingTheme.inkDim)
    }
}

extension View {
    func nothingCaption() -> some View { modifier(NothingCaption()) }

    /// Dot-matrix display type; resets the global monospaced design so the custom face is not overridden.
    func nothingDisplay(_ size: CGFloat) -> some View {
        font(NothingTheme.display(size)).fontDesign(nil)
    }

    /// Applies the global look: dark canvas, mono type, white tint.
    func nothingRoot() -> some View {
        self
            .preferredColorScheme(.dark)
            .fontDesign(.monospaced)
            .tint(NothingTheme.ink)
            .background(NothingTheme.canvas)
    }
}

/// Pill button: `.primary` fills white, `.danger` is red outline, default is a hairline outline.
struct NothingPillStyle: ButtonStyle {
    enum Kind { case plain, primary, danger }
    var kind: Kind = .plain

    func makeBody(configuration: Configuration) -> some View { PillBody(configuration: configuration, style: self) }
}

private struct PillBody: View {
    let configuration: ButtonStyleConfiguration
    let style: NothingPillStyle
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        let hot = hovering && isEnabled
        configuration.label
            .font(.system(size: 11, weight: .regular, design: .monospaced))
            .tracking(1)
            .textCase(.uppercase)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .foregroundStyle(foreground(hot))
            .background(fill(hot), in: Capsule())
            .overlay(Capsule().stroke(border(hot), lineWidth: 1))
            .shadow(color: glow.opacity(hot ? 0.4 : 0), radius: 10)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(isEnabled ? 1 : 0.35)
            .contentShape(Capsule())
            .onHover { hovering = $0 }
            .pointerStyle(isEnabled ? .link : nil)
            .animation(.smooth(duration: 0.18), value: hovering)
            .animation(.spring(duration: 0.25, bounce: 0.4), value: configuration.isPressed)
    }

    private var glow: Color { style.kind == .danger ? NothingTheme.red : .white }

    private func fill(_ hot: Bool) -> Color {
        switch style.kind {
        case .primary: hot ? .white : NothingTheme.ink
        case .danger: hot ? NothingTheme.red : .clear
        case .plain: hot ? Color.white.opacity(0.1) : .clear
        }
    }

    private func foreground(_ hot: Bool) -> Color {
        switch style.kind {
        case .primary: .black
        case .danger: hot ? .white : NothingTheme.red
        case .plain: NothingTheme.ink
        }
    }

    private func border(_ hot: Bool) -> Color {
        switch style.kind {
        case .primary: NothingTheme.ink
        case .danger: NothingTheme.red
        case .plain: hot ? NothingTheme.ink : NothingTheme.lineStrong
        }
    }
}

extension ButtonStyle where Self == NothingPillStyle {
    static var pill: NothingPillStyle { NothingPillStyle() }
    static var pillPrimary: NothingPillStyle { NothingPillStyle(kind: .primary) }
    static var pillDanger: NothingPillStyle { NothingPillStyle(kind: .danger) }
}

/// Flat list row: hairline below, hover wash and bar; `fresh` flashes it once when it arrives live.
extension View {
    func nothingRow(fresh: Bool = false, tint: Color = NothingTheme.ink, changeToken: String = "") -> some View {
        modifier(NothingRow(fresh: fresh, tint: tint, changeToken: changeToken))
    }
}
