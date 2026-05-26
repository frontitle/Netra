import CoreWLAN
import Foundation

enum WifiScanner {
    static func scan() -> [WifiNetwork] {
        let connectedBSSID = CWWiFiClient.shared().interface()?.bssid() ?? ""
        var list = scanCoreWLAN() ?? []
        if list.isEmpty {
            list = scanSystemProfiler()
        }
        annotateAPRoles(&list, connectedBSSID: connectedBSSID)
        return sortNetworks(list)
    }

    private static func scanCoreWLAN() -> [WifiNetwork]? {
        guard let iface = CWWiFiClient.shared().interface() else { return nil }
        do {
            let networks = try iface.scanForNetworks(withSSID: nil, includeHidden: true)
            let connectedSSID = iface.ssid() ?? ""
            let connectedBSSID = iface.bssid() ?? ""
            return networks.map { mapNetwork($0, connectedSSID: connectedSSID, connectedBSSID: connectedBSSID) }
        } catch {
            return nil
        }
    }

    private static func mapNetwork(_ net: CWNetwork, connectedSSID: String, connectedBSSID: String) -> WifiNetwork {
        let ssid = net.ssid ?? "Hidden Network"
        let bssid = net.bssid ?? ""
        let rssi = net.rssiValue
        let signalScore = (Double(rssi + 90) / 60.0) * 100.0
        let percent = max(0, min(100, Int(signalScore)))
        let ch = net.wlanChannel
        let security = networkSecurity(net)
        let requiresPassword = !net.supportsSecurity(.none)
        let isConnected = (!connectedSSID.isEmpty && ssid == connectedSSID)
            || (!connectedBSSID.isEmpty && bssid.caseInsensitiveCompare(connectedBSSID) == .orderedSame)
        let apName = ""
        let rates = estimateRates(channel: ch, phy: phyModeLabel(ch))
        return WifiNetwork(
            ssid: ssid,
            bssid: bssid,
            routerVendor: OUILookup.vendor(for: bssid),
            channel: ch.map { String($0.channelNumber) } ?? "",
            band: bandLabel(ch?.channelBand),
            signal: "\(rssi) dBm",
            signalPercent: percent,
            rssi: rssi,
            security: security,
            encryptionType: encryptionLabel(net),
            phyMode: phyModeLabel(ch),
            noise: "\(net.noiseMeasurement) dBm",
            channelWidth: channelWidthLabel(ch),
            isIBSS: net.ibss,
            isConnected: isConnected,
            requiresPassword: requiresPassword,
            supportsWPS: supportsWPS(net),
            apName: apName,
            minRateMbps: rates.min,
            basicRatesMbps: rates.basic,
            maxRateMbps: rates.max,
            countryCode: net.countryCode ?? ""
        )
    }

    /// 已连接置顶，其余按信号强度降序。
    static func sortNetworks(_ networks: [WifiNetwork]) -> [WifiNetwork] {
        networks.sorted { a, b in
            if a.isConnected != b.isConnected { return a.isConnected }
            if a.rssi != b.rssi { return a.rssi > b.rssi }
            return a.ssid.localizedStandardCompare(b.ssid) == .orderedAscending
        }
    }

    /// 仅为明确的子 AP / 中继 / Mesh 从节点填写；主网关留空（详情页不展示）。
    private static func annotateAPRoles(_ networks: inout [WifiNetwork], connectedBSSID: String) {
        var groups: [String: [Int]] = [:]
        for (index, net) in networks.enumerated() {
            groups[net.ssid, default: []].append(index)
        }

        for (_, indices) in groups {
            if indices.count == 1 {
                let i = indices[0]
                if isSubAPDevice(networks[i], connectedBSSID: connectedBSSID, sameSSIDCount: 1) {
                    networks[i].apName = subAPDisplayName(for: networks[i])
                } else {
                    networks[i].apName = ""
                }
                continue
            }
            // 同一 SSID 多个 BSSID：已连接的一般为主路径，其余视为子 AP
            for i in indices {
                if isSubAPDevice(networks[i], connectedBSSID: connectedBSSID, sameSSIDCount: indices.count) {
                    networks[i].apName = subAPDisplayName(for: networks[i])
                } else {
                    networks[i].apName = ""
                }
            }
        }
    }

    private static func isSubAPDevice(_ net: WifiNetwork, connectedBSSID: String, sameSSIDCount: Int) -> Bool {
        if net.isIBSS == true { return true }
        if isExtenderSSID(net.ssid) { return true }
        // 同 SSID 多 BSSID：非当前连接的其它接入点视为网关下的子 AP
        if sameSSIDCount > 1, !net.bssid.isEmpty, !connectedBSSID.isEmpty,
           net.bssid.caseInsensitiveCompare(connectedBSSID) != .orderedSame {
            return true
        }
        return false
    }

    private static func isExtenderSSID(_ ssid: String) -> Bool {
        let lower = ssid.lowercased()
        let markers = ["_ext", "-ext", ".ext", " ext", "_rpt", "repeater", "extender", "_repeater", "_rp"]
        return markers.contains { lower.contains($0) }
    }

    private static func subAPDisplayName(for net: WifiNetwork) -> String {
        if net.isIBSS == true { return "Ad-hoc (\(net.ssid))" }
        let vendor = net.routerVendor
        if vendor != "Unknown vendor", !vendor.isEmpty {
            return "\(net.ssid) · \(vendor)"
        }
        return net.ssid
    }

    private static func estimateRates(channel: CWChannel?, phy: String) -> (min: String, basic: String, max: String) {
        guard let channel else { return ("—", "—", "—") }
        switch channel.channelBand {
        case .band6GHz:
            return ("6", "6, 12, 24", "2400")
        case .band5GHz:
            return ("6", "6, 12, 24", "866")
        case .band2GHz:
            return ("1", "1, 2, 5.5, 11", "144")
        default:
            return ("1", "1, 2, 5.5, 11", phy.contains("ax") ? "600" : "300")
        }
    }

    private static func supportsWPS(_ net: CWNetwork) -> Bool {
        if net.supportsSecurity(.none) { return false }
        return net.supportsSecurity(.wpa2Personal) || net.supportsSecurity(.wpaPersonal)
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
                    ssid: currentSSID, bssid: "", routerVendor: "",
                    channel: trimmed.replacingOccurrences(of: "Channel:", with: "").trimmingCharacters(in: .whitespaces),
                    band: "", signal: "", signalPercent: 0, rssi: 0,
                    security: "", encryptionType: "", phyMode: "",
                    noise: nil, channelWidth: nil, isIBSS: false,
                    isConnected: line.contains("Current Network"),
                    requiresPassword: true, supportsWPS: false, apName: "",
                    minRateMbps: "", basicRatesMbps: "", maxRateMbps: "", countryCode: ""
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
        if channel.channelBand == .band6GHz { return "802.11ax" }
        if channel.channelWidth == .width160MHz || channel.channelWidth == .width80MHz { return "802.11ac" }
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

    private static func encryptionLabel(_ net: CWNetwork) -> String {
        if net.supportsSecurity(.wpa3Personal) { return "WPA3" }
        if net.supportsSecurity(.wpa2Personal) { return "WPA2" }
        if net.supportsSecurity(.wpaPersonal) { return "WPA" }
        if net.supportsSecurity(.dynamicWEP) { return "WEP" }
        if net.supportsSecurity(.none) { return "Open" }
        return "Encrypted"
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
