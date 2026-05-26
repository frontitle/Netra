import Foundation

enum OUILookup {
    private static var database: [String: String] = [:]
    private static var loaded = false

    /// 在后台线程预加载 OUI，避免扫描首批设备时一次性解析大文件。
    static func warmup() {
        loadIfNeeded()
    }

    static func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let url = Bundle.module.url(forResource: "master_oui", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        for line in text.split(separator: "\n") {
            let row = String(line)
            if row.hasPrefix("#") || !row.contains("\t") { continue }
            let parts = row.split(separator: "\t", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let oui = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if oui.count == 6 {
                database[oui] = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    static func vendor(for mac: String) -> String {
        loadIfNeeded()
        let normalized = IPv4Helpers.normalizeMAC(mac).replacingOccurrences(of: ":", with: "")
        guard normalized.count >= 6 else { return "未知厂商" }
        let prefix = String(normalized.prefix(6)).uppercased()
        return database[prefix] ?? "未知厂商"
    }
}
