import Combine
import Foundation

/// 用户自定义主机名备注（按 IP 持久化）。
final class DeviceNotesStore: ObservableObject {
    static let shared = DeviceNotesStore()

    @Published private(set) var revision = 0
    private var notes: [String: String] = [:]
    private let fileURL: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Netra", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("device-notes.json")
        load()
    }

    func alias(for ip: String) -> String? {
        let key = ip.trimmingCharacters(in: .whitespaces)
        guard let v = notes[key], !v.isEmpty else { return nil }
        return v
    }

    func setAlias(_ alias: String, for ip: String) {
        let key = ip.trimmingCharacters(in: .whitespaces)
        let trimmed = alias.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            notes.removeValue(forKey: key)
        } else {
            notes[key] = trimmed
        }
        save()
        revision += 1
    }

    func displayName(discovered: String, ip: String) -> String {
        alias(for: ip) ?? discovered
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else { return }
        notes = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(notes) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
