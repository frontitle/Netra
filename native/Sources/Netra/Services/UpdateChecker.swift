import Foundation

struct ReleaseInfo: Equatable {
    var version: String
    var url: URL
}

enum UpdateChecker {
    private struct GitHubRelease: Decodable {
        var tag_name: String
        var html_url: String
    }

    static func fetchLatestRelease() async -> ReleaseInfo? {
        var request = URLRequest(url: AppConfig.latestReleaseAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Netra/\(AppVersion.short)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 12
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            guard let url = URL(string: release.html_url) else { return nil }
            let version = release.tag_name
                .trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "^v", with: "", options: .regularExpression)
            return ReleaseInfo(version: version, url: url)
        } catch {
            return nil
        }
    }
}
