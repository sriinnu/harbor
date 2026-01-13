import SwiftUI

// MARK: - Harbor Design System
/// Cross-platform design system ensuring liquid, fluid UI/UX across macOS, iOS, Windows, and Web
/// Design tokens sourced from design-tokens.json

// MARK: - Color System

public extension Color {
    // MARK: - Primary Colors

    static let harborPrimary = Color("harborPrimary", bundle: .main)
    static let harborPrimaryForeground = Color("harborPrimaryForeground", bundle: .main)
    static let harborPrimaryMuted = Color("harborPrimaryMuted", bundle: .main)
    static let harborPrimaryAccent = Color("harborPrimaryAccent", bundle: .main)

    // MARK: - Status Colors

    static let harborSuccess = Color("harborSuccess", bundle: .main)
    static let harborSuccessBackground = Color("harborSuccessBackground", bundle: .main)
    static let harborSuccessBorder = Color("harborSuccessBorder", bundle: .main)

    static let harborWarning = Color("harborWarning", bundle: .main)
    static let harborWarningBackground = Color("harborWarningBackground", bundle: .main)
    static let harborWarningBorder = Color("harborWarningBorder", bundle: .main)

    static let harborError = Color("harborError", bundle: .main)
    static let harborErrorBackground = Color("harborErrorBackground", bundle: .main)
    static let harborErrorBorder = Color("harborErrorBorder", bundle: .main)

    static let harborInfo = Color("harborInfo", bundle: .main)
    static let harborInfoBackground = Color("harborInfoBackground", bundle: .main)
    static let harborInfoBorder = Color("harborInfoBorder", bundle: .main)

    // MARK: - CI Status Colors

    static let harborCISuccess = Color(red: 0.13, green: 0.77, blue: 0.37) // #22C55E
    static let harborCIFailure = Color(red: 0.94, green: 0.27, blue: 0.27) // #EF4444
    static let harborCIPending = Color(red: 0.23, green: 0.51, blue: 0.96) // #3B82F6
    static let harborCIUnknown = Color(red: 0.42, green: 0.45, blue: 0.50) // #6B7280
    static let harborCIRunning = Color(red: 0.55, green: 0.36, blue: 0.96) // #8B5CF6

    // MARK: - Sync Status Colors

    static let harborSyncSynced = Color(red: 0.13, green: 0.77, blue: 0.37)
    static let harborSyncBehind = Color(red: 0.96, green: 0.35, blue: 0.04)
    static let harborSyncAhead = Color(red: 0.23, green: 0.51, blue: 0.96)
    static let harborSyncDiverged = Color(red: 0.96, green: 0.35, blue: 0.04)
    static let harborSyncDirty = Color(red: 0.94, green: 0.27, blue: 0.27)
    static let harborSyncUnknown = Color(red: 0.42, green: 0.45, blue: 0.50)

    // MARK: - Surface Colors

    static let harborBackground = Color("harborBackground", bundle: .main)
    static let harborCard = Color("harborCard", bundle: .main)
    static let harborElevated = Color("harborElevated", bundle: .main)
    static let harborMuted = Color("harborMuted", bundle: .main)
    static let harborBorder = Color("harborBorder", bundle: .main)
    static let harborDivider = Color("harborDivider", bundle: .main)

    // MARK: - Text Colors

    static let harborTextPrimary = Color("harborTextPrimary", bundle: .main)
    static let harborTextSecondary = Color("harborTextSecondary", bundle: .main)
    static let harborTextTertiary = Color("harborTextTertiary", bundle: .main)
    static let harborTextMuted = Color("harborTextMuted", bundle: .main)
    static let harborTextInverse = Color("harborTextInverse", bundle: .main)
    static let harborTextLink = Color("harborTextLink", bundle: .main)
}

// MARK: - Typography System

public enum HarborTypography {
    public static let fontFamily = "Inter"

    public enum FontSize {
        public static let xs = Font.system(size: 12, weight: .regular)
        public static let sm = Font.system(size: 14, weight: .regular)
        public static let base = Font.system(size: 16, weight: .regular)
        public static let lg = Font.system(size: 18, weight: .regular)
        public static let xl = Font.system(size: 20, weight: .semibold)
        public static let `2xl` = Font.system(size: 24, weight: .semibold)
        public static let `3xl` = Font.system(size: 30, weight: .bold)
        public static let `4xl` = Font.system(size: 36, weight: .bold)
    }

