import Foundation

extension Notification.Name {
    static let ouiDatabaseDidLoad = Notification.Name("netra.ouiDatabaseDidLoad")
}

/// 厂商识别 — OUI-Master-Database；先加载 master（快速可用），再后台合并 kismet。
enum OUILookup {
    private final class Store: @unchecked Sendable {
        private let lock = NSLock()
        var prefixMap: [String: String] = [:]
        var isReady = false
        var loadStarted = false

        func beginLoadIfNeeded() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if loadStarted { return false }
            loadStarted = true
            return true
        }

        func install(_ table: [String: String], merge: Bool) {
            lock.lock()
            if merge {
                for (k, v) in table where prefixMap[k] == nil {
                    prefixMap[k] = v
                }
            } else {
                prefixMap = table
            }
            isReady = true
            lock.unlock()
        }

        func snapshot() -> (ready: Bool, map: [String: String]) {
            lock.lock()
            defer { lock.unlock() }
            return (isReady, prefixMap)
        }
    }

    private static let store = Store()

    static func startLoading() {
        guard store.beginLoadIfNeeded() else { return }
        Task.detached(priority: .utility) {
            var master: [String: String] = [:]
            loadResource("master_oui", into: &master)
            store.install(master, merge: false)
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .ouiDatabaseDidLoad, object: nil)
            }
            var kismet: [String: String] = [:]
            loadResource("kismet_manuf", into: &kismet)
            store.install(kismet, merge: true)
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .ouiDatabaseDidLoad, object: nil)
            }
        }
    }

    static var ready: Bool {
        store.snapshot().ready
    }

    static func vendor(for mac: String, hostname: String = "", ports: [OpenPort] = []) -> String {
        let normalized = macKey(mac)
        guard normalized.count >= 6, normalized != "未知" else {
            return inferVendorFallback(mac: mac, hostname: hostname, ports: ports) ?? unknownLabel()
        }

        let (ready, map) = store.snapshot()
        if ready, !map.isEmpty {
            for length in [9, 7, 6] {
                guard normalized.count >= length else { continue }
                let key = String(normalized.prefix(length))
                if let name = map[key] {
                    let lower = name.lowercased()
                    if lower != "private", !lower.hasPrefix("randomized") {
                        return name
                    }
                }
            }
        }

        return inferVendorFallback(mac: mac, hostname: hostname, ports: ports) ?? unknownLabel()
    }

    /// Apple 等设备常用随机/私有 MAC，需结合主机名与端口回退。
    private static func inferVendorFallback(mac: String, hostname: String, ports: [OpenPort]) -> String? {
        let h = hostname.lowercased()
        let portSet = Set(ports.map(\.port))
        if isAppleHostname(h) || isApplePortSignature(portSet) {
            return "Apple, Inc."
        }
        if h.contains("iphone") || h.contains("ipad") || h.contains("macbook") || h.contains("imac")
            || h.contains("appletv") || h.contains("airpods") || h.contains("homepod") {
            return "Apple, Inc."
        }
        // LAA（随机/私有 MAC）不能用「单一端口」下结论，避免把通用服务误判成 Apple。
        if isLocallyAdministeredMAC(mac) {
            let appleish = applePortEvidence(portSet)
            if appleish >= 2 { return "Apple, Inc." }
        }
        return nil
    }

    private static func isAppleHostname(_ h: String) -> Bool {
        h.contains("apple") || h.contains("iphone") || h.contains("ipad") || h.contains("macbook")
            || h.contains("imac") || h.contains("appletv") || h.hasSuffix(".local") && (h.contains("mac") || h.contains("iphone"))
    }

    private static func isApplePortSignature(_ ports: Set<Int>) -> Bool {
        // 端口只是“证据”，不要包含过于泛化的 5000（很多设备/服务都会用）。
        // 更偏 Apple 生态的组合：mDNS + AirPlay / iOS sync / AFP / VNC 等。
        let evidence = applePortEvidence(ports)
        return evidence >= 2
    }

    private static func isLocallyAdministeredMAC(_ mac: String) -> Bool {
        let norm = IPv4Helpers.normalizeMAC(mac)
        guard let first = norm.split(separator: ":").first, let byte = UInt8(first, radix: 16) else { return false }
        return (byte & 0x02) != 0
    }

    private static func applePortEvidence(_ ports: Set<Int>) -> Int {
        var score = 0
        if ports.contains(5353) { score += 1 } // mDNS
        if ports.contains(7000) { score += 1 } // AirPlay
        if ports.contains(62078) { score += 1 } // iOS sync/lockdownd
        if ports.contains(548) { score += 1 } // AFP
        if ports.contains(5900) { score += 1 } // VNC（macOS 共享屏幕）
        // 注意：不把 5000 算入 Apple 证据（过于泛化）
        return score
    }

    private static func macKey(_ mac: String) -> String {
        IPv4Helpers.normalizeMAC(mac).replacingOccurrences(of: ":", with: "").uppercased()
    }

    private static func loadResource(_ name: String, into map: inout [String: String]) {
        guard let url = Bundle.module.url(forResource: name, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        for line in text.split(separator: "\n") {
            let row = String(line).trimmingCharacters(in: .whitespaces)
            if row.isEmpty || row.hasPrefix("#") { continue }
            let parts: [String]
            if row.contains("\t") {
                parts = row.split(separator: "\t", maxSplits: 1).map(String.init)
            } else if row.contains(",") {
                parts = row.split(separator: ",", maxSplits: 1).map(String.init)
            } else if row.contains("  ") {
                parts = row.split(separator: "  ", maxSplits: 1).map(String.init)
            } else { continue }
            guard parts.count >= 2 else { continue }
            let key = normalizeOUIKey(parts[0])
            guard !key.isEmpty else { continue }
            let vendor = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if map[key] == nil { map[key] = vendor }
        }
    }

    private static func normalizeOUIKey(_ raw: String) -> String {
        raw.uppercased()
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ".", with: "")
            .filter { "0123456789ABCDEF".contains($0) }
    }

    private static func unknownLabel() -> String {
        "-"
    }
}
