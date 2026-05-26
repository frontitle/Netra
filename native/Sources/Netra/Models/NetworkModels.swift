import Foundation

struct WifiNetwork: Identifiable, Hashable, Codable {
    var id: String { bssid.isEmpty ? ssid : bssid }
    var ssid: String
    var bssid: String
    var routerVendor: String
    var channel: String
    var band: String
    var signal: String
    var signalPercent: Int
    var security: String
    var phyMode: String
    var noise: String?
    var channelWidth: String?
    var isIBSS: Bool?
    var isConnected: Bool
}

struct NetworkInterface: Codable, Hashable {
    var name: String
    var ip: String
    var netmask: String
    var cidr: UInt8
    var gateway: String
}

struct OpenPort: Identifiable, Hashable, Codable {
    var id: Int { port }
    var port: Int
    var service: String
    var hint: String
}

struct LanDevice: Identifiable, Hashable, Codable {
    var id: String { ip }
    var ip: String
    var mac: String
    var vendor: String
    var hostname: String
    var localDNS: String
    var os: String
    var role: String
    var segment: String
    var ports: [OpenPort]
}

struct TailscaleInfo: Codable, Hashable {
    var ipv4: String
    var hostname: String
    var remoteSubnets: [String]
}

struct GatewayBindingInfo: Codable, Hashable {
    var localGateway: String
    var upstreamGateway: String
    var aliasIPs: [String]
}

/// 拓扑链上的一跳路由（从靠近 Internet 到靠近本机排序，tier 由 TopologyService 填写）。
struct RouterHop: Identifiable, Hashable, Codable {
    var id: String { ip }
    var ip: String
    var segment: String
    var mac: String
    var label: String
    var aliasIPs: [String]
    var tier: Int
    var confirmed: Bool = true
}

struct LocalEndpoint: Identifiable, Hashable, Codable {
    var id: String { "\(interfaceName)-\(ip)" }
    var interfaceName: String
    var label: String
    var ip: String
    var kind: String
    var isPrimary: Bool
}

struct DualHomedDevice: Identifiable, Hashable, Codable {
    var id: String { mac }
    var mac: String
    var ips: [String]
    var role: String
    var vendor: String
}

struct NetworkSegment: Identifiable, Hashable, Codable {
    var id: String
    var cidr: String
    var gateway: String
    var deviceCount: Int
    var kind: String
    var interfaceName: String
}

struct HostInterfaceInfo: Identifiable, Hashable, Codable {
    var id: String { "\(name)-\(ip)" }
    var name: String
    var ip: String
    var cidr: UInt8
    var netmask: String
    var kind: String
    var label: String
    var gateway: String
    var status: String
}

struct TopologyNode: Identifiable, Hashable, Codable {
    var id: String
    var label: String
    var kind: String
    var ip: String
    var subtitle: String
    var status: String
    var aliasIPs: [String]
}

struct TopologyLink: Hashable, Codable {
    var source: String
    var target: String
    var label: String
}

struct NetworkTopology: Codable, Hashable {
    var segments: [NetworkSegment]
    var interfaces: [HostInterfaceInfo]
    var gatewayBinding: GatewayBindingInfo?
    var routerChain: [RouterHop]
    var dualHomed: [DualHomedDevice]
    var primaryInterface: String
    var nodes: [TopologyNode]
    var links: [TopologyLink]
}

struct LanScanResult: Codable, Hashable {
    var interface: NetworkInterface
    var localIPs: [String]
    var localEndpoints: [LocalEndpoint]?
    var devices: [LanDevice]
    var topology: NetworkTopology
    var tailscale: TailscaleInfo?
}

enum PingQuality: String, Codable {
    case good, warning, bad, down
}

struct PingStats: Identifiable, Hashable, Codable {
    var id: String { target }
    var target: String
    var label: String
    var avgMs: Double
    var minMs: Double
    var maxMs: Double
    var jitterMs: Double
    var packetLoss: Double
    var status: PingQuality
    var measuredAt: Date?

    enum CodingKeys: String, CodingKey {
        case target, label, avgMs, minMs, maxMs, jitterMs, packetLoss, status, measuredAt
    }

    init(target: String, label: String, avgMs: Double, minMs: Double, maxMs: Double, jitterMs: Double, packetLoss: Double, status: PingQuality, measuredAt: Date? = nil) {
        self.target = target
        self.label = label
        self.avgMs = avgMs
        self.minMs = minMs
        self.maxMs = maxMs
        self.jitterMs = jitterMs
        self.packetLoss = packetLoss
        self.status = status
        self.measuredAt = measuredAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        target = try c.decode(String.self, forKey: .target)
        label = try c.decode(String.self, forKey: .label)
        avgMs = try c.decode(Double.self, forKey: .avgMs)
        minMs = try c.decode(Double.self, forKey: .minMs)
        maxMs = try c.decode(Double.self, forKey: .maxMs)
        jitterMs = try c.decode(Double.self, forKey: .jitterMs)
        packetLoss = try c.decode(Double.self, forKey: .packetLoss)
        status = try c.decode(PingQuality.self, forKey: .status)
        measuredAt = try c.decodeIfPresent(Date.self, forKey: .measuredAt)
    }
}

struct QualityReport: Codable, Hashable {
    var interface: NetworkInterface
    var gateway: PingStats
    var external: [PingStats]
    var devices: [PingStats]
    var diagnosis: String
    var suspects: [String]
}

struct ScanSnapshot: Identifiable, Codable, Hashable {
    var id: UUID
    var networkKey: String
    var networkName: String
    var scannedAt: Date
    var wifiNetworks: [WifiNetwork]
    var lanResult: LanScanResult?
    var devices: [LanDevice]
}

enum AppSection: String, CaseIterable, Identifiable {
    case radar, quality, wifi, history, settings
    var id: String { rawValue }
}

struct ArpEntry {
    var mac: String
    var hostname: String?
    var interfaceName: String
}
