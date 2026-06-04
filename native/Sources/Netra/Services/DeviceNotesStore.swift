import Combine
import Foundation

struct DeviceNoteRecord: Codable, Equatable {
    var alias: String?
    var role: String?
    var os: String?

    init(alias: String? = nil, role: String? = nil, os: String? = nil) {
        self.alias = alias
        self.role = role
        self.os = os
    }

    var isEmpty: Bool {
        [alias, role, os].allSatisfy { ($0 ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

/// 用户自定义设备标注。优先按 MAC 持久化，避免 DHCP 重新分配 IP 后丢失。
final class DeviceNotesStore: ObservableObject {
    static let shared = DeviceNotesStore()

    @Published private(set) var revision = 0
    private var records: [String: DeviceNoteRecord] = [:]
    private let fileURL: URL

    private init() {
        fileURL = AppStorage.supportDirectory().appendingPathComponent("device-notes.json")
        load()
    }

    func alias(for ip: String) -> String? {
        value(\.alias, forKey: ipKey(ip))
    }

    func alias(for device: LanDevice) -> String? {
        value(\.alias, forKey: key(for: device)) ?? alias(for: device.ip)
    }

    func setAlias(_ alias: String, for ip: String) {
        update(key: ipKey(ip)) { record in
            record.alias = clean(alias)
        }
    }

    func setAlias(_ alias: String, for device: LanDevice) {
        update(key: key(for: device)) { record in
            record.alias = clean(alias)
        }
    }

    func roleOverride(for device: LanDevice) -> String? {
        value(\.role, forKey: key(for: device)) ?? value(\.role, forKey: ipKey(device.ip))
    }

    func osOverride(for device: LanDevice) -> String? {
        value(\.os, forKey: key(for: device)) ?? value(\.os, forKey: ipKey(device.ip))
    }

    func setRoleOverride(_ role: String, for device: LanDevice) {
        update(key: key(for: device)) { record in
            record.role = clean(role)
        }
    }

    func setOSOverride(_ os: String, for device: LanDevice) {
        update(key: key(for: device)) { record in
            record.os = clean(os)
        }
    }

    func displayName(discovered: String, ip: String) -> String {
        alias(for: ip) ?? discovered
    }

    func displayName(discovered: String, device: LanDevice) -> String {
        alias(for: device) ?? discovered
    }

    func applyOverrides(to device: LanDevice) -> LanDevice {
        var next = device
        if let role = roleOverride(for: device) { next.role = role }
        if let os = osOverride(for: device) { next.os = os }
        return next
    }

    private func key(for device: LanDevice) -> String {
        let mac = IPv4Helpers.normalizeMAC(device.mac)
        if isStableMAC(mac) { return "mac:\(mac)" }
        return ipKey(device.ip)
    }

    private func ipKey(_ ip: String) -> String {
        "ip:\(ip.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    private func value(_ path: KeyPath<DeviceNoteRecord, String?>, forKey key: String) -> String? {
        guard let raw = records[key]?[keyPath: path]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        return raw
    }

    private func update(key: String, mutate: (inout DeviceNoteRecord) -> Void) {
        var record = records[key] ?? DeviceNoteRecord()
        mutate(&record)
        if record.isEmpty {
            records.removeValue(forKey: key)
        } else {
            records[key] = record
        }
        saveAndNotify()
    }

    private func clean(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let decoded = try? JSONDecoder().decode([String: DeviceNoteRecord].self, from: data) {
            records = decoded
            return
        }
        if let legacy = try? JSONDecoder().decode([String: String].self, from: data) {
            records = legacy.reduce(into: [:]) { out, item in
                let alias = item.value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !alias.isEmpty else { return }
                out[ipKey(item.key)] = DeviceNoteRecord(alias: alias, role: nil, os: nil)
            }
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func saveAndNotify() {
        save()
        revision += 1
    }

    private func isStableMAC(_ mac: String) -> Bool {
        let m = mac.trimmingCharacters(in: .whitespacesAndNewlines)
        if m.isEmpty || m == "未知" || m.contains("扫描中") || m.contains("识别中") { return false }
        if IPv4Helpers.isIgnoredMAC(m) { return false }
        return m.split(separator: ":").count == 6
    }
}
