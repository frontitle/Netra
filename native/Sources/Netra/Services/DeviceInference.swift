import Foundation

enum DeviceInference {
    /// 设备类型（不含操作系统名称）。
    static func inferRole(ip: String, localIP: String, gateway: String, vendor: String, ports: [OpenPort]) -> String {
        let portSet = Set(ports.map(\.port))
        let v = vendor.lowercased()
        let appleSignals = [
            v.contains("apple"),
            portSet.contains(548),
            portSet.contains(7000),
            portSet.contains(5353) && (portSet.contains(5000) || portSet.contains(5900)),
            portSet.contains(62078),
        ].filter { $0 }.count
        if ip == gateway { return "Gateway / Router" }
        if portSet.contains(53) && (portSet.contains(67) || portSet.contains(68)) { return "DHCP / DNS Server" }
        if portSet.contains(445) || portSet.contains(139) { return "File Sharing (SMB)" }
        if appleSignals >= 2 { return "Apple Device" }
        if portSet.contains(631) || portSet.contains(9100) { return "Printer" }
        if portSet.contains(554) || portSet.contains(8554) { return "Camera / NVR" }
        if portSet.contains(502) { return "Industrial (Modbus)" }
        if portSet.contains(22) && portSet.contains(80) { return "Server" }
        if portSet.contains(22) { return "SSH Host" }
        if portSet.contains(80) || portSet.contains(443) || portSet.contains(8080) {
            if v.contains("router") || v.contains("netgear") || v.contains("tp-link") { return "Router" }
            return "Web Service"
        }
        if portSet.contains(5000) || portSet.contains(5001) { return "NAS / Storage" }
        if v.contains("apple") { return "Apple Device" }
        return "Network Device"
    }

    static func inferOS(ports: [OpenPort], vendor: String, mac: String) -> String {
        let portSet = Set(ports.map(\.port))
        let v = vendor.lowercased()

        if isAppleVendor(v) {
            if portSet.contains(548) || portSet.contains(7000) || portSet.contains(5900) || portSet.contains(62078) {
                return "macOS"
            }
            return "Apple (iOS/macOS/tvOS)"
        }
        if portSet.contains(445) && (portSet.contains(135) || portSet.contains(139)) { return "Windows" }
        if portSet.contains(445) { return "Windows" }
        if portSet.contains(22) && !portSet.contains(445) {
            if portSet.contains(80) || portSet.contains(443) { return "Linux" }
            return "Linux / Unix"
        }
        if portSet.contains(631) && v.contains("hp") { return "Embedded / Printer" }
        if v.contains("raspberry") { return "Linux (Raspberry Pi)" }
        if v.contains("espressif") || v.contains("arduino") { return "Embedded (IoT)" }
        return "Unknown"
    }

    /// 嗅探设备自身报告的主机名（Bonjour / NetBIOS / mDNS / DNS）。
    static func hostname(from arp: String?, ip: String) -> String {
        HostnameResolver.resolve(ip: ip, arpHostname: arp)
    }

    static func localDNS(hostname: String, ip: String) -> String {
        if hostname == "—" { return "—" }
        if hostname.contains(".") { return hostname }
        return hostname
    }

    private static func isAppleVendor(_ v: String) -> Bool {
        v.contains("apple")
    }
}
