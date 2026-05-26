import SwiftUI

enum AppTheme {
    static func background(theme: ThemeColors, dark: Bool) -> some View {
        ZStack {
            if dark {
                LinearGradient(
                    colors: [
                        Color(red: 0.04, green: 0.06, blue: 0.12),
                        Color(red: 0.08, green: 0.1, blue: 0.18),
                        Color(red: 0.05, green: 0.08, blue: 0.14),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                RadialGradient(
                    colors: [theme.accent.opacity(0.12), .clear],
                    center: .topTrailing,
                    startRadius: 40,
                    endRadius: 480
                )
                RadialGradient(
                    colors: [Color.purple.opacity(0.08), .clear],
                    center: .bottomLeading,
                    startRadius: 20,
                    endRadius: 400
                )
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.94, green: 0.95, blue: 0.98),
                        Color(red: 0.88, green: 0.91, blue: 0.96),
                        Color(red: 0.92, green: 0.94, blue: 0.99),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                RadialGradient(
                    colors: [theme.accent.opacity(0.08), .clear],
                    center: .topTrailing,
                    startRadius: 40,
                    endRadius: 480
                )
            }
        }
        .ignoresSafeArea()
    }

    static func glassPanel(cornerRadius: CGFloat = 14, theme: ThemeColors) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [theme.accent.opacity(0.5), .white.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.2), radius: 24, y: 12)
    }
}

struct FuturisticButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded).weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background {
                if prominent {
                    Capsule().fill(
                        LinearGradient(colors: [theme.accent, theme.accentDim], startPoint: .top, endPoint: .bottom)
                    )
                } else {
                    Capsule().fill(.white.opacity(0.08))
                }
            }
            .foregroundStyle(prominent ? .white : .primary)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}
