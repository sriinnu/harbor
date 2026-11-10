import SwiftUI
import AppKit

struct HarborIconView: View {
    var size: CGFloat = 18

    var body: some View {
        if let nsImage = Self.loadHarborLogo(pointSize: self.size) {
            Image(nsImage: nsImage)
                .resizable().scaledToFit()
                .frame(width: size, height: size)
        } else {
            fallbackView
        }
    }

    private var fallbackView: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [.blue, .purple],
                                     startPoint: .topLeading,
                                     endPoint: .bottomTrailing))
            Image(systemName: "shippingbox.fill")
                .font(.system(size: size * 0.5))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }

    /// The logo at `pointSize` points. The PNG is 1024 px, and a status item lays an
    /// image out at its own size, so a full-size image would be hidden off-screen.
    static func loadHarborLogo(pointSize: CGFloat) -> NSImage? {
        // Try main bundle first (packaged app), then the SwiftPM resource bundle.
        for bundle in [Bundle.main, Bundle.module] {
            if let path = bundle.path(forResource: "logo", ofType: "png"),
               let img = NSImage(contentsOfFile: path) {
                img.isTemplate = false
                img.size = NSSize(width: pointSize, height: pointSize)
                return img
            }
        }
        return nil
    }
}

#if DEBUG
struct HarborIconView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            HarborIconView(size: 64)
            HarborIconView(size: 32)
            HarborIconView(size: 18)
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
#endif
