import Foundation
import Network

/// 路由链：上级（traceroute / 双 WAN）→ 本机默认网关（靠近 Mac）。
enum RouterTopologyService {
    static func discoverChain(
        primarySegment: String,
        defaultGateway: String,
        devices: [LanDevice],
        routeHops: [IPv4Address],
        gatewayBinding: GatewayBindingInfo?,
        tailscaleRemote: Set<String>
    ) -> [RouterHop] {
        let physical = devices.filter { !TailscaleService.isRemoteSegment($0.segment, remote: tailscaleRemote) }
        var hops: [RouterHop] = []
        var seenIPs = Set<String>()

        func append(ip: String, label: String) {
            guard !ip.isEmpty, ip != "未知" else { return }
            guard let addr = IPv4Helpers.parseIPv4(ip) else { return }
            let segment = IPv4Helpers.segmentID(for: addr)
            if TailscaleService.isRemoteSegment(segment, remote: tailscaleRemote) { return }

            let device = physical.first(where: { $0.ip == ip })
                ?? physical.first(where: { $0.ip.hasSuffix(".1") && $0.segment == segment })
            let resolvedIP = device?.ip ?? ip
            guard seenIPs.insert(resolvedIP).inserted else { return }

            let mac = device.map { IPv4Helpers.normalizeMAC($0.mac) } ?? ""
            var aliases: [String] = []
            if !mac.isEmpty, mac != "未知" {
                aliases = physical
                    .filter { IPv4Helpers.normalizeMAC($0.mac) == mac && $0.ip != resolvedIP }
                    .map(\.ip)
            }
            hops.append(RouterHop(
                ip: resolvedIP,
                segment: device?.segment ?? segment,
                mac: mac,
                label: label,
                aliasIPs: aliases,
                tier: 0,
                confirmed: device != nil || resolvedIP == defaultGateway
            ))
        }

        // 上级：traceroute 私网跳（排除本机网关）
        for hop in routeHops {
            let ip = IPv4Helpers.ipv4String(hop)
            guard ip != defaultGateway, IPv4Helpers.isScannable(hop) else { continue }
            append(ip: ip, label: "上级路由")
        }

        // 上级：双 WAN / 二级路由绑定
        if let binding = gatewayBinding, !binding.upstreamGateway.isEmpty,
           binding.upstreamGateway != defaultGateway {
            append(ip: binding.upstreamGateway, label: "上级路由")
            for alias in binding.aliasIPs where alias != defaultGateway {
                append(ip: alias, label: "上级接口")
            }
        }

        // 本机默认网关（必须显示）
        if !defaultGateway.isEmpty, defaultGateway != "未知" {
            let gwLabel = hops.isEmpty ? "网关" : "二级路由 / 网关"
            append(ip: defaultGateway, label: gwLabel)
        } else if let gwDevice = physical.first(where: { $0.ip.hasSuffix(".1") || $0.role.contains("网关") }) {
            append(ip: gwDevice.ip, label: "网关")
        }

        for i in hops.indices {
            hops[i].tier = i
            if hops[i].ip == defaultGateway {
                hops[i].label = hops.count > 1 ? "二级路由 / 网关" : "网关"
            }
        }
        return hops
    }
}
