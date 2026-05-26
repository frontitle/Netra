import SwiftUI

struct QualityView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var prefs: AppPreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(prefs.l10n(.qualityTitle)).font(.largeTitle.bold())
                Spacer()
                Button(app.qualityLoading ? prefs.l10n(.qualityRunning) : prefs.l10n(.qualityStart)) {
                    Task { await app.runQualityCheck() }
                }
                .disabled(app.qualityLoading)
            }
            if let q = app.quality {
                Text(q.diagnosis).font(.headline)
                livePingCard(prefs.l10n(.qualityGateway), app.liveQualityStats(fallback: q.gateway))
                ForEach(q.external) { livePingCard($0.label, app.liveQualityStats(fallback: $0)) }
                if !q.devices.isEmpty {
                    Text(prefs.l10n(.qualityInternalSample)).font(.subheadline).foregroundStyle(.secondary)
                    ForEach(q.devices) { livePingCard($0.target, app.liveQualityStats(fallback: $0)) }
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "waveform.path.ecg").font(.largeTitle).foregroundStyle(.secondary)
                    Text(prefs.l10n(.qualityNotRun)).font(.headline)
                    Text(prefs.l10n(.qualityHint)).font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Spacer()
        }
        .padding()
        .onAppear { app.syncPingLoopsForCurrentSection() }
    }

    private func livePingCard(_ title: String, _ stats: PingStats) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text("\(Int(stats.packetLoss))% loss")
                    .font(.caption)
                    .foregroundStyle(stats.status == .good ? .green : (stats.status == .warning ? .orange : .red))
            }
            LivePingView(
                samples: app.qualityPingHistory[stats.target] ?? [],
                stats: stats,
                pulse: app.qualityPingPulse
            )
            .id("\(stats.target)-\(app.qualityPingTick)")
        }
        .padding(12)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }
}
