import SwiftUI

/// 路由节点实时延迟迷你图。
struct LivePingView: View {
    @Environment(\.theme) private var theme
    let samples: [Double]
    let stats: PingStats?
    let pulse: Bool
    var tick: UInt = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let stats {
                HStack(spacing: 6) {
                    Circle()
                        .fill(color(for: stats.status))
                        .frame(width: 6, height: 6)
                        .scaleEffect(pulse ? 1.35 : 0.85)
                        .animation(.easeInOut(duration: 0.55), value: pulse)
                    Text("\(Int(stats.avgMs)) ms")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .monospacedDigit()
                        .id("ping-ms-\(tick)-\(stats.target)")
                    Text("±\(Int(stats.jitterMs))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !samples.isEmpty {
                GeometryReader { geo in
                    let maxV = max(samples.max() ?? 1, 1)
                    Path { path in
                        let w = geo.size.width
                        let h = geo.size.height
                        let step = w / CGFloat(max(samples.count - 1, 1))
                        for (i, v) in samples.enumerated() {
                            let x = CGFloat(i) * step
                            let y = h - CGFloat(v / maxV) * h
                            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                            else { path.addLine(to: CGPoint(x: x, y: y)) }
                        }
                    }
                    .stroke(theme.accent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
                .frame(height: 22)
                .id("ping-chart-\(tick)")
            }
        }
    }

    private func color(for status: PingQuality) -> Color {
        switch status {
        case .good: return .green
        case .warning: return .orange
        case .bad: return .red
        case .down: return .gray
        }
    }
}
