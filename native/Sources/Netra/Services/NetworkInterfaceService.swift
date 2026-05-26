import Foundation
import Network

enum NetworkInterfaceService {
    static func currentInterface() throws -> NetworkInterface {
        guard let device = wifiDevice() else {
            throw ScanError.message("未找到 Wi-Fi 网卡。")
        }
        guard let ip = ShellRunner.run("/usr/sbin/ipconfig", ["getifaddr", device])?.trimmingCharacters(in: .whitespacesAndNewlines),
              !ip.isEmpty else {
            throw ScanError.message("未找到当前 Wi-Fi IPv4，请确认已连接 Wi-Fi。")
        }
        let ifconfig = ShellRunner.run("/sbin/ifconfig", [device]) ?? ""
        let netmaskHex = ifconfig.split(separator: "\n")
            .joined(separator: " ")
            .split(separator: " ")
            .enumerated()
            .first(where: { $0.element == "netmask" })
            .flatMap { idx, _ in
                ifconfig.split(separator: " ").dropFirst(idx + 1).first.map(String.init)
            } ?? "0xffffff00"
        let cidr = cidrFromHexNetmask(netmaskHex) ?? 24
        let netmask = dottedNetmask(cidr)
        let gateway = parseGateway(from: ShellRunner.run("/usr/sbin/route", ["-n", "get", "default"]) ?? "") ?? "未知"
        return NetworkInterface(name: device, ip: ip, netmask: netmask, cidr: cidr, gateway: gateway)
    }

    static func wifiDevice() -> String? {
        guard let output = ShellRunner.run("/usr/sbin/networksetup", ["-listallhardwareports"]) else { return nil }
        var lastWifi = false
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("Hardware Port: Wi-Fi") || trimmed.contains("Hardware Port: AirPort") {
                lastWifi = true
                continue
            }
            if lastWifi, trimmed.hasPrefix("Device:") {
                return trimmed.split(separator: ":").dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    static func parseAllHostInterfaces(primary: NetworkInterface) -> [HostInterfaceInfo] {
        guard let output = ShellRunner.run("/sbin/ifconfig") else { return [] }
        var results: [HostInterfaceInfo] = []
        var currentName = ""
        var currentIP = ""
        var currentMask = ""
        var isUp = false
        func flush() {
            guard !currentName.isEmpty, let ip = IPv4Helpers.parseIPv4(currentIP) else { return }
            let cidr = cidrFromDottedNetmask(currentMask) ?? 24
            let kind = interfaceKind(name: currentName)
            results.append(HostInterfaceInfo(
                name: currentName,
                ip: IPv4Helpers.ipv4String(ip),
                cidr: cidr,
                netmask: currentMask.isEmpty ? IPv4Helpers.dottedNetmask(cidr) : currentMask,
                kind: kind,
                label: interfaceLabel(kind: kind),
                gateway: currentName == primary.name ? primary.gateway : "",
                status: isUp ? "up" : "down"
            ))
        }
        for line in output.split(separator: "\n") {
            if !line.hasPrefix("\t"), !line.hasPrefix(" ") {
                flush()
                let name = line.split(separator: ":").first.map(String.init) ?? ""
                currentName = name
                currentIP = ""
                currentMask = ""
                isUp = line.contains("UP")
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("inet ") {
                let parts = trimmed.split(separator: " ")
                if parts.count >= 2 { currentIP = String(parts[1]) }
                if let maskIdx = parts.firstIndex(of: "netmask"), maskIdx + 1 < parts.count {
                    let hex = String(parts[maskIdx + 1])
                    if let c = cidrFromHexNetmask(hex) { currentMask = dottedNetmask(c) }
                }
            }
        }
        flush()
        return results
    }

    static func collectLocalIPs(primary: NetworkInterface, interfaces: [HostInterfaceInfo]) -> [String] {
        var ips = Set<String>()
        ips.insert(primary.ip)
        for iface in interfaces where iface.status == "up" {
            if !iface.ip.isEmpty, !iface.ip.hasPrefix("127.") { ips.insert(iface.ip) }
        }
        return ips.sorted()
    }

    private static func interfaceKind(name: String) -> String {
        let n = name.lowercased()
        if n.hasPrefix("en") && n != "en0" { return n == "en0" ? "wifi" : "ethernet" }
        if n.hasPrefix("bridge") { return "bridge" }
        if n.hasPrefix("utun") || n.hasPrefix("ipsec") { return "vpn" }
        if n.contains("vbox") || n.contains("vmnet") { return "vm" }
        if n.contains("docker") || n.contains("veth") { return "docker" }
        if n.hasPrefix("awdl") || n.hasPrefix("llw") { return "virtual" }
        return "virtual"
    }

    private static func interfaceLabel(kind: String) -> String {
        switch kind {
        case "wifi": return "Wi-Fi"
        case "ethernet": return "以太网"
        case "vpn": return "VPN/虚拟组网"
        case "docker": return "Docker"
        case "vm": return "虚拟机"
        case "bridge": return "桥接"
        default: return "网络接口"
        }
    }

    static func parseGateway(from routeOutput: String) -> String? {
        for line in routeOutput.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("gateway:") {
                let gw = trimmed.replacingOccurrences(of: "gateway:", with: "").trimmingCharacters(in: .whitespaces)
                if IPv4Helpers.parseIPv4(gw) != nil { return gw }
            }
        }
        return nil
    }

    static func cidrFromHexNetmask(_ hex: String) -> UInt8? {
        guard let value = UInt32(hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex, radix: 16) else { return nil }
        var bits = 0
        var v = value
        while v != 0 { bits += 1; v &= v - 1 }
        return UInt8(bits)
    }

    static func cidrFromDottedNetmask(_ mask: String) -> UInt8? {
        guard let addr = IPv4Helpers.parseIPv4(mask) else { return nil }
        let raw = IPv4Helpers.ipv4ToUInt32(addr)
        var bits = 0
        var v = raw
        while v != 0 { bits += 1; v &= v - 1 }
        return UInt8(bits)
    }

    static func dottedNetmask(_ cidr: UInt8) -> String {
        let mask = UInt32.max << (32 - Int(cidr))
        return "\(mask >> 24 & 0xff).\(mask >> 16 & 0xff).\(mask >> 8 & 0xff).\(mask & 0xff)"
    }
}

enum ScanError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}

extension IPv4Helpers {
    static func ipv4String(_ ip: IPv4Address) -> String {
        let b = [UInt8](ip.rawValue)
        return "\(b[0]).\(b[1]).\(b[2]).\(b[3])"
    }

    static func dottedNetmask(_ cidr: UInt8) -> String {
        NetworkInterfaceService.dottedNetmask(cidr)
    }
}
