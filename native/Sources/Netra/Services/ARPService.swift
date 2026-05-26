import Foundation
import Network

enum ARPService {
    static func readAll() -> [IPv4Address: ArpEntry] {
        var map: [IPv4Address: ArpEntry] = [:]
        guard let output = ShellRunner.run("/usr/sbin/arp", ["-a"]) else { return map }
        for line in output.split(separator: "\n") {
            let row = String(line)
            if row.contains("(incomplete)") || row.contains("permanent") { continue }
            guard let open = row.firstIndex(of: "("), let close = row[open...].firstIndex(of: ")") else { continue }
            let ipPart = String(row[row.index(after: open)..<close])
            guard let ip = IPv4Helpers.parseIPv4(ipPart), IPv4Helpers.isValidHost(ip) else { continue }
            guard let atRange = row.range(of: " at ") else { continue }
            let afterAt = row[atRange.upperBound...]
            let macPart = afterAt.split(separator: " ").first.map(String.init) ?? ""
            if IPv4Helpers.isIgnoredMAC(macPart) { continue }
            let iface = row.split(separator: " on ").dropFirst().first?
                .split(separator: " ").first.map(String.init) ?? "unknown"
            let name = row.split(separator: "(").first.map { $0.trimmingCharacters(in: .whitespaces) }
            let hostname = (name == "?" || name?.isEmpty == true) ? nil : name
            map[ip] = ArpEntry(mac: IPv4Helpers.normalizeMAC(macPart), hostname: hostname, interfaceName: iface)
        }
        return map
    }

    static func refresh(ip: String) {
        _ = ShellRunner.run("/sbin/ping", ["-c", "1", "-W", "1000", ip])
    }
}
