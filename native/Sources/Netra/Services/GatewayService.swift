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
                if let mac = gatewayMac,
                   devices.contains(where: { $0.ip == hopIP && IPv4Helpers.normalizeMAC($0.mac) == mac }) {
                    return hopIP
                }
            }
            return ""
        }()
        return GatewayBindingInfo(localGateway: defaultGateway, upstreamGateway: upstream, aliasIPs: uplinkAliases)
    }
}
