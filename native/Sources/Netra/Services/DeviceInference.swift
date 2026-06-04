import Foundation

enum DeviceInference {
    /// 设备类型（不含操作系统名称）。
    static func inferRole(ip: String, localIP: String, gateway: String, vendor: String, hostname: String, ports: [OpenPort]) -> String {
        let portSet = Set(ports.map(\.port))
        let v = vendor.lowercased()
        let h = hostname.lowercased()
        let appleSignals = [
            v.contains("apple"),
            isAppleMobileName(h),
            portSet.contains(548),
            portSet.contains(7000),
            portSet.contains(5353) && (portSet.contains(5000) || portSet.contains(5900)),
            portSet.contains(62078),
        ].filter { $0 }.count
        if ip == gateway { return "Gateway / Router" }
        if isOpenWrt(vendor: v, hostname: h) { return "OpenWrt Router" }
        if isLikelyGatewayAddress(ip), isRouterLike(ports: portSet), ip != localIP {
            return "Router / Gateway Candidate"
        }
        if isNVR(vendor: v, hostname: h, ports: portSet) { return "NVR Recorder" }
        if isIPCamera(vendor: v, hostname: h, ports: portSet) { return "IPC Camera" }
        if portSet.contains(53) && (portSet.contains(67) || portSet.contains(68)) { return "DHCP / DNS Server" }
        if isAndroid(vendor: v, hostname: h) { return "Android Device" }
        if isIOS(vendor: v, hostname: h, ports: portSet) { return "iPhone / iPad" }
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

    static func inferOS(ports: [OpenPort], vendor: String, mac: String, hostname: String) -> String {
        let portSet = Set(ports.map(\.port))
        let v = vendor.lowercased()
        let h = hostname.lowercased()

        if isOpenWrt(vendor: v, hostname: h) { return "OpenWrt" }
        if isAndroid(vendor: v, hostname: h) { return "Android" }
        if isIOS(vendor: v, hostname: h, ports: portSet) { return "iOS / iPadOS" }
        if isNVR(vendor: v, hostname: h, ports: portSet) { return "NVR Firmware" }
        if isIPCamera(vendor: v, hostname: h, ports: portSet) { return "Camera Firmware" }
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

    private static func isLikelyGatewayAddress(_ ip: String) -> Bool {
        guard let addr = IPv4Helpers.parseIPv4(ip) else { return false }
        return addr.rawValue[3] == 1
    }

    private static func isRouterLike(ports: Set<Int>) -> Bool {
        ports.contains(53)
            || ports.contains(80)
            || ports.contains(443)
            || ports.contains(8080)
            || ports.contains(8443)
    }

    private static func isOpenWrt(vendor: String, hostname: String) -> Bool {
        hostname.contains("openwrt") || hostname.contains("lede") || vendor.contains("openwrt") || vendor.contains("lede")
    }

    private static func isAndroid(vendor: String, hostname: String) -> Bool {
        let names = ["android", "pixel", "galaxy", "redmi", "xiaomi", "oneplus", "huawei", "honor", "oppo", "vivo", "realme", "samsung"]
        let vendors = ["samsung", "xiaomi", "huawei", "honor", "oneplus", "oppo", "vivo", "realme", "google"]
        return names.contains { hostname.contains($0) } || vendors.contains { vendor.contains($0) }
    }

    private static func isIOS(vendor: String, hostname: String, ports: Set<Int>) -> Bool {
        if hostname.contains("iphone") || hostname.contains("ipad") || hostname.contains("ipod") { return true }
        return vendor.contains("apple") && ports.contains(62078) && !ports.contains(548) && !ports.contains(5900)
    }

    private static func isAppleMobileName(_ hostname: String) -> Bool {
        hostname.contains("iphone") || hostname.contains("ipad") || hostname.contains("ipod")
    }

    private static func isNVR(vendor: String, hostname: String, ports: Set<Int>) -> Bool {
        let names = ["nvr", "dvr", "xvr", "recorder", "录像机"]
        let vendors = ["hikvision", "dahua", "uniview", "tiandy", "xmeye", "zkteco"]
        let portEvidence = ports.contains(37777) || ports.contains(37778) || (ports.contains(8000) && ports.contains(554))
        return names.contains { hostname.contains($0) }
            || (vendors.contains { vendor.contains($0) } && portEvidence)
            || (hostname.contains("hikvision") && portEvidence)
    }

    private static func isIPCamera(vendor: String, hostname: String, ports: Set<Int>) -> Bool {
        let names = ["camera", "ipcam", "ipc", "cam-", "cam_", "webcam", "摄像", "hikvision", "dahua", "ezviz", "reolink", "axis", "amcrest"]
        let vendors = ["hikvision", "dahua", "ezviz", "uniview", "reolink", "axis", "amcrest", "vivotek"]
        let cameraPorts = ports.contains(554) || ports.contains(8554) || ports.contains(88) || ports.contains(81) || ports.contains(37777)
        return names.contains { hostname.contains($0) }
            || vendors.contains { vendor.contains($0) }
            || (cameraPorts && (ports.contains(80) || ports.contains(443) || ports.contains(8000)))
    }
}
