import Darwin
import Foundation

/// 通过 Bonjour (mDNS)、NetBIOS (SMB)、DNS 等解析设备自报主机名。
enum HostnameResolver {
    /// 对一批 IP 并行解析（建议在 ping 之后调用）。
    static func resolveBatch(ips: [String], arpHints: [String: String] = [:]) -> [String: String] {
        let unique = Array(Set(ips)).filter { !$0.isEmpty }
        guard !unique.isEmpty else { return [:] }

        var results: [String: String] = [:]
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: unique.count) { index in
            let ip = unique[index]
            let hint = arpHints[ip]
            let name = resolve(ip: ip, arpHostname: hint)
            if name != "—" {
                lock.lock()
                results[ip] = name
                lock.unlock()
            }
        }
        return results
    }

    static func resolve(ip: String, arpHostname: String? = nil) -> String {
        if let name = sanitize(arpHostname) { return name }
        if let name = bonjourOrMDNSName(ip: ip).flatMap(sanitize) { return name }
        if let name = netBIOSName(ip: ip).flatMap(sanitize) { return name }
        if let name = dscacheHost(ip: ip).flatMap(sanitize) { return name }
        if let name = reverseDNS(ip: ip).flatMap(sanitize) { return name }
        if let name = refreshedARPName(ip: ip) { return name }
        return "—"
    }

    private static func sanitize(_ raw: String?) -> String? {
        guard var name = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        if name == "?" || name == "(null)" || name == "—" { return nil }
        if name.lowercased().hasPrefix("host-") { return nil }
        if name.hasSuffix(".") { name.removeLast() }
        if name.hasSuffix(".local") { name = String(name.dropLast(6)) }
        if name.contains("\\") {
            name = name.split(separator: "\\").last.map(String.init) ?? name
        }
        return name.isEmpty ? nil : name
    }

    /// Bonjour / mDNS 反向解析（依赖系统 mDNSResponder，ping 后更易成功）。
    private static func bonjourOrMDNSName(ip: String) -> String? {
        guard let addr = IPv4Helpers.parseIPv4(ip) else { return nil }
        var storage = sockaddr_in()
        storage.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        storage.sin_family = sa_family_t(AF_INET)
        let bytes = addr.rawValue
        withUnsafeMutableBytes(of: &storage.sin_addr) { ptr in
            ptr.copyBytes(from: bytes)
        }
        var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = withUnsafePointer(to: &storage) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                getnameinfo(
                    sockaddrPtr,
                    socklen_t(MemoryLayout<sockaddr_in>.size),
                    &hostBuffer,
                    socklen_t(hostBuffer.count),
                    nil,
                    0,
                    NI_NAMEREQD
                )
            }
        }
        guard result == 0 else { return nil }
        let name = String(cString: hostBuffer)
        guard !name.isEmpty, name != ip else { return nil }
        return name
    }

    /// NetBIOS 名称（macOS 通过 smbutil）。
    private static func netBIOSName(ip: String) -> String? {
        guard let output = ShellRunner.run("/usr/sbin/smbutil", ["lookup", "-a", ip]) else { return nil }
        for line in output.split(separator: "\n") {
            let row = String(line).trimmingCharacters(in: .whitespaces)
            if row.lowercased().hasPrefix("name:") {
                return row.split(separator: ":", maxSplits: 1).last.map { String($0).trimmingCharacters(in: .whitespaces) }
            }
        }
        return nil
    }

    private static func dscacheHost(ip: String) -> String? {
        guard let output = ShellRunner.run("/usr/bin/dscacheutil", ["-q", "host", "-a", "ip_address", ip]) else { return nil }
        for line in output.split(separator: "\n") {
            let row = String(line).trimmingCharacters(in: .whitespaces)
            if row.hasPrefix("name:") {
                return row.replacingOccurrences(of: "name:", with: "").trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private static func reverseDNS(ip: String) -> String? {
        guard let output = ShellRunner.run("/usr/bin/host", [ip]) else { return nil }
        for line in output.split(separator: "\n") {
            let row = String(line)
            if row.contains("domain name pointer") {
                return row.split(separator: " ").last.map(String.init)?
                    .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            }
        }
        return nil
    }

    private static func refreshedARPName(ip: String) -> String? {
        guard let addr = IPv4Helpers.parseIPv4(ip) else { return nil }
        guard let entry = ARPService.readAll()[addr] else { return nil }
        return sanitize(entry.hostname)
    }
}
