import SwiftUI

struct WifiView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var prefs: AppPreferences

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(prefs.l10n(.wifiTitle)).font(.system(.title, design: .rounded).weight(.bold))
                Spacer()
                Button(prefs.l10n(.wifiRefresh)) { app.wifiNetworks = WifiScanner.scan() }
                    .buttonStyle(FuturisticButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            Table(app.wifiNetworks) {
                TableColumn(prefs.l10n(.wifiSSID)) { Text($0.ssid).bold($0.isConnected) }
                TableColumn(prefs.l10n(.wifiSignal)) { Text("\($0.signalPercent)%") }
                TableColumn(prefs.l10n(.wifiChannel)) { Text($0.channel) }
                TableColumn(prefs.l10n(.wifiBand)) { Text($0.band) }
                TableColumn(prefs.l10n(.wifiSecurity)) { Text($0.security) }
                TableColumn("BSSID") { Text($0.bssid).font(.caption.monospaced()) }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }
}

private extension Text {
    func bold(_ on: Bool) -> Text {
        on ? self.bold() : self
    }
}
