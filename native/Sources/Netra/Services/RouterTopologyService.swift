import Foundation
import Network

/// 基于 traceroute、同 MAC 跨网段、路由表推断多层路由链（近 Internet → 近本机）。
enum RouterTopologyService {
    static func discoverChain(
        primarySegment: String,
        defaultGateway: String,
        devices: [LanDevice],
        routeHops: [IPv4Address],
        tailscaleRemote: Set<String>
    ) -> [RouterHop] {
        let physical = devices.filter { !TailscaleService.isRemoteSegment($0.segment, remote: tailscaleRemote) }
        let macGroups = groupByMAC(physical)
        let adjacency = buildSegmentGraph(macGroups: macGroups, devices: physical, tailscaleRemote: tailscaleRemote)

        var ordered: [RouterHop] = []
        var seenIPs = Set<String>()

        // 1) traceroute 路径上的私网跳（从 WAN 侧向本机）
        for hop in routeHops {
            appendHop(
                ip: IPv4Helpers.ipv4String(hop),
                segment: IPv4Helpers.segmentID(for: hop),
                label: "上级路由",
                macGroups: macGroups,
                devices: physical,
                defaultGateway: defaultGateway,
                into: &ordered,
                seen: &seenIPs,
                tailscaleRemote: tailscaleRemote
            )
        }

        // 2) 双网卡 / 跨网段 MAC 推断的中继
        let graphSegments = orderSegmentsFromWAN(
            primarySegment: primarySegment,
            defaultGateway: defaultGateway,
            adjacency: adjacency,
            routeHops: routeHops,
            devices: physical
        )
        for segment in graphSegments where segment != primarySegment {
            guard let hop = routerHop(
                for: segment,
                defaultGateway: defaultGateway,
                macGroups: macGroups,
                devices: physical
            ) else { continue }
            if seenIPs.insert(hop.ip).inserted {
                var labeled = hop
                labeled.label = "中继路由"
                ordered.append(labeled)
            }
            for alias in hop.aliasIPs where seenIPs.insert(alias).inserted {
                ordered.append(RouterHop(
                    ip: alias, segment: segment, mac: hop.mac, label: "中继接口",
                    aliasIPs: [], tier: 0, confirmed: hop.confirmed
                ))
            }
        }

        // 3) 默认网关（本机网段）
        if !defaultGateway.isEmpty, defaultGateway != "未知" {
            appendHop(
                ip: defaultGateway,
                segment: IPv4Helpers.parseIPv4(defaultGateway).map { IPv4Helpers.segmentID(for: $0) } ?? primarySegment,
                label: ordered.isEmpty ? "网关" : "二级路由 / 网关",
                macGroups: macGroups,
                devices: physical,
                defaultGateway: defaultGateway,
                into: &ordered,
                seen: &seenIPs,
                tailscaleRemote: tailscaleRemote
            )
        }

        for i in ordered.indices {
            let isPrimaryGW = ordered[i].ip == defaultGateway
            if i == 0, ordered.count > 1, ordered[i].label == "上级路由" {
                ordered[i].label = "上级路由"
            } else if isPrimaryGW {
                ordered[i].label = ordered.count > 1 ? "二级路由 / 网关" : "网关"
            }
            ordered[i].tier = i
            ordered[i].confirmed = !ordered[i].mac.isEmpty && ordered[i].mac != "未知"
        }
        return ordered
    }

    private static func appendHop(
        ip: String,
        segment: String,
        label: String,
        macGroups: [String: [LanDevice]],
        devices: [LanDevice],
        defaultGateway: String,
        into ordered: inout [RouterHop],
        seen: inout Set<String>,
        tailscaleRemote: Set<String>
    ) {
        guard !ip.isEmpty, seen.insert(ip).inserted else { return }
        guard let addr = IPv4Helpers.parseIPv4(ip), IPv4Helpers.isScannable(addr) else { return }
        if TailscaleService.isRemoteSegment(segment, remote: tailscaleRemote) { return }

        let onSegment = devices.filter { $0.ip == ip || $0.segment == segment }
        let preferred = onSegment.first(where: { $0.ip == ip })
            ?? onSegment.first(where: { $0.ip.hasSuffix(".1") })
            ?? onSegment.first
        let mac = preferred.map { IPv4Helpers.normalizeMAC($0.mac) } ?? ""
        let aliases = mac.isEmpty ? [] : (macGroups[mac]?.map(\.ip).filter { $0 != ip } ?? [])
        ordered.append(RouterHop(
            ip: ip,
            segment: segment,
            mac: mac,
            label: label,
            aliasIPs: aliases,
            tier: 0,
            confirmed: preferred != nil
        ))
    }

