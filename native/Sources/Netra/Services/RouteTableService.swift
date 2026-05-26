import Foundation
import Network

enum RouteTableService {
    static func routeTable() -> (gateways: Set<IPv4Address>, segments: [String: (IPv4Address, UInt8)]) {
        var gateways = Set<IPv4Address>()
        var segments: [String: (IPv4Address, UInt8)] = [:]
        guard let output = ShellRunner.run("/usr/sbin/netstat", ["-rn", "-f", "inet"]) else {
            return (gateways, segments)
        }
        for line in output.split(separator: "\n") {
            let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard parts.count >= 2, parts[0] != "Destination" else { continue }
            if let gw = IPv4Helpers.parseIPv4(parts[1]), IPv4Helpers.isScannable(gw) {
                gateways.insert(gw)
            }
            if let parsed = parseRouteDestination(parts[0]) {
                let (network, cidr) = parsed
                let clamped = min(max(cidr, 24), 30)
                let key = "\(IPv4Helpers.ipv4String(IPv4Helpers.networkBase(network, cidr: clamped)))/\(clamped)"
                if IPv4Helpers.isScannable(network) {
                    segments[key] = (IPv4Helpers.networkBase(network, cidr: clamped), clamped)
                }
            }
        }
        return (gateways, segments)
    }

    static func discoverRouteHops(maxHops: UInt8 = 5) -> [IPv4Address] {
        guard let output = ShellRunner.run("/usr/sbin/traceroute", ["-m", "\(maxHops)", "-q", "1", "-w", "1", "-n", "8.8.8.8"]) else {
            return []
        }
        var hops: [IPv4Address] = []
        for line in output.split(separator: "\n").dropFirst() {
            let token = line.split(whereSeparator: \.isWhitespace).dropFirst().first.map(String.init) ?? ""
            if let ip = IPv4Helpers.parseIPv4(token), IPv4Helpers.isScannable(ip), !hops.contains(ip) {
                hops.append(ip)
            }
        }
        return hops
    }

    static func parseRouteDestination(_ dest: String) -> (IPv4Address, UInt8)? {
        if dest == "default" || dest.contains(":") { return nil }
        let parts = dest.split(separator: "/")
        let addrParts = parts[0].split(separator: ".").map(String.init)
        guard !addrParts.isEmpty, addrParts.count <= 4 else { return nil }
        var octets = [UInt8](repeating: 0, count: 4)
        for (i, p) in addrParts.enumerated() {
            guard let v = UInt8(p) else { return nil }
            octets[i] = v
        }
        guard let ip = IPv4Address("\(octets[0]).\(octets[1]).\(octets[2]).\(octets[3])") else { return nil }
        let inferred: UInt8 = {
            if parts.count > 1, let c = UInt8(parts[1]) { return min(max(c, 16), 30) }
            switch addrParts.count {
            case 1: return 8
            case 2: return 16
            case 3: return 24
            default: return 32
            }
        }()
        return (ip, inferred)
    }
}
