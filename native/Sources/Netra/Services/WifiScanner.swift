import CoreWLAN
import Foundation

enum WifiScanner {
    static func scan() -> [WifiNetwork] {
        if let core = scanCoreWLAN(), !core.isEmpty { return core }
        return scanSystemProfiler()
    }

    private static func scanCoreWLAN() -> [WifiNetwork]? {
        guard let iface = CWWiFiClient.shared().interface() else { return nil }
        do {
            let networks = try iface.scanForNetworks(withSSID: nil, includeHidden: true)
            let connected = iface.ssid() ?? ""
            return networks.map { net in
                let ssid = net.ssid ?? "Hidden Network"
                let bssid = net.bssid ?? ""
                let rssi = net.rssiValue
                let signalScore = (Double(rssi + 90) / 60.0) * 100.0
                let percent = max(0, min(100, Int(signalScore)))
                let ch = net.wlanChannel
                return WifiNetwork(
                    ssid: ssid,
                    bssid: bssid,
                    routerVendor: OUILookup.vendor(for: bssid),
                    channel: ch.map { String($0.channelNumber) } ?? "",
                    band: bandLabel(ch?.channelBand),
                    signal: "\(rssi) dBm",
                    signalPercent: percent,
                    security: networkSecurity(net),
                    phyMode: phyModeLabel(ch),
                    noise: "\(net.noiseMeasurement) dBm",
                    channelWidth: channelWidthLabel(ch),
                    isIBSS: net.ibss,
                    isConnected: ssid == connected
                )
            }.sorted { $0.signalPercent > $1.signalPercent }
        } catch {
            return nil
        }
    }

    private static func scanSystemProfiler() -> [WifiNetwork] {
        guard let output = ShellRunner.run("/usr/sbin/system_profiler", ["SPAirPortDataType"]) else { return [] }
        var results: [WifiNetwork] = []
        var currentSSID = ""
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasSuffix(":"), !trimmed.hasPrefix(" "), trimmed.count < 40 {
                currentSSID = trimmed.dropLast().trimmingCharacters(in: .whitespaces)
            }
            if trimmed.hasPrefix("Channel:"), !currentSSID.isEmpty {
                results.append(WifiNetwork(
                    ssid: currentSSID,
                    bssid: "",
                    routerVendor: "",
                    channel: trimmed.replacingOccurrences(of: "Channel:", with: "").trimmingCharacters(in: .whitespaces),
                    band: "",
                    signal: "",
                    signalPercent: 0,
                    security: "",
                    phyMode: "",
                    noise: "",
                    channelWidth: "",
                    isIBSS: false,
                    isConnected: line.contains("Current Network")
                ))
            }
        }
        return results
    }

    private static func bandLabel(_ band: CWChannelBand?) -> String {
        switch band {
        case .band2GHz: return "2.4 GHz"
        case .band5GHz: return "5 GHz"
        case .band6GHz: return "6 GHz"
        default: return ""
        }
    }

    private static func phyModeLabel(_ channel: CWChannel?) -> String {
        guard let channel else { return "" }
        if #available(macOS 14.0, *) {
            return channel.channelBand == .band6GHz ? "802.11ax" : "802.11ac/n"
        }
        return channel.channelBand == .band2GHz ? "802.11n" : "802.11ac"
    }

    private static func channelWidthLabel(_ channel: CWChannel?) -> String {
        guard let channel else { return "" }
        switch channel.channelWidth {
        case .width20MHz: return "20 MHz"
        case .width40MHz: return "40 MHz"
        case .width80MHz: return "80 MHz"
        case .width160MHz: return "160 MHz"
        default: return ""
        }
    }

    private static func networkSecurity(_ net: CWNetwork) -> String {
        if net.supportsSecurity(.wpa3Personal) { return "WPA3 Personal" }
        if net.supportsSecurity(.wpa2Personal) { return "WPA2 Personal" }
        if net.supportsSecurity(.wpaPersonal) { return "WPA Personal" }
        if net.supportsSecurity(.dynamicWEP) { return "WEP" }
        if net.supportsSecurity(.none) { return "Open" }
        return "Secured"
    }
}
