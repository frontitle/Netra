import Foundation
import Network

enum LANScanner {
    static func scan(onDeviceFound: ((LanDevice) -> Void)? = nil) throws -> LanScanResult {
        ScanCancellation.shared.reset()
        let interface = try NetworkInterfaceService.currentInterface()
        guard let localIP = IPv4Helpers.parseIPv4(interface.ip) else {
            throw ScanError.message("当前 IP 无效")
        }
        let primarySegment = IPv4Helpers.segmentID(for: localIP)
        let (routeGateways, routeSegments) = RouteTableService.routeTable()
        let hostInterfaces = NetworkInterfaceService.parseAllHostInterfaces(primary: interface)
        var arpEntries = ARPService.readAll()
        let routeHops = RouteTableService.discoverRouteHops()
        let tailscale = TailscaleService.detect(primaryIP: interface.ip)
        let tailscaleRemote = Set(tailscale?.remoteSubnets ?? [])

        var candidates = discoverCandidateSegments(
            interface: interface,
            routeGateways: routeGateways,
            routeSegments: routeSegments,
            hostInterfaces: hostInterfaces,
            arpEntries: arpEntries,
            routeHops: routeHops,
            tailscaleRemote: tailscaleRemote
        )
        var scannedSegmentKeys = Set(candidates.map { segKey($0.0, $0.1) })
        PingService.sweep(collectPingTargets(candidates).map { IPv4Helpers.ipv4String($0) })
        if ScanCancellation.shared.isCancelled { return cancelledResult(interface: interface) }
        Thread.sleep(forTimeInterval: 0.12)
        arpEntries = ARPService.readAll()

        // 发现新网段则继续 ping 遍历，直到稳定（最多 4 轮）
        for _ in 0..<4 {
            if ScanCancellation.shared.isCancelled { break }
            let discovered = Set(arpEntries.keys.map { IPv4Helpers.segmentID(for: $0) })
                .filter { !TailscaleService.isRemoteSegment($0, remote: tailscaleRemote) && !IPv4Helpers.isIgnoredSegment($0) }
            let fresh = discovered.filter { !scannedSegmentKeys.contains($0) }
            guard !fresh.isEmpty else { break }
            var extra: [(IPv4Address, UInt8)] = []
            for segment in fresh {
                scannedSegmentKeys.insert(segment)
                if let ip = devicesSegmentBase(segment) {
                    extra.append((ip, 24))
                }
            }
            candidates.append(contentsOf: extra)
            PingService.sweep(collectPingTargets(extra).map { IPv4Helpers.ipv4String($0) })
            Thread.sleep(forTimeInterval: 0.12)
            arpEntries = ARPService.readAll()
        }

        var ips = Set(arpEntries.keys)
        ips.insert(localIP)
        if let gw = IPv4Helpers.parseIPv4(interface.gateway) { ips.insert(gw) }
        routeGateways.forEach { ips.insert($0) }
        routeHops.forEach { ips.insert($0) }

        var devices: [LanDevice] = []
        let ports = IPv4Helpers.defaultScanPorts
        for ip in ips.sorted(by: { IPv4Helpers.ipv4ToUInt32($0) < IPv4Helpers.ipv4ToUInt32($1) }) {
            if ScanCancellation.shared.isCancelled { break }
            guard IPv4Helpers.isValidHost(ip) else { continue }
            let ipStr = IPv4Helpers.ipv4String(ip)
            let arp = arpEntries[ip]
            let mac = arp?.mac ?? "未知"
            if IPv4Helpers.isIgnoredMAC(mac), arp == nil { continue }
            let hostname = DeviceInference.hostname(from: arp?.hostname, ip: ipStr)
            var openPorts = PortScanner.scanTCP(ip: ip, ports: ports)
            openPorts.append(contentsOf: PortScanner.scanUDP(ip: ip, ports: IPv4Helpers.udpProbePorts))
            let vendor = OUILookup.vendor(for: mac, hostname: hostname, ports: openPorts)
            let os = DeviceInference.inferOS(ports: openPorts, vendor: vendor, mac: mac)
            let role = DeviceInference.inferRole(ip: ipStr, localIP: interface.ip, gateway: interface.gateway, vendor: vendor, ports: openPorts)
            let device = LanDevice(
                ip: ipStr,
                mac: mac,
                vendor: vendor,
                hostname: hostname,
                localDNS: DeviceInference.localDNS(hostname: hostname, ip: ipStr),
                os: os,
                role: role,
                segment: IPv4Helpers.segmentID(for: ip),
                ports: openPorts
            )
            if TailscaleService.isRemoteSegment(device.segment, remote: tailscaleRemote) { continue }
            onDeviceFound?(device)
            devices.append(device)
        }

        var binding = GatewayService.discoverBinding(
            defaultGateway: interface.gateway,
            devices: devices,
            routeHops: routeHops,
            primarySegment: primarySegment,
            tailscaleRemote: tailscaleRemote
        )
        if let initialBinding = binding, !initialBinding.upstreamGateway.isEmpty,
           let upstream = IPv4Helpers.parseIPv4(initialBinding.upstreamGateway) {
            let upstreamSeg = IPv4Helpers.networkBase(upstream, cidr: 24)
            PingService.sweep(collectPingTargets([(upstreamSeg, 24)]).map { IPv4Helpers.ipv4String($0) })
            Thread.sleep(forTimeInterval: 0.1)
            let upstreamARP = ARPService.readAll()
            var extraIPs = Set<IPv4Address>()
            for (ip, entry) in upstreamARP where IPv4Helpers.isValidHost(ip) {
                arpEntries[ip] = entry
                if !devices.contains(where: { $0.ip == IPv4Helpers.ipv4String(ip) }) {
                    extraIPs.insert(ip)
                }
            }
            if let upIP = IPv4Helpers.parseIPv4(initialBinding.upstreamGateway) { extraIPs.insert(upIP) }
            initialBinding.aliasIPs.forEach { if let a = IPv4Helpers.parseIPv4($0) { extraIPs.insert(a) } }
            for ip in extraIPs {
                let ipStr = IPv4Helpers.ipv4String(ip)
                let arp = arpEntries[ip]
                let mac = arp?.mac ?? "未知"
                let hostname = DeviceInference.hostname(from: arp?.hostname, ip: ipStr)
                var openPorts = PortScanner.scanTCP(ip: ip, ports: ports)
                openPorts.append(contentsOf: PortScanner.scanUDP(ip: ip, ports: IPv4Helpers.udpProbePorts))
                let vendor = OUILookup.vendor(for: mac, hostname: hostname, ports: openPorts)
                let os = DeviceInference.inferOS(ports: openPorts, vendor: vendor, mac: mac)
                let role = DeviceInference.inferRole(ip: ipStr, localIP: interface.ip, gateway: interface.gateway, vendor: vendor, ports: openPorts)
                let device = LanDevice(
                    ip: ipStr, mac: mac, vendor: vendor, hostname: hostname,
                    localDNS: DeviceInference.localDNS(hostname: hostname, ip: ipStr),
                    os: os, role: role, segment: IPv4Helpers.segmentID(for: ip), ports: openPorts
                )
                if !TailscaleService.isRemoteSegment(device.segment, remote: tailscaleRemote) {
                    onDeviceFound?(device)
                    devices.append(device)
                }
            }
        }
        binding = GatewayService.discoverBinding(
            defaultGateway: interface.gateway,
            devices: devices,
            routeHops: routeHops,
            primarySegment: primarySegment,
            tailscaleRemote: tailscaleRemote
        )
        var routerChain = RouterTopologyService.discoverChain(
            primarySegment: primarySegment,
            defaultGateway: interface.gateway,
            devices: devices,
            routeHops: routeHops,
            gatewayBinding: binding,
            tailscaleRemote: tailscaleRemote
        )
        for i in routerChain.indices { routerChain[i].tier = i }
        applyGatewayRoles(&devices, binding: binding, routerChain: routerChain)
        let dualHomed = discoverDualHomed(devices: devices, hostInterfaces: hostInterfaces)
        var localIPs = NetworkInterfaceService.collectLocalIPs(primary: interface, interfaces: hostInterfaces)
        if let ts = tailscale, !ts.ipv4.isEmpty, !localIPs.contains(ts.ipv4) { localIPs.append(ts.ipv4) }
        let localEndpoints = buildLocalEndpoints(primary: interface, interfaces: hostInterfaces)
        let topology = TopologyService.build(
            interface: interface,
            devices: devices,
            hostInterfaces: hostInterfaces,
            gatewayBinding: binding,
            routerChain: routerChain,
            dualHomed: dualHomed,
            localIPs: localIPs,
            tunnelSubnets: tailscale?.remoteSubnets ?? [],
            routeSegments: routeSegments
        )
        return LanScanResult(
            interface: interface,
            localIPs: localIPs,
            localEndpoints: localEndpoints,
            devices: devices,
            topology: topology,
            tailscale: tailscale
        )
    }