    private static func groupByMAC(_ devices: [LanDevice]) -> [String: [LanDevice]] {
        var map: [String: [LanDevice]] = [:]
        for d in devices {
            let mac = IPv4Helpers.normalizeMAC(d.mac)
            guard !mac.isEmpty, mac != "未知" else { continue }
            map[mac, default: []].append(d)
        }
        return map
    }

    /// 同 MAC 跨网段即视为路由（不再要求必须是 .1）。
    private static func buildSegmentGraph(
        macGroups: [String: [LanDevice]],
        devices: [LanDevice],
        tailscaleRemote: Set<String>
    ) -> [String: Set<String>] {
        var adj: [String: Set<String>] = [:]
        for (_, entries) in macGroups {
            let segments = Set(entries.map(\.segment).filter { !TailscaleService.isRemoteSegment($0, remote: tailscaleRemote) })
            guard segments.count >= 2 else { continue }
            for a in segments {
                for b in segments where a != b {
                    adj[a, default: []].insert(b)
                }
            }
        }
        for d in devices where d.role.contains("路由") || d.role.contains("网关") || d.role.contains("Gateway") {
            let seg = d.segment
            if !TailscaleService.isRemoteSegment(seg, remote: tailscaleRemote) {
                adj[seg, default: []].insert(seg)
            }
        }
        return adj
    }

    private static func orderSegmentsFromWAN(
        primarySegment: String,
        defaultGateway: String,
        adjacency: [String: Set<String>],
        routeHops: [IPv4Address],
        devices: [LanDevice]
    ) -> [String] {
        var allSegments = Set(adjacency.keys)
        allSegments.insert(primarySegment)
        for d in devices { allSegments.insert(d.segment) }

        var parent: [String: String] = [:]
        var queue: [String] = []
        var startSegments = Set<String>()

        for hop in routeHops {
            let seg = IPv4Helpers.segmentID(for: hop)
            if seg != primarySegment { startSegments.insert(seg) }
        }
        for (_, neighbors) in adjacency where !neighbors.contains(primarySegment) {
            for n in neighbors where n != primarySegment { startSegments.insert(n) }
        }
        if startSegments.isEmpty, let gw = IPv4Helpers.parseIPv4(defaultGateway) {
            startSegments.insert(IPv4Helpers.segmentID(for: gw))
        }

        for start in startSegments {
            queue.append(start)
            parent[start] = ""
        }
        if queue.isEmpty, let any = allSegments.first(where: { $0 != primarySegment }) {
            queue = [any]
            parent[any] = ""
        }

        var visited = Set<String>()
        while !queue.isEmpty {
            let current = queue.removeFirst()
            if visited.contains(current) { continue }
            visited.insert(current)
            for next in adjacency[current, default: []] where !visited.contains(next) {
                if parent[next] == nil { parent[next] = current }
                queue.append(next)
            }
        }

        var pathToPrimary: [String] = []
        var cursor = primarySegment
        var guardSet = Set<String>()
        while cursor != "", !guardSet.contains(cursor) {
            guardSet.insert(cursor)
            pathToPrimary.insert(cursor, at: 0)
            if let p = parent[cursor] { cursor = p } else { break }
        }
        if !pathToPrimary.contains(primarySegment) {
            pathToPrimary.append(primarySegment)
        }

        var wanSide: [String] = []
        for start in startSegments {
            var chain: [String] = []
            var c = start
            var guard2 = Set<String>()
            while !guard2.contains(c) {
                guard2.insert(c)
                chain.append(c)
                if let next = adjacency[c, default: []].first(where: { pathToPrimary.contains($0) && $0 != c }) {
                    c = next
                } else { break }
            }
            for s in chain where !wanSide.contains(s) && s != primarySegment {
                wanSide.append(s)
            }
        }

        var ordered = wanSide.filter { $0 != primarySegment }
        for s in pathToPrimary where !ordered.contains(s) {
            ordered.append(s)
        }
        return ordered
    }

    private static func routerHop(
        for segment: String,
        defaultGateway: String,
        macGroups: [String: [LanDevice]],
        devices: [LanDevice]
    ) -> RouterHop? {
        let onSegment = devices.filter { $0.segment == segment }
        guard !onSegment.isEmpty else { return nil }
        let preferred = onSegment.first(where: { $0.ip == defaultGateway })
            ?? onSegment.first(where: { $0.ip.hasSuffix(".1") })
            ?? onSegment.first(where: { $0.role.contains("路由") || $0.role.contains("网关") })
            ?? onSegment[0]
        let mac = IPv4Helpers.normalizeMAC(preferred.mac)
        let aliases = macGroups[mac]?.map(\.ip).filter { $0 != preferred.ip } ?? []
        return RouterHop(
            ip: preferred.ip,
            segment: segment,
            mac: mac,
            label: "路由",
            aliasIPs: aliases,
            tier: 0,
            confirmed: !mac.isEmpty && mac != "未知"
        )
    }
}
