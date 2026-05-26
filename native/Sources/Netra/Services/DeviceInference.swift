import Foundation

enum DeviceInference {
    /// 设备类型（不含操作系统名称）。
    static func inferRole(ip: String, localIP: String, gateway: String, vendor: String, ports: [OpenPort]) -> String {
        let portSet = Set(ports.map(\.port))
        if ip == gateway { return "Gateway / Router" }
        if portSet.contains(53) && (portSet.contains(67) || portSet.contains(68)) { return "DHCP / DNS Server" }
        if portSet.contains(445) || portSet.contains(139) { return "File Sharing (SMB)" }
        if portSet.contains(548) || portSet.contains(7000) || portSet.contains(5000) { return "Apple Device" }
        if portSet.contains(631) || portSet.contains(9100) { return "Printer" }
        if portSet.contains(554) || portSet.contains(8554) { return "Camera / NVR" }
        if portSet.contains(502) { return "Industrial (Modbus)" }
        if portSet.contains(22) && portSet.contains(80) { return "Server" }
        if portSet.contains(22) { return "SSH Host" }
        if portSet.contains(80) || portSet.contains(443) || portSet.contains(8080) {
            if vendor.lowercased().contains("router") || vendor.lowercased().contains("netgear")
                || vendor.lowercased().contains("tp-link") { return "Router" }
            return "Web Service"
        }
        if portSet.contains(5000) || portSet.contains(5001) { return "NAS / Storage" }
        if vendor.lowercased().contains("apple") { return "Apple Device" }
        return "Network Device"
    }

    static func inferOS(ports: [OpenPort], vendor: String, mac: String) -> String {
        let portSet = Set(ports.map(\.port))
        let v = vendor.lowercased()

        if isAppleVendor(v) {
            if portSet.contains(548) || portSet.contains(7000) || portSet.contains(5000) || portSet.contains(5900) {
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

    /// 嗅探设备自身报告的主机名（非应用生成名）。
    static func hostname(from arp: String?, ip: String) -> String {
        if let name = sanitizeHostname(arp) { return name }
        if let name = dscacheHost(ip: ip).flatMap(sanitizeHostname) { return name }
        if let name = reverseDNS(ip: ip).flatMap(sanitizeHostname) { return name }
        if let name = smbutilName(ip: ip).flatMap(sanitizeHostname) { return name }
        if let name = refreshedARPName(ip: ip) { return name }
        return "—"
    }

    static func localDNS(hostname: String, ip: String) -> String {
        if hostname == "—" { return "\(ip.replacingOccurrences(of: ".", with: "-")).local" }
        if hostname.contains(".") { return hostname }
        return "\(hostname).local"
    }

    private static func sanitizeHostname(_ raw: String?) -> String? {
        guard var name = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        if name == "?" || name == "(null)" || name == "—" { return nil }
        if name.lowercased().hasPrefix("host-") { return nil }
        if name.hasSuffix(".") { name.removeLast() }
        if name.contains("\\") {
            name = name.split(separator: "\\").last.map(String.init) ?? name
        }
        return name.isEmpty ? nil : name
    }

    private static func refreshedARPName(ip: String) -> String? {
        guard let addr = IPv4Helpers.parseIPv4(ip) else { return nil }
        guard let entry = ARPService.readAll()[addr] else { return nil }
        return sanitizeHostname(entry.hostname)
    }

    private static func isAppleVendor(_ v: String) -> Bool {
        v.contains("apple")
    }

    private static func dscacheHost(ip: String) -> String? {
        guard let output = ShellRunner.run("/usr/bin/dscacheutil", ["-q", "host", "-a", "ip_address", ip]) else { return nil }
        for line in output.split(separator: "\n") {
            let row = String(line).trimmingCharacters(in: .whitespaces)
            if row.hasPrefix("name:") {
                return row.replacingOccurrences(of: "name:", with: "").trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private static func reverseDNS(ip: String) -> String? {
        guard let output = ShellRunner.run("/usr/bin/host", [ip]) else { return nil }
        for line in output.split(separator: "\n") {
            let row = String(line)
            if row.contains("domain name pointer") {
                return row.split(separator: " ").last.map(String.init)?
                    .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            }
        }
        return nil
    }

    private static func smbutilName(ip: String) -> String? {
        guard let output = ShellRunner.run("/usr/sbin/smbutil", ["lookup", "-a", ip]) else { return nil }
        for line in output.split(separator: "\n") {
            let row = String(line).trimmingCharacters(in: .whitespaces)
            if row.lowercased().hasPrefix("name:") {
                return row.split(separator: ":", maxSplits: 1).last.map { String($0).trimmingCharacters(in: .whitespaces) }
            }
        }
        return nil
    }
}
