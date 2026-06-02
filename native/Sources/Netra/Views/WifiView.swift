import SwiftUI

struct WifiView: View {
  @EnvironmentObject private var app: AppState
  @EnvironmentObject private var prefs: AppPreferences
  @Environment(\.theme) private var theme
  @ObservedObject private var location = LocationAuthorizationService.shared

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      PageHeader(prefs.l10n(.wifiTitle), subtitle: wifiSubtitle) {
        Button {
          app.refreshWifi()
        } label: {
          Label(prefs.l10n(.wifiRefresh), systemImage: "arrow.clockwise")
        }
          .buttonStyle(FuturisticButtonStyle())
          .disabled(!location.canScanWifi)
      }
      .padding(.horizontal, 20)
      .padding(.top, 16)

      if !location.canScanWifi {
        locationBanner
          .padding(.horizontal, 20)
      }

      if location.canScanWifi, app.wifiNetworks.isEmpty {
        EmptyStateView(
          icon: "wifi.exclamationmark",
          title: prefs.l10n(.wifiSelectNetwork),
          message: prefs.l10n(.wifiInspectorHint)
        )
      } else {
        List(app.wifiNetworks, selection: $app.selectedWifiID) { net in
          HStack(spacing: 12) {
            SignalBadge(percent: net.signalPercent, connected: net.isConnected)
            VStack(alignment: .leading, spacing: 3) {
              HStack(spacing: 6) {
                Text(net.ssid.isEmpty ? "—" : net.ssid)
                  .fontWeight(net.isConnected ? .bold : .regular)
                  .lineLimit(1)
                if net.isConnected {
                  Text(prefs.l10n(.wifiConnected))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.green)
                }
              }
              if !net.bssid.isEmpty {
                HStack(spacing: 4) {
                  Text(net.bssid)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                  CopyIconButton(value: net.bssid, help: prefs.l10n(.copyBSSID))
                }
              }
            }
            Spacer()
            Text("\(net.signalPercent)%")
              .font(.caption.monospacedDigit().weight(.semibold))
              .foregroundStyle(WifiSignalStyle.color(percent: net.signalPercent))
          }
          .padding(.vertical, 3)
          .tag(net.id)
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
      }
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

  private var wifiSubtitle: String? {
    guard location.canScanWifi else { return nil }
    return String(format: prefs.l10n(.devicesCount), app.wifiNetworks.count)
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
    .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
  }
}

private struct SignalBadge: View {
  let percent: Int
  let connected: Bool

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(WifiSignalStyle.color(percent: percent).opacity(0.12))
      Image(systemName: connected ? "wifi" : "wifi.circle")
        .foregroundStyle(connected ? .green : WifiSignalStyle.color(percent: percent))
    }
    .frame(width: 34, height: 34)
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
