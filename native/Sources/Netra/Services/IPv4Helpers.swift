import Foundation
import Network

enum IPv4Helpers {
    static let defaultScanPorts: [UInt16] = [
        22, 53, 80, 139, 443, 445, 548, 554, 5000, 5001, 7000, 8000, 8001, 8080, 8081, 8181, 8443, 9000, 631, 5900, 5353,
    ]
    static let udpProbePorts: [UInt16] = [53, 123, 137, 1900]

    static func parseIPv4(_ text: String) -> IPv4Address? {
        IPv4Address(text.trimmingCharacters(in: .whitespaces))
    }

    static func segmentID(for ip: IPv4Address) -> String {
        "\(networkBase(ip, cidr: 24).debugDescription)/24"
    }

    static func networkBase(_ ip: IPv4Address, cidr: UInt8) -> IPv4Address {
        let c = min(max(cidr, 24), 30)
        let mask = UInt32.max << (32 - Int(c))
        let raw = ipv4ToUInt32(ip) & mask
        return uint32ToIPv4(raw) ?? ip
    }

    static func enumerateHosts(network: IPv4Address, cidr: UInt8) -> [IPv4Address] {
        let c = min(max(cidr, 24), 30)
        let hostBits = 32 - Int(c)
        let count = max(0, (1 << hostBits) - 2)
        guard count > 0 else { return [] }
        let base = networkBase(network, cidr: c)
        let baseRaw = ipv4ToUInt32(base)
        return (1..<(count + 1)).prefix(72).compactMap { offset in
            let value = baseRaw + UInt32(offset)
            return uint32ToIPv4(value)
        }
    }

    static func ipv4ToUInt32(_ ip: IPv4Address) -> UInt32 {
        let bytes = ip.rawValue
        return (UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16) | (UInt32(bytes[2]) << 8) | UInt32(bytes[3])
    }

    static func uint32ToIPv4(_ value: UInt32) -> IPv4Address? {
        IPv4Address("\(value >> 24 & 0xff).\(value >> 16 & 0xff).\(value >> 8 & 0xff).\(value & 0xff)")
    }

    static func isScannable(_ ip: IPv4Address) -> Bool {
        let b = ip.rawValue
        if b[0] == 10 { return true }
        if b[0] == 172 && (16...31).contains(b[1]) { return true }
        if b[0] == 192 && b[1] == 168 { return true }
        return false
    }

    static func isValidHost(_ ip: IPv4Address) -> Bool {
        let b = ip.rawValue
        if b[3] == 0 || b[3] == 255 { return false }
        return isScannable(ip)
    }

    static func normalizeMAC(_ mac: String) -> String {
        mac.uppercased()
            .replacingOccurrences(of: "-", with: ":")
            .split(separator: ":")
            .map { $0.count == 1 ? "0\($0)" : String($0) }
            .joined(separator: ":")
    }

    static func isIgnoredMAC(_ mac: String) -> Bool {
        let m = normalizeMAC(mac)
        return m.isEmpty || m == "FF:FF:FF:FF:FF:FF" || m.hasPrefix("00:00:00")
    }

    static func isIgnoredSegment(_ cidr: String) -> Bool {
        cidr.hasPrefix("169.254.") || cidr.contains("127.0.0")
    }
}
