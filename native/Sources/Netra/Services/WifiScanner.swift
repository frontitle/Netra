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
                return WifiNetwork(
                    ssid: ssid,
                    bssid: bssid,
                    routerVendor: OUILookup.vendor(for: bssid),
                    channel: net.wlanChannel.map { String($0.channelNumber) } ?? "",
                    band: bandLabel(net.wlanChannel?.channelBand),
                    signal: "\(rssi) dBm",
                    signalPercent: percent,
                    security: networkSecurity(net),
                    phyMode: "",
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

    private static func networkSecurity(_ net: CWNetwork) -> String {
        if net.supportsSecurity(.wpa3Personal) { return "WPA3 Personal" }
        if net.supportsSecurity(.wpa2Personal) { return "WPA2 Personal" }
        if net.supportsSecurity(.wpaPersonal) { return "WPA Personal" }
        if net.supportsSecurity(.dynamicWEP) { return "WEP" }
        if net.supportsSecurity(.none) { return "Open" }
        return "Secured"
    }
}
