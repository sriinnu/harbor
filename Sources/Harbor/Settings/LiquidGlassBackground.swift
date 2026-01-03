import SwiftUI

/// Beautiful liquid glass background with animated gradient
struct LiquidGlassBackground: View {
    @State private var animateGradient = false

    var body: some View {
        LinearGradient(
            colors: [
                Color.blue.opacity(0.08),
                Color.purple.opacity(0.08),
                Color.cyan.opacity(0.08),
                Color.pink.opacity(0.06)
            ],
            startPoint: animateGradient ? .topLeading : .bottomLeading,
            endPoint: animateGradient ? .bottomTrailing : .topTrailing
        )
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                animateGradient = true
            }
        }
    }
}

/// Glass card with blur effect and hover animation
struct GlassCard<Content: View>: View {
    @ViewBuilder let content: Content
    @State private var isHovered = false

    var body: some View {
        content
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.3),
                                        Color.white.opacity(0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
            )
            .scaleEffect(isHovered ? 1.01 : 1.0)
            .shadow(color: Color.blue.opacity(isHovered ? 0.2 : 0), radius: 15, x: 0, y: 8)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

/// Wrapper for settings content with liquid background
struct LiquidSettingsContainer<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            LiquidGlassBackground()

            ScrollView {
                VStack(spacing: 16) {
                    content
                }
                .padding(20)
            }
        }
    }
}
