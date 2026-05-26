import Foundation
import Network

/// 基于同 MAC 多网段、ARP 与路由表推断多层路由链（近 Internet → 近本机）。
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
        let adjacency = buildSegmentGraph(macGroups: macGroups, tailscaleRemote: tailscaleRemote)
        let orderedSegments = orderSegmentsFromWAN(
            primarySegment: primarySegment,
            defaultGateway: defaultGateway,
            adjacency: adjacency,
            routeHops: routeHops,
            devices: physical
        )
        var hops = orderedSegments.compactMap { segment in
            routerHop(for: segment, defaultGateway: defaultGateway, macGroups: macGroups, devices: physical)
        }
        if !defaultGateway.isEmpty, defaultGateway != "未知",
           !hops.contains(where: { $0.ip == defaultGateway }),
           let hop = routerHop(
               for: IPv4Helpers.parseIPv4(defaultGateway).map { IPv4Helpers.segmentID(for: $0) } ?? primarySegment,
               defaultGateway: defaultGateway,
               macGroups: macGroups,
               devices: physical
           ) {
            hops.append(hop)
        }
        return hops
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

    /// 同 MAC 跨网段 ⇒ 该 MAC 是连接两个网段的路由器。
    private static func buildSegmentGraph(
        macGroups: [String: [LanDevice]],
        tailscaleRemote: Set<String>
    ) -> [String: Set<String>] {
        var adj: [String: Set<String>] = [:]
        for (_, entries) in macGroups {
            let segments = Set(entries.map(\.segment).filter { !TailscaleService.isRemoteSegment($0, remote: tailscaleRemote) })
            guard segments.count >= 2 else { continue }
            let isRouterish = entries.contains { e in
                e.ip.hasSuffix(".1") || e.role.contains("路由") || e.role.contains("网关")
            }
            guard isRouterish else { continue }
            for a in segments {
                for b in segments where a != b {
                    adj[a, default: []].insert(b)
                }
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
            ?? onSegment[0]
        let mac = IPv4Helpers.normalizeMAC(preferred.mac)
        let aliases = macGroups[mac]?.map(\.ip).filter { $0 != preferred.ip } ?? []
        let isLocalGW = preferred.ip == defaultGateway
        return RouterHop(
            ip: preferred.ip,
            segment: segment,
            mac: mac,
            label: isLocalGW ? "二级路由" : "上级路由",
            aliasIPs: aliases,
            tier: 0
        )
    }
}
