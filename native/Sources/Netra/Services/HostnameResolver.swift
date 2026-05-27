import Darwin
import Foundation

/// 通过 Bonjour (mDNS)、NetBIOS (SMB)、DNS、LLMNR、SSDP/UPnP 等解析设备自报主机名。
enum HostnameResolver {
    private static let llmnrPort: UInt16 = 5355
    private static let ssdpPort: UInt16 = 1900
    private static let hostnameTimeoutMs = 180
    private static let receiveLoopMaxPackets = 3
    private static let ssdpLocationTimeoutMs = 350

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
        if let name = llmnrName(ip: ip).flatMap({ sanitize($0, ip: ip) }) { return name }
        if let name = ssdpFriendlyName(ip: ip).flatMap({ sanitize($0, ip: ip) }) { return name }
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

        configureReceiveTimeout(sock: sock, timeoutMs: hostnameTimeoutMs)

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

        guard let received = receiveUDP(sock: sock, expectedIP: ip, bufferSize: 1024) else { return nil }
        return parseNBNSNodeStatusResponse(buf: received.buffer, count: received.count, txid: txid)
    }

    /// LLMNR 反向 PTR 查询，命中 Windows / IoT 设备时可拿到主机名。
    private static func llmnrName(ip: String) -> String? {
        guard let addr = IPv4Helpers.parseIPv4(ip) else { return nil }
        let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard sock >= 0 else { return nil }
        defer { close(sock) }

        configureReceiveTimeout(sock: sock, timeoutMs: hostnameTimeoutMs)

        var dst = sockaddr_in()
        dst.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        dst.sin_family = sa_family_t(AF_INET)
        dst.sin_port = in_port_t(llmnrPort).bigEndian
        let bytes = addr.rawValue
        withUnsafeMutableBytes(of: &dst.sin_addr) { ptr in
            ptr.copyBytes(from: bytes)
        }

        let txid = UInt16.random(in: 0...UInt16.max)
        guard let query = buildLLMNRPTRQuery(ip: ip, txid: txid) else { return nil }
        let sent: Int = query.withUnsafeBytes { ptr in
            withUnsafePointer(to: &dst) { dstPtr in
                dstPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    sendto(sock, ptr.baseAddress, ptr.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent > 0 else { return nil }

        guard let received = receiveUDP(sock: sock, expectedIP: ip, bufferSize: 1024) else { return nil }
        return parsePTRResponse(buf: received.buffer, count: received.count, txid: txid)
    }

    /// SSDP / UPnP 单播探测。优先取响应头中的 SERVER/USN/LOCATION，再尝试读取描述 XML 中的 friendlyName。
    private static func ssdpFriendlyName(ip: String) -> String? {
        guard let addr = IPv4Helpers.parseIPv4(ip) else { return nil }
        let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard sock >= 0 else { return nil }
        defer { close(sock) }

        configureReceiveTimeout(sock: sock, timeoutMs: hostnameTimeoutMs)

        var dst = sockaddr_in()
        dst.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        dst.sin_family = sa_family_t(AF_INET)
        dst.sin_port = in_port_t(ssdpPort).bigEndian
        let bytes = addr.rawValue
        withUnsafeMutableBytes(of: &dst.sin_addr) { ptr in
            ptr.copyBytes(from: bytes)
        }

        let payload = Array(ssdpDiscoveryPayload.utf8)
        let sent: Int = payload.withUnsafeBytes { ptr in
            withUnsafePointer(to: &dst) { dstPtr in
                dstPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    sendto(sock, ptr.baseAddress, ptr.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent > 0 else { return nil }

        guard let received = receiveUDP(sock: sock, expectedIP: ip, bufferSize: 4096) else { return nil }
        let response = String(decoding: received.buffer.prefix(received.count), as: UTF8.self)
        let headers = parseHTTPHeaders(response)
        if let friendly = headers["x-user-friendly-name"] ?? headers["friendlyname"],
           let name = sanitize(friendly, ip: ip) {
            return name
        }
        if let server = headers["server"], let name = bestSSDPHeaderName(server, ip: ip) { return name }
        if let usn = headers["usn"], let name = bestSSDPHeaderName(usn, ip: ip) { return name }
        if let location = headers["location"], let name = fetchUPnPDeviceDescriptionName(from: location, expectedIP: ip) {
            return name
        }
        return nil
    }

    private static func buildNBNSNodeStatusQuery(txid: UInt16) -> [UInt8] {
        var out: [UInt8] = []
        out.append(UInt8(txid >> 8)); out.append(UInt8(txid & 0xff))
        out.append(0x00); out.append(0x00)
        out.append(0x00); out.append(0x01)
        out.append(0x00); out.append(0x00)
        out.append(0x00); out.append(0x00)
        out.append(0x00); out.append(0x00)

        let name16: [UInt8] = [0x2a] + Array(repeating: 0x20, count: 15)
        var encoded: [UInt8] = []
        encoded.reserveCapacity(32)
        for b in name16 {
            let hi = (b >> 4) & 0x0f
            let lo = b & 0x0f
            encoded.append(0x41 + hi)
            encoded.append(0x41 + lo)
        }

        out.append(0x20)
        out.append(contentsOf: encoded)
        out.append(0x00)
        out.append(0x00); out.append(0x21)
        out.append(0x00); out.append(0x01)
        return out
    }

    private static func buildLLMNRPTRQuery(ip: String, txid: UInt16) -> [UInt8]? {
        let octets = ip.split(separator: ".")
        guard octets.count == 4 else { return nil }

        var out: [UInt8] = []
        out.append(UInt8(txid >> 8)); out.append(UInt8(txid & 0xff))
        out.append(0x00); out.append(0x00)
        out.append(0x00); out.append(0x01)
        out.append(0x00); out.append(0x00)
        out.append(0x00); out.append(0x00)
        out.append(0x00); out.append(0x00)

        let reverseLabels = octets.reversed().map(String.init) + ["in-addr", "arpa"]
        for label in reverseLabels {
            let bytes = Array(label.utf8)
            guard !bytes.isEmpty, bytes.count <= 63 else { return nil }
            out.append(UInt8(bytes.count))
            out.append(contentsOf: bytes)
        }
        out.append(0x00)
        out.append(0x00); out.append(0x0c)
        out.append(0x00); out.append(0x01)
        return out
    }

    private static func parseNBNSNodeStatusResponse(buf: [UInt8], count: Int, txid: UInt16) -> String? {
        guard count >= 12 else { return nil }
        let rxid = (UInt16(buf[0]) << 8) | UInt16(buf[1])
        guard rxid == txid else { return nil }
        let ancount = (UInt16(buf[6]) << 8) | UInt16(buf[7])
        guard ancount >= 1 else { return nil }

        var idx = 12
        idx = skipDNSName(buf, count, idx)
        guard idx + 4 <= count else { return nil }
        idx += 4

        idx = skipDNSName(buf, count, idx)
        guard idx + 10 <= count else { return nil }
        idx += 2
        idx += 2
        idx += 4
        let rdlen = Int((UInt16(buf[idx]) << 8) | UInt16(buf[idx + 1]))
        idx += 2
        guard idx + rdlen <= count else { return nil }

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
            if suffix != 0x00 && suffix != 0x20 { continue }
            let raw = String(bytes: nameBytes, encoding: .ascii)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if raw.isEmpty { continue }
            return raw
        }
        return nil
    }

    private static func parsePTRResponse(buf: [UInt8], count: Int, txid: UInt16) -> String? {
        guard count >= 12 else { return nil }
        let rxid = (UInt16(buf[0]) << 8) | UInt16(buf[1])
        guard rxid == txid else { return nil }
        let qdcount = Int((UInt16(buf[4]) << 8) | UInt16(buf[5]))
        let ancount = Int((UInt16(buf[6]) << 8) | UInt16(buf[7]))
        guard ancount > 0 else { return nil }

        var idx = 12
        for _ in 0..<qdcount {
            idx = skipDNSName(buf, count, idx)
            guard idx + 4 <= count else { return nil }
            idx += 4
        }

        for _ in 0..<ancount {
            idx = skipDNSName(buf, count, idx)
            guard idx + 10 <= count else { return nil }
            let type = (UInt16(buf[idx]) << 8) | UInt16(buf[idx + 1])
            idx += 2
            idx += 2
            idx += 4
            let rdlen = Int((UInt16(buf[idx]) << 8) | UInt16(buf[idx + 1]))
            idx += 2
            guard idx + rdlen <= count else { return nil }
            if type == 0x000c {
                return decodeDNSName(buf, count, idx)
            }
            idx += rdlen
        }
        return nil
    }

    private static func skipDNSName(_ buf: [UInt8], _ count: Int, _ start: Int) -> Int {
        guard start >= 0, start < count else { return count }
        var idx = start
        var guardCount = 0
        while idx < count && guardCount < 64 {
            guardCount += 1
            let len = Int(buf[idx])
            if len == 0 { return idx + 1 }
            if (len & 0xC0) == 0xC0 {
                return idx + 1 < count ? idx + 2 : count
            }
            if (len & 0xC0) != 0 { return count }
            let next = idx + 1 + len
            guard next <= count else { return count }
            idx = next
        }
        return count
    }

    private static func decodeDNSName(_ buf: [UInt8], _ count: Int, _ start: Int) -> String? {
        guard start >= 0, start < count else { return nil }

        var labels: [String] = []
        var idx = start
        var jumped = false
        var guardCount = 0
        while idx < count && guardCount < 64 {
            guardCount += 1
            let len = Int(buf[idx])
            if len == 0 {
                return labels.isEmpty ? nil : labels.joined(separator: ".")
            }
            if (len & 0xC0) == 0xC0 {
                guard idx + 1 < count else { return nil }
                let pointer = ((len & 0x3F) << 8) | Int(buf[idx + 1])
                guard pointer < count, pointer != idx else { return nil }
                idx = pointer
                jumped = true
                continue
            }
            guard (len & 0xC0) == 0 else { return nil }
            let next = idx + 1 + len
            guard len > 0, next <= count else { return nil }
            let label = String(decoding: buf[(idx + 1)..<next], as: UTF8.self)
            labels.append(label)
            idx = next
            if jumped, idx >= count { return nil }
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
        return sanitize(entry.hostname, ip: ip)
    }

    private static func configureReceiveTimeout(sock: Int32, timeoutMs: Int) {
        var timeout = timeval(tv_sec: timeoutMs / 1000, tv_usec: Int32((timeoutMs % 1000) * 1000))
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    }

    private static func receiveUDP(sock: Int32, expectedIP: String, bufferSize: Int, maxPackets: Int = receiveLoopMaxPackets) -> (buffer: [UInt8], count: Int)? {
        guard bufferSize > 0, maxPackets > 0 else { return nil }

        var buf = [UInt8](repeating: 0, count: bufferSize)
        for _ in 0..<maxPackets {
            var from = sockaddr_in()
            var fromLen: socklen_t = socklen_t(MemoryLayout<sockaddr_in>.size)
            let received: Int = withUnsafeMutablePointer(to: &from) { fromPtr in
                fromPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    recvfrom(sock, &buf, buf.count, 0, sa, &fromLen)
                }
            }
            guard received > 0 else { return nil }
            let source = ipv4String(from.sin_addr)
            if source == expectedIP {
                return (buf, received)
            }
        }
        return nil
    }

    private static func ipv4String(_ addr: in_addr) -> String {
        var copy = addr
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        let result = inet_ntop(AF_INET, &copy, &buffer, socklen_t(INET_ADDRSTRLEN))
        guard result != nil else { return "" }
        return String(cString: buffer)
    }

    private static var ssdpDiscoveryPayload: String {
        """
        M-SEARCH * HTTP/1.1\r
        HOST: 239.255.255.250:1900\r
        MAN: \"ssdp:discover\"\r
        MX: 1\r
        ST: ssdp:all\r
        \r
        """
    }

    private static func parseHTTPHeaders(_ response: String) -> [String: String] {
        var headers: [String: String] = [:]
        for line in response.split(separator: "\n") {
            let row = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let sep = row.firstIndex(of: ":") else { continue }
            let key = row[..<sep].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = row[row.index(after: sep)...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else { continue }
            headers[key] = value
        }
        return headers
    }

    private static func bestSSDPHeaderName(_ raw: String, ip: String) -> String? {
        let candidates = raw
            .replacingOccurrences(of: "::", with: "/")
            .split(whereSeparator: { $0 == "/" || $0 == ";" || $0 == "(" || $0 == ")" || $0 == "," })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        for candidate in candidates {
            if let name = sanitize(candidate, ip: ip), candidate.rangeOfCharacter(from: .letters) != nil {
                return name
            }
        }
        return nil
    }

    private static func fetchUPnPDeviceDescriptionName(from location: String, expectedIP: String) -> String? {
        guard let url = URL(string: location), let host = url.host else { return nil }
        guard host == expectedIP else { return nil }

        let semaphore = DispatchSemaphore(value: 0)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = TimeInterval(ssdpLocationTimeoutMs) / 1000.0
        configuration.timeoutIntervalForResource = TimeInterval(ssdpLocationTimeoutMs) / 1000.0
        let session = URLSession(configuration: configuration)

        var result: String?
        let task = session.dataTask(with: url) { data, _, _ in
            defer { semaphore.signal() }
            guard let data, !data.isEmpty else { return }
            result = parseUPnPDeviceDescriptionName(data: data, ip: expectedIP)
        }
        task.resume()
        let waitResult = semaphore.wait(timeout: .now() + .milliseconds(ssdpLocationTimeoutMs + 100))
        if waitResult == .timedOut {
            task.cancel()
        }
        session.finishTasksAndInvalidate()
        return result
    }

    private static func parseUPnPDeviceDescriptionName(data: Data, ip: String) -> String? {
        guard let xml = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return nil }
        for tag in ["friendlyName", "modelName", "deviceType"] {
            if let value = firstXMLValue(named: tag, in: xml), let name = sanitize(value, ip: ip) {
                return name
            }
        }
        return nil
    }

    private static func firstXMLValue(named tag: String, in xml: String) -> String? {
        guard let start = xml.range(of: "<\(tag)", options: .regularExpression) else { return nil }
        guard let openEnd = xml[start.lowerBound...].firstIndex(of: ">") else { return nil }
        let contentStart = xml.index(after: openEnd)
        guard let close = xml.range(of: "</\(tag)>", range: contentStart..<xml.endIndex) else { return nil }
        let content = String(xml[contentStart..<close.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        return content.isEmpty ? nil : content
    }
}
