import SwiftUI

struct WifiView: View {
  @EnvironmentObject private var app: AppState
  @EnvironmentObject private var prefs: AppPreferences
  @ObservedObject private var location = LocationAuthorizationService.shared

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text(prefs.l10n(.wifiTitle)).font(.system(.title, design: .rounded).weight(.bold))
        Spacer()
        Button(prefs.l10n(.wifiRefresh)) { scanWifi() }
          .buttonStyle(FuturisticButtonStyle())
      }
      .padding(.horizontal, 20)
      .padding(.top, 16)

      if !location.canScanWifi {
        locationBanner
          .padding(.horizontal, 20)
      }

      List(app.wifiNetworks, selection: $app.selectedWifiID) { net in
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text(net.ssid).fontWeight(net.isConnected ? .bold : .regular)
            Text(net.bssid).font(.caption.monospaced()).foregroundStyle(.secondary)
          }
          Spacer()
          Text("\(net.signalPercent)%")
            .font(.caption.monospacedDigit())
        }
        .tag(net.id)
      }
      .listStyle(.inset(alternatesRowBackgrounds: true))
    }
    .padding(.horizontal, 12)
    .padding(.bottom, 12)
    .onAppear {
      location.refreshStatus()
      if location.status == .notDetermined {
        location.requestAuthorization()
      }
    }
  }

  private var locationBanner: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label(prefs.l10n(.wifiLocationTitle), systemImage: "location.slash")
        .font(.headline)
        .foregroundStyle(.orange)
      Text(prefs.l10n(.wifiLocationBody))
        .font(.callout)
        .foregroundStyle(.secondary)
      HStack(spacing: 10) {
        Button(prefs.l10n(.wifiGrantAccess)) { location.requestAuthorization() }
          .buttonStyle(FuturisticButtonStyle())
        Button(prefs.l10n(.wifiOpenSettings)) { location.openSystemLocationSettings() }
          .buttonStyle(FuturisticButtonStyle(prominent: true))
      }
    }
    .padding(14)
    .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
  }

  private func scanWifi() {
    guard location.canScanWifi else {
      if location.status == .notDetermined {
        location.requestAuthorization()
      } else {
        location.openSystemLocationSettings()
      }
      return
    }
    app.wifiNetworks = WifiScanner.scan()
    if app.selectedWifiID == nil {
      app.selectedWifiID = app.wifiNetworks.first?.id
    }
  }
}