    public enum FontWeight {
        public static let normal = Font.Weight.regular
        public static let medium = Font.Weight.medium
        public static let semibold = Font.Weight.semibold
        public static let bold = Font.Weight.bold
    }

    public enum LineHeight {
        public static let tight: CGFloat = 1.25
        public static let normal: CGFloat = 1.5
        public static let relaxed: CGFloat = 1.75
    }
}

// MARK: - Spacing System

public enum HarborSpacing {
    public static let `0`: CGFloat = 0
    public static let `1`: CGFloat = 4
    public static let `2`: CGFloat = 8
    public static let `3`: CGFloat = 12
    public static let `4`: CGFloat = 16
    public static let `5`: CGFloat = 20
    public static let `6`: CGFloat = 24
    public static let `8`: CGFloat = 32
    public static let `10`: CGFloat = 40
    public static let `12`: CGFloat = 48
    public static let `16`: CGFloat = 64
    public static let `20`: CGFloat = 80
    public static let `24`: CGFloat = 96
}

// MARK: - Corner Radius

public enum HarborCornerRadius {
    public static let none: CGFloat = 0
    public static let sm: CGFloat = 4
    public static let md: CGFloat = 8
    public static let lg: CGFloat = 12
    public static let xl: CGFloat = 16
    public static let `2xl`: CGFloat = 24
    public static let full: CGFloat = 9999
}

// MARK: - Shadow System

public enum HarborShadow {
    public static let sm = ShadowStyle(color: .black.opacity(0.05), x: 0, y: 1, blur: 2)
    public static let `default` = ShadowStyle(color: .black.opacity(0.1), x: 0, y: 1, blur: 3)
    public static let md = ShadowStyle(color: .black.opacity(0.1), x: 0, y: 4, blur: 6)
    public static let lg = ShadowStyle(color: .black.opacity(0.1), x: 0, y: 10, blur: 15)
    public static let xl = ShadowStyle(color: .black.opacity(0.1), x: 0, y: 20, blur: 25)
    public static let card = ShadowStyle(color: .black.opacity(0.05), x: 0, y: 1, blur: 3)
    public static let cardHovered = ShadowStyle(color: .black.opacity(0.1), x: 0, y: 8, blur: 16)
    public static let dropdown = ShadowStyle(color: .black.opacity(0.2), x: 0, y: 10, blur: 40)
    public static let modal = ShadowStyle(color: .black.opacity(0.25), x: 0, y: 25, blur: 50)
}

public struct ShadowStyle: Sendable {
    public let color: Color
    public let x: CGFloat
    public let y: CGFloat
    public let blur: CGFloat

    public init(color: Color, x: CGFloat = 0, y: CGFloat = 0, blur: CGFloat = 0) {
        self.color = color
        self.x = x
        self.y = y
        self.blur = blur
    }
}

extension View {
    public func shadow(_ style: ShadowStyle) -> some View {
        self.shadow(color: style.color, radius: style.blur, x: style.x, y: style.y)
    }
}

// MARK: - Animation System

public enum HarborAnimation {
    public static let durationFast: Double = 0.15
    public static let durationDefault: Double = 0.2
    public static let durationMedium: Double = 0.3
    public static let durationSlow: Double = 0.5
    public static let durationLong: Double = 0.7

    public static let easingDefault = Animation.easeInOut(duration: durationDefault)
    public static let easingEaseIn = Animation.easeIn(duration: durationDefault)
    public static let easingEaseOut = Animation.easeOut(duration: durationDefault)
    public static let easingSpring = Animation.spring(response: durationDefault, dampingFraction: 0.8)
    public static let easingSpringBounce = Animation.spring(response: durationMedium, dampingFraction: 0.6)

    // MARK: - Pre-built Animations

    public static let fadeIn = Animation.easeIn(duration: durationMedium)
    public static let fadeOut = Animation.easeOut(duration: durationMedium)
    public static let scaleIn = Animation.spring(response: durationMedium, dampingFraction: 0.7)
    public static let slideUp = Animation.easeOut(duration: durationMedium)
    public static let slideDown = Animation.easeIn(duration: durationMedium)
    public static let slideLeft = Animation.easeInOut(duration: durationMedium)
    public static let slideRight = Animation.easeInOut(duration: durationMedium)

