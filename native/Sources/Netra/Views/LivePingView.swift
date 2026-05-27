import SwiftUI
import Foundation

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
                    Text(pingText(stats))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .monospacedDigit()
                        .id("ping-ms-\(tick)-\(stats.target)")
                    Text(jitterText(stats))
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

    private func pingText(_ stats: PingStats) -> String {
        if stats.packetLoss >= 100 { return "超时" }
        if stats.avgMs < 10 { return String(format: "%.1f ms", stats.avgMs) }
        return "\(Int(stats.avgMs.rounded())) ms"
    }

    private func jitterText(_ stats: PingStats) -> String {
        if stats.packetLoss >= 100 { return "loss 100%" }
        if stats.jitterMs < 10 { return String(format: "±%.1f", stats.jitterMs) }
        return "±\(Int(stats.jitterMs.rounded()))"
    }
}
