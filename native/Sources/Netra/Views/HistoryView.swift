import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var prefs: AppPreferences

    var body: some View {
        VStack(alignment: .leading) {
            Text(prefs.l10n(.historyTitle)).font(.largeTitle.bold())
            List(app.snapshots) { snap in
                VStack(alignment: .leading) {
                    Text(snap.networkName).font(.headline)
                    Text("\(String(format: prefs.l10n(.historyDeviceCount), snap.devices.count)) · \(snap.scannedAt.formatted())")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }
}
