import Foundation

struct ReleaseInfo: Equatable {
    var version: String
    var url: URL
}

enum UpdateChecker {
    private struct GitHubRelease: Decodable {
        var tag_name: String
        var html_url: String
        var draft: Bool?
        var prerelease: Bool?
    }

    /// 取仓库最新已发布 Release（含 prerelease/beta；GitHub `/releases/latest` 会忽略 prerelease）。
    static func fetchLatestRelease() async -> ReleaseInfo? {
        var components = URLComponents(url: AppConfig.repositoryURL, resolvingAgainstBaseURL: false)!
        components.path += "/releases"
        components.queryItems = [URLQueryItem(name: "per_page", value: "8")]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Netra/\(AppVersion.short)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 12
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
            let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
            guard let release = releases.first(where: { $0.draft != true }) else { return nil }
            guard let page = URL(string: release.html_url) else { return nil }
            let version = release.tag_name
                .trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "^v", with: "", options: .regularExpression)
            return ReleaseInfo(version: version, url: page)
        } catch {
            return nil
        }
    }
}
