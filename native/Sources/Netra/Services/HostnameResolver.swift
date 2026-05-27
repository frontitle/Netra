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
        if let name = sanitize(arpHostname, ip: ip) { return name }
        if let name = bonjourOrMDNSName(ip: ip).flatMap({ sanitize($0, ip: ip) }) { return name }
        if let name = nbnsName(ip: ip).flatMap({ sanitize($0, ip: ip) }) { return name }
        if let name = netBIOSName(ip: ip).flatMap({ sanitize($0, ip: ip) }) { return name }
        if let name = dscacheHost(ip: ip).flatMap({ sanitize($0, ip: ip) }) { return name }
        if let name = reverseDNS(ip: ip).flatMap({ sanitize($0, ip: ip) }) { return name }
        if let name = refreshedARPName(ip: ip) { return name }
        return "—"
    }

    private static func sanitize(_ raw: String?, ip: String? = nil) -> String? {
        guard var name = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        if name == "?" || name == "(null)" || name == "—" { return nil }
        if name.lowercased().hasPrefix("host-") { return nil }
        if name.hasSuffix(".") { name.removeLast() }
        if name.hasSuffix(".local") { name = String(name.dropLast(6)) }
        if name.contains("\\") {
            name = name.split(separator: "\\").last.map(String.init) ?? name
        }
        if let ip, isSyntheticDNSName(name, ip: ip) { return nil }
        return name.isEmpty ? nil : name
    }

    private static func isSyntheticDNSName(_ name: String, ip: String) -> Bool {
        let lower = name.lowercased()
        let octets = ip.split(separator: ".").map(String.init)
        let dashed = octets.joined(separator: "-")
        let dotted = octets.joined(separator: ".")
        let compact = octets.joined()
        if lower == ip || lower.contains(dashed) || lower.contains(dotted) || lower.contains(compact) { return true }
        if lower.hasPrefix("ip-") || lower.hasPrefix("ip") && lower.dropFirst(2).allSatisfy({ $0.isNumber || $0 == "-" }) { return true }
        if lower.hasSuffix(".in-addr.arpa") { return true }
        return false
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

    /// NBNS (NetBIOS Name Service) 直接查询（对齐 Angry IP Scanner 这类工具的做法之一）。
    /// 发送 NBSTAT(0x21) 到 UDP/137，解析返回中的第一个 UNIQUE 名称。
    private static func nbnsName(ip: String) -> String? {
        guard let addr = IPv4Helpers.parseIPv4(ip) else { return nil }
        let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard sock >= 0 else { return nil }
        defer { close(sock) }

        var timeout = timeval(tv_sec: 0, tv_usec: 250_000)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var dst = sockaddr_in()
        dst.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        dst.sin_family = sa_family_t(AF_INET)
        dst.sin_port = in_port_t(137).bigEndian
        let bytes = addr.rawValue
        withUnsafeMutableBytes(of: &dst.sin_addr) { ptr in
            ptr.copyBytes(from: bytes)
        }

        let txid = UInt16.random(in: 0...UInt16.max)
        let query = buildNBNSNodeStatusQuery(txid: txid)
        let sent: Int = query.withUnsafeBytes { ptr in
            withUnsafePointer(to: &dst) { dstPtr in
                dstPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    sendto(sock, ptr.baseAddress, ptr.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent > 0 else { return nil }

        var buf = [UInt8](repeating: 0, count: 1024)
        var from = sockaddr_in()
        var fromLen: socklen_t = socklen_t(MemoryLayout<sockaddr_in>.size)
        let received: Int = withUnsafeMutablePointer(to: &from) { fromPtr in
            fromPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                recvfrom(sock, &buf, buf.count, 0, sa, &fromLen)
            }
        }
        guard received > 0 else { return nil }
        return parseNBNSNodeStatusResponse(buf: buf, count: received, txid: txid)
    }

    private static func buildNBNSNodeStatusQuery(txid: UInt16) -> [UInt8] {
        // Header (12):
        // TXID, Flags(0x0000), QDCOUNT=1, ANCOUNT/NSCOUNT/ARCOUNT=0
        var out: [UInt8] = []
        out.append(UInt8(txid >> 8)); out.append(UInt8(txid & 0xff))
        out.append(0x00); out.append(0x00)
        out.append(0x00); out.append(0x01)
        out.append(0x00); out.append(0x00)
        out.append(0x00); out.append(0x00)
        out.append(0x00); out.append(0x00)

        // QNAME for NBSTAT: "*"
        // Use NetBIOS encoding of 16-byte name: "*" + 15 spaces.
        let name16: [UInt8] = [0x2a] + Array(repeating: 0x20, count: 15) // '*' + spaces
        var encoded: [UInt8] = []
        encoded.reserveCapacity(32)
        for b in name16 {
            let hi = (b >> 4) & 0x0f
            let lo = b & 0x0f
            encoded.append(0x41 + hi) // 'A' + nibble
            encoded.append(0x41 + lo)
        }

        // label length = 32, then "CK" prefix per RFC1002 representation: "CK" + encoded? (common impl uses 0x20 + encoded only)
        // Practical: many tools use a single label length 0x20 and the 32 encoded bytes directly.
        out.append(0x20)
        out.append(contentsOf: encoded)
        out.append(0x00) // end of QNAME

        // QTYPE=NBSTAT(0x0021), QCLASS=IN(0x0001)
        out.append(0x00); out.append(0x21)
        out.append(0x00); out.append(0x01)
        return out
    }

    private static func parseNBNSNodeStatusResponse(buf: [UInt8], count: Int, txid: UInt16) -> String? {
        guard count >= 12 else { return nil }
        let rxid = (UInt16(buf[0]) << 8) | UInt16(buf[1])
        guard rxid == txid else { return nil }
        // ANCOUNT at bytes 6-7
        let ancount = (UInt16(buf[6]) << 8) | UInt16(buf[7])
        guard ancount >= 1 else { return nil }

        var idx = 12
        // Skip question section name
        idx = skipDNSName(buf, count, idx)
        guard idx + 4 <= count else { return nil }
        idx += 4 // QTYPE/QCLASS

        // Answer section
        idx = skipDNSName(buf, count, idx)
        guard idx + 10 <= count else { return nil }
        _ = (UInt16(buf[idx]) << 8) | UInt16(buf[idx + 1]) // type
        idx += 2
        _ = (UInt16(buf[idx]) << 8) | UInt16(buf[idx + 1]) // class
        idx += 2
        idx += 4 // ttl
        let rdlen = Int((UInt16(buf[idx]) << 8) | UInt16(buf[idx + 1]))
        idx += 2
        guard idx + rdlen <= count else { return nil }

        // Node status RDATA: first byte = number of names (N), then N * 18 bytes entries
        guard rdlen >= 1 else { return nil }
        let n = Int(buf[idx])
        idx += 1
        guard n > 0 else { return nil }
        let entrySize = 18
        let namesBytes = n * entrySize
        guard idx + namesBytes <= count else { return nil }

        for i in 0..<n {
            let off = idx + i * entrySize
            let nameBytes = Array(buf[off..<(off + 15)])
            let suffix = buf[off + 15]
            let flags = (UInt16(buf[off + 16]) << 8) | UInt16(buf[off + 17])
            let isGroup = (flags & 0x8000) != 0
            if isGroup { continue }
            // suffix 0x00=workstation service; 0x20=file server service 等
            if suffix != 0x00 && suffix != 0x20 { continue }
            let raw = String(bytes: nameBytes, encoding: .ascii)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if raw.isEmpty { continue }
            return raw
        }
        return nil
    }

    private static func skipDNSName(_ buf: [UInt8], _ count: Int, _ start: Int) -> Int {
        var idx = start
        while idx < count {
            let len = Int(buf[idx])
            if len == 0 { return idx + 1 }
            // compression pointer
            if (len & 0xC0) == 0xC0 { return idx + 2 }
            idx += 1 + len
        }
        return min(idx, count)
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
        return sanitize(entry.hostname, ip: ip)
    }
}
