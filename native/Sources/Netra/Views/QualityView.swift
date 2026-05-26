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
                pingCard(prefs.l10n(.qualityGateway), q.gateway)
                ForEach(q.external) { pingCard($0.label, $0) }
                if !q.devices.isEmpty {
                    Text(prefs.l10n(.qualityInternalSample)).font(.subheadline).foregroundStyle(.secondary)
                    ForEach(q.devices) { pingCard($0.target, $0) }
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
    }

    private func pingCard(_ title: String, _ stats: PingStats) -> some View {
        HStack {
            Text(title).frame(width: 120, alignment: .leading)
            Text("\(Int(stats.avgMs)) ms avg")
            Spacer()
            Text("\(Int(stats.packetLoss))% loss")
                .foregroundStyle(stats.status == .good ? .green : (stats.status == .warning ? .orange : .red))
        }
        .padding(10)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }
}
