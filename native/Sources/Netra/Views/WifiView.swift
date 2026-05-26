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
        Button(prefs.l10n(.wifiRefresh)) { app.refreshWifi() }
          .buttonStyle(FuturisticButtonStyle())
          .disabled(!location.canScanWifi)
      }
      .padding(.horizontal, 20)
      .padding(.top, 16)

      if !location.canScanWifi {
        locationBanner
          .padding(.horizontal, 20)
      }

      List(app.wifiNetworks, selection: $app.selectedWifiID) { net in
        HStack(spacing: 10) {
          Image(systemName: net.isConnected ? "wifi" : "wifi.circle")
            .foregroundStyle(net.isConnected ? .green : WifiSignalStyle.color(percent: net.signalPercent))
          VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
              Text(net.ssid).fontWeight(net.isConnected ? .bold : .regular)
              if net.isConnected {
                Text(prefs.l10n(.wifiConnected))
                  .font(.caption2)
                  .foregroundStyle(.green)
              }
            }
            if !net.bssid.isEmpty {
              Text(net.bssid).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
          }
          Spacer()
          Text("\(net.signalPercent)%")
            .font(.caption.monospacedDigit().weight(.semibold))
            .foregroundStyle(WifiSignalStyle.color(percent: net.signalPercent))
        }
        .tag(net.id)
      }
      .listStyle(.inset(alternatesRowBackgrounds: true))
    }
    .padding(.horizontal, 12)
    .padding(.bottom, 12)
    .onAppear {
      location.onAuthorized = { app.refreshWifi() }
      location.refreshStatus()
      if location.status == .notDetermined {
        location.requestAuthorization()
      } else if location.canScanWifi {
        app.refreshWifi()
      }
    }
    .onChange(of: location.status) { status in
      if LocationAuthorizationService.canScanWifi(status: status) {
        app.refreshWifi()
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
}

enum WifiSignalStyle {
  static func color(percent: Int) -> Color {
    switch percent {
    case 70...: return .green
    case 45..<70: return .yellow
    case 25..<45: return .orange
    default: return .red
    }
  }
}
