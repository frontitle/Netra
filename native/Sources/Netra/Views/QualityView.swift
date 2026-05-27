import SwiftUI

struct QualityView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var prefs: AppPreferences
    @Environment(\.theme) private var theme

    private let lanColumns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
    private let wanColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(prefs.l10n(.qualityTitle)).font(.largeTitle.bold())
                    Spacer()
                    Button(app.qualityLoading ? prefs.l10n(.qualityRunning) : prefs.l10n(.qualityStart)) {
                        Task { await app.runQualityCheck() }
                    }
                    .buttonStyle(FuturisticButtonStyle(prominent: true))
                    .disabled(app.qualityLoading)
                }

                if let q = app.quality {
                    Text(q.diagnosis)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))

                    sectionLabel(prefs.l10n(.qualityGateway))
                    pingCard(
                        title: prefs.l10n(.qualityCurrentGateway),
                        subtitle: q.gateway.target,
                        stats: app.liveQualityStats(fallback: q.gateway),
                        prominent: true
                    )

                    sectionLabel("Internet")
                    LazyVGrid(columns: wanColumns, spacing: 10) {
                        ForEach(q.external) { target in
                            pingCard(
                                title: target.label,
                                subtitle: target.target,
                                stats: app.liveQualityStats(fallback: target),
                                prominent: false
                            )
                        }
                    }

                    if !q.devices.isEmpty {
                        sectionLabel(prefs.l10n(.qualityInternalSample))
                        LazyVGrid(columns: lanColumns, spacing: 10) {
                            ForEach(q.devices) { target in
                                pingCard(
                                    title: displayLabel(for: target),
                                    subtitle: target.target,
                                    stats: app.liveQualityStats(fallback: target),
                                    prominent: false
                                )
                            }
                        }
                    }
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 40))
                            .foregroundStyle(theme.accent.opacity(0.5))
                        Text(prefs.l10n(.qualityNotRun)).font(.headline)
                        Text(prefs.l10n(.qualityHint))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 48)
                }
            }
            .padding(20)
        }
        .onAppear { app.syncPingLoopsForCurrentSection() }
        .onDisappear { app.syncPingLoopsForCurrentSection() }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private func displayLabel(for stats: PingStats) -> String {
        if let device = app.devices.first(where: { $0.ip == stats.target }),
           device.hostname != "—", !device.hostname.isEmpty {
            return device.hostname
        }
        return stats.label == stats.target ? stats.target : stats.label
    }

    private func pingCard(title: String, subtitle: String, stats: PingStats, prominent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(prominent ? .subheadline.weight(.semibold) : .caption.weight(.semibold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                statusDot(stats.status)
            }
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(latencyText(stats))
                    .font(.system(prominent ? .title3 : .body, design: .rounded).weight(.bold).monospacedDigit())
                Text("ms")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("· \(connectivityText(stats))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(lossColor(stats.status))
                Spacer()
                Text(String(format: prefs.l10n(.qualityConnectivityFormat), connectivityValue(stats)))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(lossColor(stats.status))
            }
            LivePingView(
                samples: app.qualityPingHistory[stats.target] ?? [],
                stats: stats,
                pulse: app.qualityPingPulse,
                tick: app.qualityPingTick
            )
        }
        .padding(prominent ? 14 : 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            prominent ? theme.accent.opacity(0.08) : Color.white.opacity(0.05),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(prominent ? theme.accent.opacity(0.35) : Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func statusDot(_ status: PingQuality) -> some View {
        Circle()
            .fill(lossColor(status))
            .frame(width: 8, height: 8)
    }

    private func lossColor(_ status: PingQuality) -> Color {
        switch status {
        case .good: return .green
        case .warning: return .orange
        case .bad, .down: return .red
        }
    }

    private func latencyText(_ stats: PingStats) -> String {
        if stats.packetLoss >= 100 { return "—" }
        if stats.avgMs < 10 { return String(format: "%.1f", stats.avgMs) }
        return "\(Int(stats.avgMs.rounded()))"
    }

    private func connectivityValue(_ stats: PingStats) -> Int {
        max(0, min(100, Int((100 - stats.packetLoss).rounded())))
    }

    private func connectivityText(_ stats: PingStats) -> String {
        "\(connectivityValue(stats))%"
    }
}
