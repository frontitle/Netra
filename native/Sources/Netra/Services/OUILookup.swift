import Foundation

extension Notification.Name {
    static let ouiDatabaseDidLoad = Notification.Name("netra.ouiDatabaseDidLoad")
}

/// 厂商识别 — 基于 [OUI-Master-Database](https://github.com/Ringmast4r/OUI-Master-Database)（后台异步加载）。
enum OUILookup {
    private final class Store: @unchecked Sendable {
        private let lock = NSLock()
        var prefixes: [(String, String)] = []
        var isReady = false
        var loadStarted = false

        func beginLoadIfNeeded() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if loadStarted { return false }
            loadStarted = true
            return true
        }

        func install(_ table: [(String, String)]) {
            lock.lock()
            prefixes = table
            isReady = true
            lock.unlock()
        }

        func snapshot() -> (ready: Bool, list: [(String, String)]) {
            lock.lock()
            defer { lock.unlock() }
            return (isReady, prefixes)
        }
    }

    private static let store = Store()

    /// 应用启动时调用；加载在后台线程完成，不阻塞扫描。
    static func startLoading() {
        guard store.beginLoadIfNeeded() else { return }
        Task.detached(priority: .utility) {
            let loaded = buildPrefixTable()
            store.install(loaded)
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .ouiDatabaseDidLoad, object: nil)
            }
        }
    }

    static var ready: Bool {
        store.snapshot().ready
    }

    static func vendor(for mac: String) -> String {
        let normalized = IPv4Helpers.normalizeMAC(mac).replacingOccurrences(of: ":", with: "").uppercased()
        guard normalized.count >= 6, normalized != "未知" else { return unknownLabel() }

        let (ready, list) = store.snapshot()

        guard ready, !list.isEmpty else { return unknownLabel() }

        for length in [9, 7, 6] {
            guard normalized.count >= length else { continue }
            let prefix = String(normalized.prefix(length))
            if let name = list.first(where: { $0.0 == prefix })?.1 { return name }
        }
        return unknownLabel()
    }

    private static func buildPrefixTable() -> [(String, String)] {
        var map: [String: String] = [:]
        loadResource("master_oui", into: &map)
        loadResource("kismet_manuf", into: &map)
        return map.map { ($0.key, $0.value) }.sorted { $0.0.count > $1.0.count }
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
        "Unknown vendor"
    }
}