    // MARK: - View Extensions

    public static func withHover(_ isHovered: Bool, scale: Bool = true) -> some ViewModifier {
        HoverEffectModifier(isHovered: isHovered, scale: scale)
    }
}

private struct HoverEffectModifier: ViewModifier {
    let isHovered: Bool
    let scale: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered && scale ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}

public extension View {
    /// Apply liquid hover effect with smooth animation
    @ViewBuilder
    func harborHoverEffect(_ enabled: Bool = true) -> some View {
        if enabled {
            self.overlay(
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            self.performHoverEffect(hovering: hovering, in: geometry)
                        }
                }
            )
        } else {
            self
        }
    }

    private func performHoverEffect(hovering: Bool, in geometry: GeometryProxy) -> some View {
        self
            .scaleEffect(hovering ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: hovering)
    }

    /// Apply card styling with hover effects
    func harborCardStyle(hoverable: Bool = true) -> some View {
        self
            .padding(HarborSpacing.`4`)
            .background(
                RoundedRectangle(cornerRadius: HarborCornerRadius.lg)
                    .fill(Color.harborCard)
                    .shadow(HarborShadow.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: HarborCornerRadius.lg)
                    .stroke(Color.harborBorder, lineWidth: 1)
            )
            .animation(.easeInOut(duration: 0.2), value: false)
    }

    /// Apply liquid glass background
    func harborGlassBackground() -> some View {
        self
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: HarborCornerRadius.lg))
    }
}

// MARK: - Button Styles

public struct HarborButtonStyle: ButtonStyle {
    public static let `default` = HarborButtonStyle(variant: .primary, size: .medium)

    public enum Variant {
        case primary
        case secondary
        case ghost
        case destructive
    }

    public enum Size {
        case small
        case medium
        case large

        var padding: EdgeInsets {
            switch self {
            case .small: EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
            case .medium: EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
            case .large: EdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 24)
            }
        }
    }

    let variant: Variant
    let size: Size

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(HarborTypography.FontSize.sm)
            .fontWeight(.medium)
            .padding(size.padding)
            .background(background(for: configuration.isPressed))
            .foregroundColor(foreground)
            .clipShape(RoundedRectangle(cornerRadius: HarborCornerRadius.md))
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }

    private func background(for isPressed: Bool) -> Color {
        switch variant {
        case .primary:
            return isPressed ? Color.harborPrimaryMuted : Color.harborPrimary
        case .secondary:
            return isPressed ? Color.harborMuted : Color.harborBackground
        case .ghost:
            return .clear
        case .destructive:
            return isPressed ? Color.harborErrorBackground : Color.harborError
        }
    }

    private var foreground: Color {
        switch variant {
        case .primary, .destructive:
            return .white
        case .secondary, .ghost:
            return Color.harborTextPrimary
        }
    }
}

public extension ButtonStyle where Self == HarborButtonStyle {
    static func harbor(variant: HarborButtonStyle.Variant = .primary, size: HarborButtonStyle.Size = .medium) -> HarborButtonStyle {
        HarborButtonStyle(variant: variant, size: size)
    }
}

// MARK: - Input Field Style

public struct HarborTextFieldStyle: TextFieldStyle, @unchecked Sendable {
    public static let `default` = HarborTextFieldStyle()

    public func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(HarborTypography.FontSize.base)
            .padding(HarborSpacing.`3`)
            .background(
                RoundedRectangle(cornerRadius: HarborCornerRadius.md)
                    .fill(Color.harborBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: HarborCornerRadius.md)
                    .stroke(Color.harborBorder, lineWidth: 1)
            )
            .animation(.easeInOut(duration: 0.15), value: false)
    }
}

public extension TextFieldStyle where Self == HarborTextFieldStyle {
    static var harbor: HarborTextFieldStyle { .default }
}

// MARK: - Card Style Modifier

public struct HarborCardModifier: ViewModifier {
    @State private var isHovered = false

    public static let `default` = HarborCardModifier()

