import Foundation

enum DeviceInference {
    static func inferRole(ip: String, localIP: String, gateway: String, vendor: String, ports: [OpenPort]) -> String {
        if ip == gateway { return "网关 / 路由器" }
        if ports.contains(where: { [80, 443, 8080, 8443].contains($0.port) }) && vendor.lowercased().contains("router") {
            return "路由器"
        }
        if ports.contains(where: { [445, 139].contains($0.port) }) { return "Windows / SMB 设备" }
        if ports.contains(where: { $0.port == 22 }) { return "SSH 服务器" }
        if ports.contains(where: { [5000, 5001, 8080, 8081].contains($0.port) }) { return "NAS / 存储" }
        return "普通联网设备"
    }

    static func inferOS(ports: [OpenPort], vendor: String, mac: String) -> String {
        let v = vendor.lowercased()
        if v.contains("apple") { return "Apple 设备" }
        if ports.contains(where: { $0.port == 445 }) { return "Windows" }
        if ports.contains(where: { $0.port == 22 }) { return "Linux / Unix" }
        return "未知"
    }

    static func hostname(from arp: String?, ip: String) -> String {
        if let arp, !arp.isEmpty, arp != "?" { return arp }
        if let name = dscacheHost(ip: ip) { return name }
        return "局域网设备"
    }

    static func localDNS(hostname: String, ip: String) -> String {
        if hostname.contains(".") { return hostname }
        if hostname != "局域网设备" { return "\(hostname).local" }
        return "\(ip.replacingOccurrences(of: ".", with: "-")).local"
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
}
