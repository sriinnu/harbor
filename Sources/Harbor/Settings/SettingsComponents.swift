import AppKit
import SwiftUI

// One look for every Settings pane: the System Settings grouped form ("Liquid Glass
// Native"). Native controls and materials do the work; rows carry no leading icons, so
// every label sits on the same indent. Colour is reserved for state (connected, error).

/// The container every pane uses.
struct SettingsPane<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        Form {
            self.content
        }
        .formStyle(.grouped)
    }
}

/// A section footer. Grouped-form footers align trailing on macOS by default (they're
/// meant for buttons); explanatory text reads better on the leading edge, as in System Settings.
struct SettingsFooter: View {
    private let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(verbatim: self.text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A row's two-line label: the title, then a secondary line. Used where a control
/// (Toggle, Picker, LabeledContent) takes a label view.
struct SettingsLabel: View {
    let title: String
    var detail: String?

    var body: some View {
        Text(verbatim: self.title)
        if let detail {
            Text(verbatim: detail)
        }
    }
}

/// "Connected", "Not connected" and similar states: a symbol plus text, so state never
/// relies on colour alone.
struct SettingsStatus: View {
    enum Kind {
        case ok
        case neutral
        case warning
        case error

        var symbol: String {
            switch self {
            case .ok: "checkmark.circle.fill"
            case .neutral: "circle.dashed"
            case .warning: "exclamationmark.triangle.fill"
            case .error: "xmark.octagon.fill"
            }
        }

        var tint: Color {
            switch self {
            case .ok: .green
            case .neutral: .secondary
            case .warning: .orange
            case .error: .red
            }
        }
    }

    let text: String
    var kind: Kind = .neutral

    var body: some View {
        Label {
            Text(verbatim: self.text)
                .foregroundStyle(.secondary)
        } icon: {
            Image(systemName: self.kind.symbol)
                .foregroundStyle(self.kind.tint)
        }
        .labelStyle(.titleAndIcon)
        .accessibilityElement(children: .combine)
    }
}

/// An inline error under a group of fields.
struct SettingsErrorText: View {
    let text: String

    var body: some View {
        Label {
            Text(verbatim: self.text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(.callout)
        .foregroundStyle(.red)
        .accessibilityLabel("Error: \(self.text)")
    }
}

/// A link that opens in the browser, styled as a native link.
struct SettingsLink: View {
    let title: String
    let url: String

    var body: some View {
        if let destination = URL(string: self.url) {
            Link(destination: destination) {
                Text(verbatim: self.title)
            }
            .help(self.url)
        }
    }
}

/// A trailing "Done/Apply"-style row: a group's primary action, right-aligned.
struct SettingsActionRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            self.content
        }
    }
}

extension Bundle {
    var harborShortVersion: String {
        self.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
    }

    /// "0.2.0 (0.02.0011)": the marketing version plus the dev build label or build number.
    var harborVersionDescription: String {
        let build = self.object(forInfoDictionaryKey: "HarborBuildLabel") as? String
            ?? self.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build.map { "\(self.harborShortVersion) (\($0))" } ?? self.harborShortVersion
    }
}
