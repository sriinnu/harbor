import SwiftUI

struct SubmenuIconColumnView<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        self.content
            .frame(width: MenuStyle.submenuIconColumnWidth, alignment: .center)
            .alignmentGuide(.firstTextBaseline) { dimensions in
                dimensions[VerticalAlignment.center] + MenuStyle.submenuIconBaselineOffset
            }
    }
}

struct SubmenuIconPlaceholderView: View {
    let font: Font

    init(font: Font = .caption) {
        self.font = font
    }

    var body: some View {
        SubmenuIconColumnView {
            Text(" ")
                .font(self.font)
                .accessibilityHidden(true)
        }
    }
}
