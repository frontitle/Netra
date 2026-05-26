import SwiftUI

struct WifiInspectorView: View {
  @EnvironmentObject private var prefs: AppPreferences
  @Environment(\.theme) private var theme

  let network: WifiNetwork?

  var body: some View {
    Group {
      if let network {
        ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            header(network)
            params(network)
          }
          .padding(20)
        }
      } else {
        VStack(spacing: 12) {
          Image(systemName: "wifi")
            .font(.system(size: 36))
            .foregroundStyle(theme.accent.opacity(0.6))
          Text(prefs.l10n(.wifiSelectNetwork))
            .font(.headline)
          Text(prefs.l10n(.wifiInspectorHint))
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .background(.ultraThinMaterial)
  }

  private func header(_ net: WifiNetwork) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(net.ssid)
          .font(.system(.title2, design: .rounded).weight(.bold))
        if net.isConnected {
          Text("●")
            .foregroundStyle(.green)
            .help("Connected")
        }
      }
      if !net.bssid.isEmpty {
        Text(net.bssid)
          .font(.system(.body, design: .monospaced))
          .foregroundStyle(theme.accent)
      }
    }
  }

  private func params(_ net: WifiNetwork) -> some View {
    let lang = prefs.language
  return VStack(alignment: .leading, spacing: 10) {
      WifiParamRow(title: prefs.l10n(.wifiSignal), value: "\(net.signalPercent)% (\(net.signal))", help: nil)
      WifiParamRow(title: prefs.l10n(.wifiChannel), value: net.channel, help: nil)
      WifiParamRow(title: prefs.l10n(.wifiBand), value: net.band, help: nil)
      WifiParamRow(title: prefs.l10n(.wifiSecurity), value: net.security, help: nil)
      WifiParamRow(title: "BSSID", value: net.bssid, help: WifiParamHelp.text("bssid", language: lang), monospace: true)
      WifiParamRow(title: prefs.l10n(.wifiSSID), value: net.ssid, help: nil)
      WifiParamRow(title: "PHY", value: net.phyMode, help: WifiParamHelp.text("phyMode", language: lang))
      WifiParamRow(title: "Noise", value: net.noise ?? "", help: WifiParamHelp.text("noise", language: lang))
      WifiParamRow(title: "Width", value: net.channelWidth ?? "", help: WifiParamHelp.text("channelWidth", language: lang))
      WifiParamRow(title: prefs.l10n(.metaVendor), value: net.routerVendor, help: WifiParamHelp.text("routerVendor", language: lang))
      WifiParamRow(title: "IBSS", value: (net.isIBSS ?? false) ? "Yes" : "No", help: WifiParamHelp.text("ibss", language: lang))
    }
    .padding(12)
    .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
  }
}
