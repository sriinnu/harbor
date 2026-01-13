import SwiftUI
import AppKit
import ImageIO

/// Custom Harbor anchor icon view using the actual logo
struct HarborIconView: View {
    var size: CGFloat = 18

    var body: some View {
        // Try to load logo from bundle resources first, then fall back to file paths
        let logoImage = Self.loadHarborLogo(size: size)

        if let nsImage = logoImage {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            // Fallback: simple anchor shape
            fallbackView
        }
    }

    private var fallbackView: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)

            Image(systemName: "shippingbox.fill")
                .font(.system(size: size * 0.5))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }

    /// Load and render the Harbor logo SVG at the specified size
    private static func loadHarborLogo(size: CGFloat) -> NSImage? {
        // First try to load from bundle resources
        if let nsImage = loadLogoFromBundle(size: size) {
            return nsImage
        }

        // Fall back to file path lookup for development
        if let logoPath = findLogoPath(), let svgData = try? Data(contentsOf: URL(fileURLWithPath: logoPath)) {
            return renderSVG(svgData: svgData, size: size)
        }

        return nil
    }

    /// Load logo from bundle resources
    private static func loadLogoFromBundle(size: CGFloat) -> NSImage? {
        // Try to find the logo in the main bundle
        guard let bundlePath = Bundle.main.path(forResource: "logo", ofType: "svg") else {
            return nil
        }

        guard let svgData = try? Data(contentsOf: URL(fileURLWithPath: bundlePath)) else {
            return nil
        }

        return renderSVG(svgData: svgData, size: size)
    }

    /// Render SVG data to NSImage at the specified size
    private static func renderSVG(svgData: Data, size: CGFloat) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(svgData as CFData, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(size * 2, 64)
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
    }

    /// Find the logo path by searching common locations (for development builds)
    private static func findLogoPath() -> String? {
        let bundlePath = Bundle.main.bundlePath

        // Common locations for development builds
        let possiblePaths = [
            // Project root Assets folder
            "/Users/srinivaspendela/Sriinnu/AI/Harbor/Assets/logo.svg",
            // Next to the app bundle
            (bundlePath as NSString).deletingLastPathComponent + "/Assets/logo.svg",
            (bundlePath as NSString).deletingLastPathComponent + "/assets/logo.svg",
            // Parent directories
            (bundlePath as NSString).deletingLastPathComponent + "/../../Assets/logo.svg",
            (bundlePath as NSString).deletingLastPathComponent + "/../../assets/logo.svg",
            // Build directory (for SPM builds)
            (bundlePath as NSString).deletingLastPathComponent + "/../../../../Assets/logo.svg",
        ]

        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
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
            HarborIconView(size: 24)
            HarborIconView(size: 18)
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
#endif
