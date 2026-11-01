// Settings building blocks: sections, label/control rows, Nothing-style text field and toggle.
import SwiftUI

/// Captioned group of rows separated by hairlines, with no surrounding card.
struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).nothingCaption().padding(.bottom, 6)
            VStack(spacing: 0) { content }
        }
    }
}

/// One setting: label and optional hint on the left, control on the right, hairline below.
struct SettingsRow<Control: View>: View {
    let title: String
    var hint: String?
    @ViewBuilder let control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(NothingTheme.body).foregroundStyle(NothingTheme.ink)
                if let hint {
                    Text(hint).font(NothingTheme.tiny).foregroundStyle(NothingTheme.inkDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: 210, alignment: .leading)
            control.frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(NothingTheme.line).frame(height: 1) }
    }
}

struct NothingFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .font(NothingTheme.small)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(NothingTheme.panel, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(NothingTheme.line, lineWidth: 1))
    }
}

/// Capsule switch: green when on.
struct NothingToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer(minLength: 12)
            Capsule()
                .fill(configuration.isOn ? NothingTheme.green : NothingTheme.panel)
                .overlay(Capsule().stroke(configuration.isOn ? NothingTheme.green : NothingTheme.lineStrong, lineWidth: 1))
                .frame(width: 38, height: 22)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle().fill(configuration.isOn ? Color.black : NothingTheme.inkDim).frame(width: 16, height: 16).padding(3)
                }
                .animation(.easeOut(duration: 0.12), value: configuration.isOn)
                .onTapGesture { configuration.isOn.toggle() }
        }
    }
}
