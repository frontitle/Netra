import Foundation

enum AppStorage {
    static func supportDirectory() -> URL {
        let candidates = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let base = candidates.first ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("Netra", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        } catch {
            let fallback = FileManager.default.temporaryDirectory
                .appendingPathComponent("Netra", isDirectory: true)
            try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
            return fallback
        }
    }
}