    public func body(content: Content) -> some View {
        content
            .padding(HarborSpacing.`4`)
            .background(
                RoundedRectangle(cornerRadius: HarborCornerRadius.lg)
                    .fill(Color.harborCard)
                    .shadow(isHovered ? HarborShadow.cardHovered : HarborShadow.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: HarborCornerRadius.lg)
                    .stroke(isHovered ? Color.harborPrimary.opacity(0.3) : Color.harborBorder, lineWidth: 1)
            )
            .scaleEffect(isHovered ? 1.01 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

public extension View {
    func harborCard() -> some View {
        modifier(HarborCardModifier.default)
    }
}

// MARK: - Badge View

public struct HarborBadge: View {
    public enum Variant {
        case `default`
        case success
        case warning
        case error
        case info
        case ci(status: CIStatus)
        case sync(status: LocalSyncStatus)
    }

    public enum CIStatus {
        case passing
        case failing
        case pending
        case unknown
        case running
    }

    public enum LocalSyncStatus {
        case synced
        case behind
        case ahead
        case diverged
        case dirty
        case unknown
    }

    let content: String
    let variant: Variant

    public init(_ content: String, variant: Variant = .default) {
        self.content = content
        self.variant = variant
    }

    public var body: some View {
        Text(content)
            .font(HarborTypography.FontSize.xs)
            .fontWeight(.medium)
            .padding(.horizontal, HarborSpacing.`2`)
            .padding(.vertical, HarborSpacing.`1`)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .clipShape(Capsule())
    }

    private var backgroundColor: Color {
        switch variant {
        case .default: return Color.harborMuted
        case .success: return Color.harborSuccessBackground
        case .warning: return Color.harborWarningBackground
        case .error: return Color.harborErrorBackground
        case .info: return Color.harborInfoBackground
        case .ci(let status): return ciColor(for: status).opacity(0.15)
        case .sync(let status): return syncColor(for: status).opacity(0.15)
        }
    }

    private var foregroundColor: Color {
        switch variant {
        case .default: return Color.harborTextSecondary
        case .success: return Color.harborSuccess
        case .warning: return Color.harborWarning
        case .error: return Color.harborError
        case .info: return Color.harborInfo
        case .ci(let status): return ciColor(for: status)
        case .sync(let status): return syncColor(for: status)
        }
    }

    private func ciColor(for status: CIStatus) -> Color {
        switch status {
        case .passing: return .harborCISuccess
        case .failing: return .harborCIFailure
        case .pending: return .harborCIPending
        case .unknown: return .harborCIUnknown
        case .running: return .harborCIRunning
        }
    }

    private func syncColor(for status: LocalSyncStatus) -> Color {
        switch status {
        case .synced: return .harborSyncSynced
        case .behind: return .harborSyncBehind
        case .ahead: return .harborSyncAhead
        case .diverged: return .harborSyncDiverged
        case .dirty: return .harborSyncDirty
        case .unknown: return .harborSyncUnknown
        }
    }
}

// MARK: - Avatar View

public struct HarborAvatar: View {
    public enum Size {
        case sm
        case md
        case lg
        case xl

        var dimension: CGFloat {
            switch self {
            case .sm: return 20
            case .md: return 32
            case .lg: return 40
            case .xl: return 64
            }
        }
    }

    let imageURL: URL?
    let fallback: String
    let size: Size

    public init(imageURL: URL?, fallback: String, size: Size = .md) {
        self.imageURL = imageURL
        self.fallback = fallback
        self.size = size
    }

    public var body: some View {
        Group {
            if let imageURL = imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        fallbackView
                    case .empty:
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    @unknown default:
                        fallbackView
                    }
                }
            } else {
                fallbackView
            }
        }
        .frame(width: size.dimension, height: size.dimension)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Color.harborBorder, lineWidth: 1)
        )
    }

    private var fallbackView: some View {
        Text(String(fallback.prefix(2)).uppercased())
            .font(size == .sm ? .caption2 : .caption)
            .fontWeight(.medium)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.harborPrimary)
    }
}

// MARK: - Skeleton Loading View

public struct HarborSkeleton: View {
    let width: CGFloat?
    let height: CGFloat
    let cornerRadius: CGFloat

    @State private var opacity: Double = 0.3

    public init(width: CGFloat? = nil, height: CGFloat = 16, cornerRadius: CGFloat = 4) {
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.harborMuted)
            .frame(width: width, height: height)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                    opacity = 0.6
                }
            }
    }
}

