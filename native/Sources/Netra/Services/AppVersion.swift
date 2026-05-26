import Foundation

enum AppVersion {
    static var short: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.1-beta"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    /// 用于界面展示，如 `0.1.1-beta · build 1`
    static var display: String {
        "\(short) · build \(build)"
    }

    static var isBeta: Bool {
        short.lowercased().contains("beta")
    }

    /// 与 GitHub Release 标签比较（去掉 `v` 与 `-beta` 后按 0.1.x 数字段比较）。
    static func isRemoteNewer(remote: String, than local: String) -> Bool {
        compare(remote, local) == .orderedDescending
    }

    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let a = parse(lhs)
        let b = parse(rhs)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x < y { return .orderedAscending }
            if x > y { return .orderedDescending }
        }
        return .orderedSame
    }

    private static func parse(_ raw: String) -> [Int] {
        raw.trimmingCharacters(in: .whitespaces)
            .lowercased()
            .replacingOccurrences(of: "^v", with: "", options: .regularExpression)
            .replacingOccurrences(of: "-beta", with: "", options: .caseInsensitive)
            .split(whereSeparator: { !"0123456789".contains($0) })
            .compactMap { Int($0) }
    }
}
