import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var prefs: AppPreferences

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(prefs.l10n(.historyTitle)).font(.largeTitle.bold())
                Spacer()
                Button(prefs.l10n(.historyClear)) {
                    app.clearHistory()
                }
                .buttonStyle(FuturisticButtonStyle())
                .disabled(app.snapshots.isEmpty)
            }
            if app.snapshots.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 38))
                        .foregroundStyle(.secondary)
                    Text(prefs.l10n(.historyEmpty))
                        .font(.headline)
                    Text(prefs.l10n(.historyEmptyHint))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(app.snapshots) { snap in
                    VStack(alignment: .leading) {
                        Text(snap.networkName).font(.headline)
                        Text("\(String(format: prefs.l10n(.historyDeviceCount), snap.devices.count)) · \(snap.scannedAt.formatted())")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
    }
}