// MARK: - Empty State View

public struct HarborEmptyState: View {
    let icon: String
    let title: String
    let message: String?
    let actionLabel: String?
    let action: (() -> Void)?

    public init(
        icon: String,
        title: String,
        message: String? = nil,
        actionLabel: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionLabel = actionLabel
        self.action = action
    }

    public var body: some View {
        VStack(spacing: HarborSpacing.`4`) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.harborTextTertiary)

            Text(title)
                .font(HarborTypography.FontSize.xl)
                .fontWeight(.semibold)
                .foregroundColor(.harborTextPrimary)

            if let message = message {
                Text(message)
                    .font(HarborTypography.FontSize.base)
                    .foregroundColor(.harborTextSecondary)
                    .multilineTextAlignment(.center)
            }

            if let actionLabel = actionLabel, let action = action {
                Button(action: action) {
                    Text(actionLabel)
                }
                .buttonStyle(HarborButtonStyle.harbor())
            }
        }
        .padding(HarborSpacing.`8`)
    }
}

// MARK: - Shimmer Effect for Loading

public struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    public static let `default` = ShimmerModifier()

    public func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    LinearGradient(
                        gradient: Gradient(colors: [
                            .clear,
                            Color.white.opacity(0.4),
                            .clear
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 2)
                    .offset(x: -geometry.size.width + (geometry.size.width * 2 * phase))
                    .clipped()
                }
            )
            .mask(content)
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

public extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier.default)
    }
}

// MARK: - Liquid Card Animation

public struct LiquidCardModifier: ViewModifier {
    @State private var isPressed = false
    @State private var isHovered = false

    public static let `default` = LiquidCardModifier()

    public func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? 0.98 : (isHovered ? 1.01 : 1.0))
            .shadow(
                color: (isPressed || isHovered) ? Color.black.opacity(0.15) : Color.black.opacity(0.05),
                radius: isPressed ? 4 : (isHovered ? 12 : 8),
                x: 0,
                y: isPressed ? 2 : (isHovered ? 8 : 4)
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
            .animation(.easeInOut(duration: 0.2), value: isHovered)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded { _ in isPressed = false }
            )
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

public extension View {
    func liquidCard() -> some View {
        modifier(LiquidCardModifier.default)
    }
}

// MARK: - Status Indicator View

public struct HarborStatusIndicator: View {
    public enum Status {
        case success
        case warning
        case error
        case info
        case neutral
    }

    let status: Status
    let animated: Bool

    @State private var pulse: Bool = false

    public init(status: Status, animated: Bool = true) {
        self.status = status
        self.animated = animated
    }

    public var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(color.opacity(0.3), lineWidth: 4)
                    .scaleEffect(pulse ? 1.5 : 1.0)
                    .opacity(pulse ? 0 : 0.5)
            )
            .animation(
                animated ? Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: false) : .default,
                value: pulse
            )
            .onAppear {
                if animated { pulse = true }
            }
    }

    private var color: Color {
        switch status {
        case .success: return .harborCISuccess
        case .warning: return .harborSyncBehind
        case .error: return .harborCIFailure
        case .info: return .harborCIPending
        case .neutral: return .harborCIUnknown
        }
    }
}

// MARK: - List Row Animation

public struct AnimatedListRow<Content: View>: View {
    let content: Content
    let animation: Animation

    @State private var isVisible = false

    public init(
        animation: Animation = .spring(response: 0.3, dampingFraction: 0.8),
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.animation = animation
    }

    public var body: some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 10)
            .animation(animation, value: isVisible)
            .onAppear {
                isVisible = true
            }
    }
}

// MARK: - Smooth List Transition

public struct SmoothListView<Data: RandomAccessCollection, Content: View>: View where Data.Element: Identifiable {
    let data: Data
    @ViewBuilder let content: (Data.Element) -> Content

    public init(data: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.data = data
        self.content = content
    }

    public var body: some View {
        LazyVStack(spacing: HarborSpacing.`2`) {
            ForEach(data) { item in
                AnimatedListRow {
                    self.content(item)
                }
            }
        }
    }
}

public extension View {
    func smoothList<Data: RandomAccessCollection, Content: View>(
        data: Data,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) -> some View where Data.Element: Identifiable {
        SmoothListView(data: data, content: content)
    }
}
