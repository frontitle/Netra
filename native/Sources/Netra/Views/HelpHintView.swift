import SwiftUI

struct HelpHintView: View {
  let help: String

  var body: some View {
    Image(systemName: "questionmark.circle")
      .font(.caption)
      .foregroundStyle(.secondary)
      .help(help)
  }
}

struct WifiParamRow: View {
  let title: String
  let value: String
  let help: String?
  var monospace = false

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(width: 108, alignment: .leading)
      Text(value.isEmpty ? "—" : value)
        .font(monospace ? .system(.callout, design: .monospaced) : .callout)
        .lineLimit(3)
      if let help, !help.isEmpty {
        HelpHintView(help: help)
      }
      Spacer(minLength: 0)
    }
  }
}

enum WifiParamHelp {
  static func text(_ key: String, language: AppLanguage) -> String {
    let zh: [String: String] = [
      "bssid": "BSSID 是接入点的物理 MAC 地址，用于识别路由器硬件。",
      "noise": "噪声水平（dBm）越低越好；过高会导致无线速率下降。",
      "channelWidth": "信道宽度越大，理论吞吐量越高，但更易受干扰。",
      "phyMode": "PHY 模式表示 Wi-Fi 物理层协议代际（如 802.11ac/ax）。",
      "ibss": "IBSS（Ad-hoc）为设备自组网模式，非常见家庭路由器场景。",
      "routerVendor": "根据 BSSID 前缀 OUI 推断的网卡/设备厂商。",
    ]
    let en: [String: String] = [
      "bssid": "BSSID is the access point hardware MAC used to identify the router.",
      "noise": "Noise floor (dBm); lower is better. High noise reduces wireless throughput.",
      "channelWidth": "Channel width; wider channels can yield higher throughput but more interference.",
      "phyMode": "PHY mode indicates the Wi-Fi physical-layer generation (e.g. 802.11ac/ax).",
      "ibss": "IBSS (Ad-hoc) is a peer-to-peer Wi-Fi mode, uncommon on home routers.",
      "routerVendor": "Vendor inferred from the BSSID OUI prefix.",
    ]
    let table = language == .zhHans ? zh : en
    return table[key] ?? ""
  }
}
