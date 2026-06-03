import Foundation
import Network

enum GatewayService {
    static func discoverBinding(
        defaultGateway: String,
        devices: [LanDevice],
        routeHops: [IPv4Address],
        primarySegment: String,
        tailscaleRemote: Set<String>
    ) -> GatewayBindingInfo? {
        guard !defaultGateway.isEmpty, defaultGateway != "未知" else { return nil }
        let localSegment = devices.first(where: { $0.ip == defaultGateway })?.segment
            ?? IPv4Helpers.parseIPv4(defaultGateway).map { IPv4Helpers.segmentID(for: $0) }
        guard let localSegment else { return nil }
        let gatewayMac = devices.first(where: { $0.ip == defaultGateway })
            .map { IPv4Helpers.normalizeMAC($0.mac) }
            .flatMap { $0.isEmpty || $0 == "未知" ? nil : $0 }
        let sameMacIPs = gatewayMac.map { mac in
            devices.filter { IPv4Helpers.normalizeMAC($0.mac) == mac }.map(\.ip)
        } ?? []
        let uplinkAliases = sameMacIPs.filter { ip in
            guard ip != defaultGateway, let addr = IPv4Helpers.parseIPv4(ip) else { return false }
            let seg = IPv4Helpers.segmentID(for: addr)
            return seg != localSegment && seg != primarySegment && !TailscaleService.isRemoteSegment(seg, remote: tailscaleRemote)
        }
        let upstream: String = {
            if !uplinkAliases.isEmpty {
                return uplinkAliases.first(where: { $0.hasSuffix(".1") }) ?? uplinkAliases[0]
            }
            for hop in routeHops {
                let hopIP = IPv4Helpers.ipv4String(hop)
                let seg = IPv4Helpers.segmentID(for: hop)
                guard hopIP != defaultGateway, seg != localSegment, seg != primarySegment,
                      !TailscaleService.isRemoteSegment(seg, remote: tailscaleRemote) else { continue }
                // traceroute 已经给出了“上级私网跳”；这一步不应依赖“同 MAC”才能成立，
                // 否则会出现“没扫描上游网段→拿不到 MAC→无法确定 upstream→也就永远不会去扫上游”的死循环。
                return hopIP
            }
            if let candidate = upstreamGatewayCandidate(
                devices: devices,
                defaultGateway: defaultGateway,
                localSegment: localSegment,
                primarySegment: primarySegment,
                tailscaleRemote: tailscaleRemote
            ) {
                return candidate
            }
            return ""
        }()
        return GatewayBindingInfo(localGateway: defaultGateway, upstreamGateway: upstream, aliasIPs: uplinkAliases)
    }

    private static func upstreamGatewayCandidate(
        devices: [LanDevice],
        defaultGateway: String,
        localSegment: String,
        primarySegment: String,
        tailscaleRemote: Set<String>
    ) -> String? {
        let candidates = devices.filter { device in
            guard device.ip != defaultGateway,
                  let ip = IPv4Helpers.parseIPv4(device.ip),
                  ip.rawValue[3] == 1 else { return false }
            let segment = IPv4Helpers.segmentID(for: ip)
            guard segment != localSegment,
                  segment != primarySegment,
                  !TailscaleService.isRemoteSegment(segment, remote: tailscaleRemote) else { return false }
            let ports = Set(device.ports.map(\.port))
            return ports.contains(53)
                || ports.contains(80)
                || ports.contains(443)
                || ports.contains(8080)
                || ports.contains(8443)
                || device.role.lowercased().contains("router")
                || device.role.contains("网关")
        }
        return candidates.sorted { a, b in
            upstreamGatewayScore(a.ip) > upstreamGatewayScore(b.ip)
        }.first?.ip
    }

    private static func upstreamGatewayScore(_ ip: String) -> Int {
        guard let addr = IPv4Helpers.parseIPv4(ip) else { return 0 }
        let b = addr.rawValue
        if b[0] == 192, b[1] == 168, b[2] == 1, b[3] == 1 { return 100 }
        if b[0] == 10, b[1] == 0, b[2] == 0, b[3] == 1 { return 90 }
        if b[3] == 1 { return 50 - Int(b[2]) }
        return 0
    }
}