    private static func discoverCandidateSegments(
        interface: NetworkInterface,
        routeGateways: Set<IPv4Address>,
        routeSegments: [String: (IPv4Address, UInt8)],
        hostInterfaces: [HostInterfaceInfo],
        arpEntries: [IPv4Address: ArpEntry],
        routeHops: [IPv4Address],
        tailscaleRemote: Set<String>
    ) -> [(IPv4Address, UInt8)] {
        var segments = Set<String>()
        var result: [(IPv4Address, UInt8)] = []
        func insert(_ network: IPv4Address, _ cidr: UInt8) {
            let c = min(max(cidr, 24), 30)
            let key = "\(IPv4Helpers.ipv4String(IPv4Helpers.networkBase(network, cidr: c)))/\(c)"
            if segments.insert(key).inserted {
                result.append((IPv4Helpers.networkBase(network, cidr: c), c))
            }
        }
        if let local = IPv4Helpers.parseIPv4(interface.ip) {
            insert(local, interface.cidr)
        }
        for (_, seg) in routeSegments {
            let prefix = min(max(seg.1, 16), 24)
            guard prefix <= 24 else { continue }
            let key = "\(IPv4Helpers.ipv4String(IPv4Helpers.networkBase(seg.0, cidr: prefix)))/\(prefix)"
            if TailscaleService.isRemoteSegment(key, remote: tailscaleRemote) { continue }
            if IPv4Helpers.isScannable(seg.0) { insert(seg.0, prefix) }
        }
        for gw in routeGateways where IPv4Helpers.isScannable(gw) { insert(gw, 24) }
        for hop in routeHops where IPv4Helpers.isScannable(hop) { insert(hop, 24) }
        for iface in hostInterfaces where iface.status == "up" {
            guard let ip = IPv4Helpers.parseIPv4(iface.ip), IPv4Helpers.isScannable(ip) else { continue }
            insert(ip, iface.cidr)
        }
        for (ip, _) in arpEntries where IPv4Helpers.isScannable(ip) && !TailscaleService.isRemoteSegment(IPv4Helpers.segmentID(for: ip), remote: tailscaleRemote) {
            insert(ip, 24)
        }
        return Array(result.prefix(12))
    }

