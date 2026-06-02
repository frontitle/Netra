import Foundation

struct KnownDeviceRecord: Codable, Hashable {
    var ip: String
    var mac: String
    var hostname: String
    var vendor: String
    var role: String
    var os: String
    var segment: String
    var ports: [OpenPort]
    var lastSeen: Date
}

/// 记录历史上见过的设备，用于提示本次扫描中消失的设备。
final class KnownDevicesStore {
    static let shared = KnownDevicesStore()

    private var records: [String: KnownDeviceRecord] = [:]
    private let fileURL: URL

    private init() {
        fileURL = AppStorage.supportDirectory().appendingPathComponent("known-devices.json")
        load()
    }

    func applyScan(_ online: [LanDevice]) {
        let now = Date()
        for d in online {
            records[d.ip] = KnownDeviceRecord(
                ip: d.ip, mac: d.mac, hostname: d.hostname, vendor: d.vendor,
                role: d.role, os: d.os, segment: d.segment, ports: d.ports, lastSeen: now
            )
        }
        save()
    }

    func remove(ip: String) {
        records.removeValue(forKey: ip)
        save()
    }

    func missingDevices(segment: String, excludingOnline onlineIPs: Set<String>) -> [LanDevice] {
        records.values
            .filter { $0.segment == segment && !onlineIPs.contains($0.ip) }
            .map { r in
                LanDevice(
                    ip: r.ip, mac: r.mac, vendor: r.vendor, hostname: r.hostname,
                    localDNS: DeviceInference.localDNS(hostname: r.hostname, ip: r.ip),
                    os: r.os, role: r.role, segment: r.segment, ports: r.ports,
                    isOnline: false
                )
            }
            .sorted { $0.ip.localizedStandardCompare($1.ip) == .orderedAscending }
    }

    func lastSeen(ip: String) -> Date? {
        records[ip]?.lastSeen
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: KnownDeviceRecord].self, from: data) else { return }
        records = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
