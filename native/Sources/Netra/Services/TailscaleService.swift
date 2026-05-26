import Foundation
import Network

enum TailscaleService {
    static func detect(primaryIP: String) -> TailscaleInfo? {
        guard let ipv4 = ShellRunner.run("/usr/local/bin/tailscale", ["ip", "-4"])?
            .trimmingCharacters(in: .whitespacesAndNewlines), !ipv4.isEmpty else {
            if let alt = ShellRunner.run("/opt/homebrew/bin/tailscale", ["ip", "-4"])?
                .trimmingCharacters(in: .whitespacesAndNewlines), !alt.isEmpty {
                return buildInfo(ipv4: alt, primaryIP: primaryIP)
            }
            return nil
        }
        return buildInfo(ipv4: ipv4, primaryIP: primaryIP)
    }

    private static func buildInfo(ipv4: String, primaryIP: String) -> TailscaleInfo {
        let status = ShellRunner.run("/usr/local/bin/tailscale", ["status", "--self"])
            ?? ShellRunner.run("/opt/homebrew/bin/tailscale", ["status", "--self"]) ?? ""
        let hostname = status.split(separator: "\n").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? "Tailscale"
        return TailscaleInfo(ipv4: ipv4, hostname: hostname, remoteSubnets: remoteSubnets(primaryIP: primaryIP))
    }

    static func remoteSubnets(primaryIP: String) -> [String] {
        guard let primary = IPv4Helpers.parseIPv4(primaryIP) else { return [] }
        let primarySegment = IPv4Helpers.segmentID(for: primary)
        guard let output = ShellRunner.run("/usr/sbin/netstat", ["-rn", "-f", "inet"]) else { return [] }
        var subnets = Set<String>()
        for line in output.split(separator: "\n") {
            let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard parts.count >= 4 else { continue }
            let iface = parts.last ?? ""
            guard iface.hasPrefix("utun") || iface.hasPrefix("ipsec") else { continue }
            guard let parsed = RouteTableService.parseRouteDestination(parts[0]) else { continue }
            let (network, cidr) = parsed
            let b = network.rawValue
            if b[0] == 10 || (b[0] == 172 && (16...31).contains(b[1])) || (b[0] == 192 && b[1] == 168) {
                let clamped = min(max(cidr, 24), 30)
                let seg = "\(IPv4Helpers.ipv4String(IPv4Helpers.networkBase(network, cidr: clamped)))/\(clamped)"
                if seg != primarySegment { subnets.insert(seg) }
            }
        }
        return subnets.sorted()
    }

    static func isRemoteSegment(_ segment: String, remote: Set<String>) -> Bool {
        remote.contains(segment)
    }
}
