import SwiftUI

enum AppTheme {
    static func background(theme: ThemeColors, dark: Bool) -> some View {
        LinearGradient(
            colors: dark
                ? [
                    Color(red: 0.06, green: 0.07, blue: 0.10),
                    Color(red: 0.08, green: 0.09, blue: 0.13),
                    Color(red: 0.05, green: 0.07, blue: 0.11),
                ]
                : [
                    Color(red: 0.96, green: 0.97, blue: 0.98),
                    Color(red: 0.91, green: 0.94, blue: 0.97),
                    Color(red: 0.94, green: 0.96, blue: 0.98),
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    static func glassPanel(cornerRadius: CGFloat = 8, theme: ThemeColors) -> some View {
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
            .shadow(color: .black.opacity(0.16), radius: 16, y: 8)
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
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(
                        LinearGradient(colors: [theme.accent, theme.accentDim], startPoint: .top, endPoint: .bottom)
                    )
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.08))
                }
            }
            .foregroundStyle(prominent ? .white : .primary)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct PageHeader<Action: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder var action: Action

    init(_ title: String, subtitle: String? = nil, @ViewBuilder action: () -> Action) {
        self.title = title
        self.subtitle = subtitle
        self.action = action()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            action
        }
    }
}

struct EmptyStateView: View {
    @Environment(\.theme) private var theme
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 34))
                .foregroundStyle(theme.accent.opacity(0.55))
            Text(title)
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 44)
    }
}
