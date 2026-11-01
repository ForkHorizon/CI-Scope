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
    static let inkDim = Color(white: 0.55)
    static let red = Color(red: 0.84, green: 0.10, blue: 0.13)

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
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .regular, design: .monospaced))
            .tracking(1)
            .textCase(.uppercase)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .foregroundStyle(foreground)
            .background(kind == .primary ? NothingTheme.ink : Color.clear, in: Capsule())
            .overlay(Capsule().stroke(border, lineWidth: 1))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.35)
            .contentShape(Capsule())
    }

    private var foreground: Color {
        switch kind {
        case .primary: .black
        case .danger: NothingTheme.red
        case .plain: NothingTheme.ink
        }
    }

    private var border: Color {
        switch kind {
        case .primary: NothingTheme.ink
        case .danger: NothingTheme.red
        case .plain: NothingTheme.lineStrong
        }
    }
}

extension ButtonStyle where Self == NothingPillStyle {
    static var pill: NothingPillStyle { NothingPillStyle() }
    static var pillPrimary: NothingPillStyle { NothingPillStyle(kind: .primary) }
    static var pillDanger: NothingPillStyle { NothingPillStyle(kind: .danger) }
}

/// Hairline outlined container used instead of tinted cards.
struct NothingCard: ViewModifier {
    var radius: CGFloat = 14
    var highlighted = false

    func body(content: Content) -> some View {
        content
            .background(highlighted ? NothingTheme.panel : Color.clear, in: RoundedRectangle(cornerRadius: radius))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .stroke(highlighted ? NothingTheme.lineStrong : NothingTheme.line, lineWidth: 1)
            )
    }
}

extension View {
    func nothingCard(radius: CGFloat = 14, highlighted: Bool = false) -> some View {
        modifier(NothingCard(radius: radius, highlighted: highlighted))
    }
}
