import Darwin
import Foundation
import Network

enum PortScanner {
    static func scanTCP(ip: IPv4Address, ports: [UInt16]) -> [OpenPort] {
        var open: [OpenPort] = []
        let batch = 10
        var idx = 0
        while idx < ports.count {
            if ScanCancellation.shared.isCancelled { break }
            let chunk = Array(ports[idx..<min(idx + batch, ports.count)])
            let group = DispatchGroup()
            let lock = NSLock()
            for port in chunk {
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    defer { group.leave() }
                    let ok = tcpProbe(ip: ip, port: port, timeoutMs: 100)
                    if ok {
                        let entry = OpenPort(port: Int(port), service: serviceName(port), hint: portHint(port))
                        lock.lock()
                        open.append(entry)
                        lock.unlock()
                    }
                }
            }
            group.wait()
            idx += batch
        }
        return open.sorted { $0.port < $1.port }
    }

    static func scanUDP(ip: IPv4Address, ports: [UInt16]) -> [OpenPort] {
        var results: [OpenPort] = []
        for port in ports {
            if ScanCancellation.shared.isCancelled { break }
            if udpProbe(ip: ip, port: port) {
                results.append(OpenPort(port: Int(port), service: udpServiceName(port), hint: "UDP 响应"))
            }
        }
        return results
    }

    static func discoverUDPResponders(ips: [IPv4Address], ports: [UInt16]) -> Set<IPv4Address> {
        var responders = Set<IPv4Address>()
        let lock = NSLock()
        let batch = 24
        var idx = 0
        while idx < ips.count {
            if ScanCancellation.shared.isCancelled { break }
            let chunk = Array(ips[idx..<min(idx + batch, ips.count)])
            let group = DispatchGroup()
            for ip in chunk {
                group.enter()
                DispatchQueue.global(qos: .utility).async {
                    defer { group.leave() }
                    for port in ports {
                        if ScanCancellation.shared.isCancelled { return }
                        if udpProbe(ip: ip, port: port, timeoutMs: 140) {
                            lock.lock()
                            responders.insert(ip)
                            lock.unlock()
                            return
                        }
                    }
                }
            }
            group.wait()
            idx += batch
        }
        return responders
    }

    private static func tcpProbe(ip: IPv4Address, port: UInt16, timeoutMs: Int) -> Bool {
        let host = NWEndpoint.Host(IPv4Helpers.ipv4String(ip))
        let conn = NWConnection(host: host, port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        let sem = DispatchSemaphore(value: 0)
        var success = false
        conn.stateUpdateHandler = { state in
            switch state {
            case .ready:
                success = true
                conn.cancel()
                sem.signal()
            case .failed:
                conn.cancel()
                sem.signal()
            default: break
            }
        }
        conn.start(queue: .global())
        _ = sem.wait(timeout: .now() + .milliseconds(timeoutMs))
        conn.cancel()
        return success
    }

    private static func udpProbe(ip: IPv4Address, port: UInt16, timeoutMs: Int = 200) -> Bool {
        let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard sock >= 0 else { return false }
        defer { close(sock) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        let ipStr = IPv4Helpers.ipv4String(ip)
        inet_pton(AF_INET, ipStr, &addr.sin_addr)
        let payload = udpPayload(for: port)
        let sent = payload.withUnsafeBytes { ptr in
            withUnsafePointer(to: &addr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    sendto(sock, ptr.baseAddress, ptr.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent >= 0 else { return false }
        var timeout = timeval(tv_sec: timeoutMs / 1000, tv_usec: Int32((timeoutMs % 1000) * 1000))
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var buf = [UInt8](repeating: 0, count: 512)
        var from = sockaddr_in()
        var fromLen: socklen_t = socklen_t(MemoryLayout<sockaddr_in>.size)
        let received = withUnsafeMutablePointer(to: &from) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                recvfrom(sock, &buf, buf.count, 0, sa, &fromLen)
            }
        }
        return received > 0
    }

    private static func udpPayload(for port: UInt16) -> [UInt8] {
        switch port {
        case 53:
            return [0x12, 0x34, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                    0x00, 0x00, 0x01, 0x00, 0x01]
        case 123:
            return [0x1b] + Array(repeating: 0, count: 47)
        case 137:
            return buildNBNSNodeStatusQuery(txid: UInt16.random(in: 0...UInt16.max))
        case 1900:
            return Array("""
            M-SEARCH * HTTP/1.1\r
            HOST: 239.255.255.250:1900\r
            MAN: "ssdp:discover"\r
            MX: 1\r
            ST: ssdp:all\r
            \r
            """.utf8)
        case 5353:
            var out: [UInt8] = [0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
            for label in "_services._dns-sd._udp.local".split(separator: ".") {
                out.append(UInt8(label.count))
                out.append(contentsOf: label.utf8)
            }
            out.append(contentsOf: [0x00, 0x00, 0x0c, 0x00, 0x01])
            return out
        default:
            return [0]
        }
    }

    private static func buildNBNSNodeStatusQuery(txid: UInt16) -> [UInt8] {
        var out: [UInt8] = []
        out.append(UInt8(txid >> 8)); out.append(UInt8(txid & 0xff))
        out.append(0x00); out.append(0x00)
        out.append(0x00); out.append(0x01)
        out.append(0x00); out.append(0x00)
        out.append(0x00); out.append(0x00)
        out.append(0x00); out.append(0x00)
        out.append(0x20)
        for b in [0x2a] + Array(repeating: UInt8(0x20), count: 15) {
            out.append(0x41 + ((b >> 4) & 0x0f))
            out.append(0x41 + (b & 0x0f))
        }
        out.append(0x00)
        out.append(0x00); out.append(0x21)
        out.append(0x00); out.append(0x01)
        return out
    }

    static func serviceName(_ port: UInt16) -> String {
        switch port {
        case 22: return "SSH"
        case 53: return "DNS"
        case 80: return "HTTP"
        case 443: return "HTTPS"
        case 445: return "SMB"
        case 548: return "AFP"
        case 631: return "IPP"
        case 502: return "Modbus"
        case 5900: return "VNC"
        case 62078: return "iOS Sync"
        default: return "TCP/\(port)"
        }
    }

    static func udpServiceName(_ port: UInt16) -> String {
        switch port {
        case 53: return "DNS/UDP"
        case 123: return "NTP/UDP"
        case 137: return "NetBIOS/UDP"
        case 1900: return "SSDP/UDP"
        case 5353: return "mDNS/UDP"
        default: return "UDP/\(port)"
        }
    }

    static func portHint(_ port: UInt16) -> String {
        switch port {
        case 80, 443, 8080: return "Web 管理或服务"
        case 22: return "SSH 远程管理"
        case 445: return "Windows 文件共享"
        default: return "开放端口"
        }
    }
}