    private static func collectPingTargets(_ segments: [(IPv4Address, UInt8)]) -> [IPv4Address] {
        var targets = Set<IPv4Address>()
        for (network, cidr) in segments {
            for ip in IPv4Helpers.enumerateHosts(network: network, cidr: cidr) where IPv4Helpers.isValidHost(ip) {
                targets.insert(ip)
                if targets.count >= 240 { return Array(targets) }
            }
        }
        return Array(targets)
    }

    private static func segKey(_ network: IPv4Address, _ cidr: UInt8) -> String {
        let c = min(max(cidr, 24), 30)
        return "\(IPv4Helpers.ipv4String(IPv4Helpers.networkBase(network, cidr: c)))/\(c)"
    }

    private static func devicesSegmentBase(_ segment: String) -> IPv4Address? {
        let base = segment.split(separator: "/").first.map(String.init) ?? ""
        return IPv4Helpers.parseIPv4(base)
    }

    private static func applyGatewayRoles(
        _ devices: inout [LanDevice],
        binding: GatewayBindingInfo?,
        routerChain: [RouterHop]
    ) {
        let chainIPs = Set(routerChain.flatMap { [$0.ip] + $0.aliasIPs })
        for i in devices.indices {
            if let hop = routerChain.first(where: { $0.ip == devices[i].ip }) {
                devices[i].role = "\(hop.label) · \(hop.segment)"
            } else if chainIPs.contains(devices[i].ip) {
                devices[i].role = "路由接口"
            }
        }
        guard let binding else { return }
        for i in devices.indices {
            if devices[i].ip == binding.localGateway, !devices[i].role.contains("路由") {
                devices[i].role = binding.upstreamGateway.isEmpty ? "网关 / 路由器" : "网关 / 二级路由"
            }
        }
    }

