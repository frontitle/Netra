import Foundation
import Network

enum TopologyService {
    static func build(
        interface: NetworkInterface,
        devices: [LanDevice],
        hostInterfaces: [HostInterfaceInfo],
        gatewayBinding: GatewayBindingInfo?,
        routerChain: [RouterHop],
        dualHomed: [DualHomedDevice],
        localIPs: [String],
        tunnelSubnets: [String],
        routeSegments: [String: (IPv4Address, UInt8)]
    ) -> NetworkTopology {
        var segments: [NetworkSegment] = []
        var segmentMeta: [String: (count: Int, kind: String, iface: String)] = [:]
        let primarySegment = IPv4Helpers.parseIPv4(interface.ip).map { IPv4Helpers.segmentID(for: $0) } ?? ""
        for device in devices where !IPv4Helpers.isIgnoredSegment(device.segment) {
            let entry = segmentMeta[device.segment, default: (0, "primary", "")]
            segmentMeta[device.segment] = (entry.count + 1, entry.kind, entry.iface)
        }
        if let primary = IPv4Helpers.parseIPv4(interface.ip) {
            segmentMeta[IPv4Helpers.segmentID(for: primary), default: (0, "primary", interface.name)] =
                (devices.filter { $0.segment == IPv4Helpers.segmentID(for: primary) }.count, "primary", interface.name)
        }
        for subnet in tunnelSubnets where !IPv4Helpers.isIgnoredSegment(subnet) {
            segmentMeta[subnet, default: (0, "vpn-remote", "Tailscale")] = (0, "vpn-remote", "Tailscale")
        }
        for (_, pair) in routeSegments {
            let prefix = min(max(pair.1, 16), 24)
            guard prefix <= 24, let network = IPv4Helpers.parseIPv4(IPv4Helpers.ipv4String(pair.0)) else { continue }
            let seg = "\(IPv4Helpers.ipv4String(IPv4Helpers.networkBase(network, cidr: prefix)))/\(prefix)"
            if IPv4Helpers.isScannable(network), !IPv4Helpers.isIgnoredSegment(seg), segmentMeta[seg] == nil {
                segmentMeta[seg] = (0, "routed", "")
            }
        }
        for (cidr, meta) in segmentMeta.sorted(by: { $0.key < $1.key }) {
            guard shouldShowSegment(cidr, count: meta.count, kind: meta.kind) else { continue }
            let gw = devices.first(where: { $0.segment == cidr && ($0.ip.hasSuffix(".1") || $0.role.contains("网关")) })?.ip ?? ""
            segments.append(NetworkSegment(
                id: "segment:\(cidr)",
                cidr: cidr,
                gateway: gw,
                deviceCount: meta.count,
                kind: meta.kind,
                interfaceName: meta.iface
            ))
        }

        var nodes: [TopologyNode] = [
            TopologyNode(id: "internet", label: "Internet", kind: "internet", ip: "", subtitle: "", status: "online", aliasIPs: []),
        ]
        var links: [TopologyLink] = []
        let defaultGW = interface.gateway
        let chain: [RouterHop] = {
            if !routerChain.isEmpty { return routerChain }
            if let binding = gatewayBinding {
                var hops: [RouterHop] = []
                if !binding.upstreamGateway.isEmpty {
                    hops.append(RouterHop(ip: binding.upstreamGateway, segment: "", mac: "", label: "上级路由", aliasIPs: [], tier: 0, confirmed: true))
                }
                hops.append(RouterHop(ip: binding.localGateway, segment: "", mac: "", label: "默认网关", aliasIPs: binding.aliasIPs, tier: hops.count, confirmed: true))
                return hops
            }
            if !defaultGW.isEmpty, defaultGW != "未知" {
                return [RouterHop(ip: defaultGW, segment: "", mac: "", label: "网关", aliasIPs: [], tier: 0, confirmed: true)]
            }
            return []
        }()

        for (index, hop) in chain.enumerated() {
            let dev = devices.first { $0.ip == hop.ip }
            let kind = index == chain.count - 1 ? "gateway" : "upstream"
            let subtitle = hop.aliasIPs.isEmpty ? hop.segment : "同设备 \(hop.aliasIPs.joined(separator: " · "))"
            nodes.append(TopologyNode(
                id: "device:\(hop.ip)",
                label: dev.map { displayLabel($0) } ?? hop.ip,
                kind: kind,
                ip: hop.ip,
                subtitle: subtitle,
                status: "online",
                aliasIPs: hop.aliasIPs
            ))
        }

        let hostLabel = localIPs.isEmpty ? "-" : localIPs.joined(separator: " · ")
        nodes.append(TopologyNode(id: "local", label: "Mac", kind: "local", ip: hostLabel, subtitle: interface.name, status: "online", aliasIPs: []))

        var prev = "internet"
        for hop in chain {
            let target = "device:\(hop.ip)"
            links.append(TopologyLink(source: prev, target: target, label: prev == "internet" ? "出口" : "上联"))
            prev = target
        }
        if prev == "internet" {
            links.append(TopologyLink(source: "internet", target: "local", label: "本机"))
        } else {
            links.append(TopologyLink(source: prev, target: "local", label: "下联"))
        }

        return NetworkTopology(
            segments: segments,
            interfaces: hostInterfaces,
            gatewayBinding: gatewayBinding,
            routerChain: chain,
            dualHomed: dualHomed,
            primaryInterface: interface.name,
            nodes: nodes,
            links: links
        )
    }

    private static func shouldShowSegment(_ cidr: String, count: Int, kind: String) -> Bool {
        if IPv4Helpers.isIgnoredSegment(cidr) { return false }
        let prefix = Int(cidr.split(separator: "/").last ?? "24") ?? 24
        if prefix < 16 || prefix > 24 { return false }
        if kind == "vpn-remote" || kind == "routed" { return true }
        return count > 0 || kind == "primary" || kind == "gateway"
    }

    private static func displayLabel(_ device: LanDevice) -> String {
        if !device.hostname.isEmpty, device.hostname != "局域网设备" { return device.hostname }
        if !device.vendor.isEmpty, device.vendor != "未知厂商" { return device.vendor }
        return device.ip
    }
}
