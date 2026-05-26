import Foundation

/// 官方开源仓库 — 应用内「检查更新」以此仓库 [Releases](https://github.com/frontitle/Netra/releases) 为准。
enum AppConfig {
    static let githubOwner = "frontitle"
    static let githubRepo = "Netra"

    /// 预发布通道后缀；GitHub Release 标签建议：`v0.1.2-beta`
    static let releaseChannelSuffix = "-beta"

    static var repositoryURL: URL {
        URL(string: "https://github.com/\(githubOwner)/\(githubRepo)")!
    }

    static var releasesPageURL: URL {
        URL(string: "https://github.com/\(githubOwner)/\(githubRepo)/releases")!
    }
}