    private static func discoverDualHomed(devices: [LanDevice], hostInterfaces: [HostInterfaceInfo]) -> [DualHomedDevice] {
        var groups: [String: [LanDevice]] = [:]
        for d in devices {
            let mac = IPv4Helpers.normalizeMAC(d.mac)
            guard !mac.isEmpty, mac != "未知" else { continue }
            groups[mac, default: []].append(d)
        }
        return groups.compactMap { mac, entries in
            let ips = Set(entries.map(\.ip))
            guard ips.count >= 2 else { return nil }
            let segments = Set(entries.map(\.segment))
            let gatewayish = entries.contains { $0.role.contains("网关") || $0.role.contains("路由") }
            let vpnish = entries.contains { e in hostInterfaces.contains { $0.kind == "vpn" && $0.status == "up" && $0.ip == e.ip } }
            guard segments.count >= 2 || gatewayish || vpnish else { return nil }
            let role = gatewayish ? "双栈网关 / 二级路由" : (vpnish ? "VPN / 隧道接口" : "多网段设备")
            return DualHomedDevice(mac: mac, ips: Array(ips).sorted(), role: role, vendor: entries.first?.vendor ?? "未知厂商")
        }
    }

    private static func buildLocalEndpoints(primary: NetworkInterface, interfaces: [HostInterfaceInfo]) -> [LocalEndpoint] {
        interfaces
            .filter { $0.status == "up" && !$0.ip.isEmpty && !$0.ip.hasPrefix("127.") }
            .map { iface in
                LocalEndpoint(
                    interfaceName: iface.name,
                    label: "\(iface.name) · \(iface.label)",
                    ip: iface.ip,
                    kind: iface.kind,
                    isPrimary: iface.ip == primary.ip
                )
            }
            .sorted { a, b in
                if a.isPrimary != b.isPrimary { return a.isPrimary }
                return a.interfaceName.localizedStandardCompare(b.interfaceName) == .orderedAscending
            }
    }

    private static func cancelledResult(interface: NetworkInterface) -> LanScanResult {
        LanScanResult(
            interface: interface,
            localIPs: [interface.ip],
            localEndpoints: [LocalEndpoint(interfaceName: interface.name, label: interface.name, ip: interface.ip, kind: "wifi", isPrimary: true)],
            devices: [],
            topology: NetworkTopology(segments: [], interfaces: [], gatewayBinding: nil, routerChain: [], dualHomed: [], primaryInterface: interface.name, nodes: [], links: []),
            tailscale: nil
        )
    }
}
