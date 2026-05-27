import AppKit
import Foundation

enum UpdateInstaller {
    enum InstallError: LocalizedError {
        case missingAsset
        case invalidBundle
        case unzipFailed
        case appNotFound
        case relaunchFailed

        var errorDescription: String? {
            switch self {
            case .missingAsset: return "Release 中没有可安装的 zip 包。"
            case .invalidBundle: return "当前应用不是 .app bundle，无法自动覆盖升级。"
            case .unzipFailed: return "更新包解压失败。"
            case .appNotFound: return "更新包中没有找到 Netra.app。"
            case .relaunchFailed: return "无法启动更新替换流程。"
            }
        }
    }

    static func installAndRelaunch(assetURL: URL) async throws {
        let currentApp = Bundle.main.bundleURL
        guard currentApp.pathExtension == "app" else { throw InstallError.invalidBundle }

        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("netra-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        let zipURL = workDir.appendingPathComponent("Netra-update.zip")
        let extractURL = workDir.appendingPathComponent("extract", isDirectory: true)
        try FileManager.default.createDirectory(at: extractURL, withIntermediateDirectories: true)

        let (downloaded, _) = try await URLSession.shared.download(from: assetURL)
        if FileManager.default.fileExists(atPath: zipURL.path) {
            try FileManager.default.removeItem(at: zipURL)
        }
        try FileManager.default.moveItem(at: downloaded, to: zipURL)

        guard run("/usr/bin/ditto", ["-x", "-k", zipURL.path, extractURL.path]) else {
            throw InstallError.unzipFailed
        }
        guard let newApp = findApp(in: extractURL) else { throw InstallError.appNotFound }

        let scriptURL = workDir.appendingPathComponent("install.sh")
        let script = """
        #!/bin/zsh
        set -e
        sleep 1
        /bin/rm -rf "\(currentApp.path)"
        /usr/bin/ditto "\(newApp.path)" "\(currentApp.path)"
        /usr/bin/xattr -cr "\(currentApp.path)" 2>/dev/null || true
        /usr/bin/open "\(currentApp.path)"
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [scriptURL.path]
        do {
            try process.run()
        } catch {
            throw InstallError.relaunchFailed
        }
        await MainActor.run { NSApp.terminate(nil) }
    }

    private static func findApp(in root: URL) -> URL? {
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        while let url = enumerator?.nextObject() as? URL {
            if url.lastPathComponent == "Netra.app" { return url }
        }
        return nil
    }

    private static func run(_ launchPath: String, _ args: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
