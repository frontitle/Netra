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
            securityBadges(network)
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
          Text(prefs.l10n(.wifiConnected))
            .font(.caption)
            .foregroundStyle(.green)
        }
      }
      if !net.bssid.isEmpty {
        HStack(spacing: 4) {
          Text(net.bssid)
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(theme.accent)
          CopyIconButton(value: net.bssid, help: prefs.l10n(.copyBSSID))
        }
      }
    }
  }

  private func securityBadges(_ net: WifiNetwork) -> some View {
    HStack(spacing: 14) {
      Label {
        Text(net.requiresPassword ? prefs.l10n(.wifiHasPassword) : prefs.l10n(.wifiOpenNetwork))
          .font(.caption)
      } icon: {
        Image(systemName: net.requiresPassword ? "lock.fill" : "lock.open")
          .foregroundStyle(net.requiresPassword ? .orange : .green)
      }
      if net.supportsWPS {
        Label(prefs.l10n(.wifiSupportsWPS), systemImage: "wifi.router")
          .font(.caption)
          .foregroundStyle(.secondary)
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
      WifiParamRow(title: prefs.l10n(.wifiEncryption), value: net.encryptionType, help: nil)
      WifiParamRow(title: prefs.l10n(.wifiAPName), value: net.apName, help: WifiParamHelp.text("apName", language: lang))
      WifiParamRow(title: prefs.l10n(.wifiMinRate), value: net.minRateMbps.isEmpty ? "—" : "\(net.minRateMbps) Mbps", help: nil)
      WifiParamRow(title: prefs.l10n(.wifiBasicRates), value: net.basicRatesMbps.isEmpty ? "—" : "\(net.basicRatesMbps) Mbps", help: nil)
      WifiParamRow(title: prefs.l10n(.wifiMaxRate), value: net.maxRateMbps.isEmpty ? "—" : "\(net.maxRateMbps) Mbps", help: nil)
      copyableRow(title: prefs.l10n(.wifiSSID), value: net.ssid)
      copyableRow(title: "BSSID", value: net.bssid, help: WifiParamHelp.text("bssid", language: lang))
      WifiParamRow(title: "PHY", value: net.phyMode, help: WifiParamHelp.text("phyMode", language: lang))
      WifiParamRow(title: "Noise", value: net.noise ?? "", help: WifiParamHelp.text("noise", language: lang))
      WifiParamRow(title: "Width", value: net.channelWidth ?? "", help: WifiParamHelp.text("channelWidth", language: lang))
      WifiParamRow(title: prefs.l10n(.metaVendor), value: net.routerVendor, help: WifiParamHelp.text("routerVendor", language: lang))
      if !net.countryCode.isEmpty {
        WifiParamRow(title: prefs.l10n(.wifiCountry), value: net.countryCode, help: nil)
      }
      WifiParamRow(title: "IBSS", value: (net.isIBSS ?? false) ? prefs.l10n(.yes) : prefs.l10n(.no), help: WifiParamHelp.text("ibss", language: lang))
    }
    .padding(12)
    .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
  }

  private func copyableRow(title: String, value: String, help: String? = nil) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(width: 108, alignment: .leading)
      Text(value.isEmpty ? "—" : value)
        .font(.callout)
        .lineLimit(3)
      if let help, !help.isEmpty { HelpHintView(help: help) }
      CopyIconButton(value: value)
      Spacer(minLength: 0)
    }
  }
}
