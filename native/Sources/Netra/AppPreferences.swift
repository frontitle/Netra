import Combine
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case zhHans = "zh-Hans"
    case en = "en"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .zhHans: return "简体中文"
        case .en: return "English"
        }
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable, Codable {
    case system, light, dark

    var id: String { rawValue }
}

enum AccentPreset: String, CaseIterable, Identifiable, Codable {
    case cyan, violet, green, orange, rose

    var id: String { rawValue }

    var theme: ThemeColors {
        switch self {
        case .cyan:
            return ThemeColors(
                accent: Color(red: 0.2, green: 0.78, blue: 1.0),
                accentDim: Color(red: 0.1, green: 0.45, blue: 0.85),
                glow: Color(red: 0.35, green: 0.9, blue: 1.0).opacity(0.45)
            )
        case .violet:
            return ThemeColors(
                accent: Color(red: 0.62, green: 0.45, blue: 1.0),
                accentDim: Color(red: 0.42, green: 0.28, blue: 0.82),
                glow: Color(red: 0.7, green: 0.5, blue: 1.0).opacity(0.4)
            )
        case .green:
            return ThemeColors(
                accent: Color(red: 0.25, green: 0.88, blue: 0.62),
                accentDim: Color(red: 0.12, green: 0.58, blue: 0.42),
                glow: Color(red: 0.35, green: 0.95, blue: 0.7).opacity(0.4)
            )
        case .orange:
            return ThemeColors(
                accent: Color(red: 1.0, green: 0.58, blue: 0.22),
                accentDim: Color(red: 0.82, green: 0.38, blue: 0.12),
                glow: Color(red: 1.0, green: 0.7, blue: 0.35).opacity(0.42)
            )
        case .rose:
            return ThemeColors(
                accent: Color(red: 1.0, green: 0.42, blue: 0.58),
                accentDim: Color(red: 0.78, green: 0.22, blue: 0.42),
                glow: Color(red: 1.0, green: 0.55, blue: 0.65).opacity(0.4)
            )
        }
    }

    func label(language: AppLanguage) -> String {
        switch self {
        case .cyan: return L10n.string(.accentCyan, language: language)
        case .violet: return L10n.string(.accentViolet, language: language)
        case .green: return L10n.string(.accentGreen, language: language)
        case .orange: return L10n.string(.accentOrange, language: language)
        case .rose: return L10n.string(.accentRose, language: language)
        }
    }
}

struct ThemeColors {
    var accent: Color
    var accentDim: Color
    var glow: Color

    static let cyan = AccentPreset.cyan.theme
}

private struct ThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue = ThemeColors.cyan
}

extension EnvironmentValues {
    var theme: ThemeColors {
        get { self[ThemeEnvironmentKey.self] }
        set { self[ThemeEnvironmentKey.self] = newValue }
    }
}

@MainActor
final class AppPreferences: ObservableObject {
    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Keys.language) }
    }
    @Published var appearance: AppearanceMode {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: Keys.appearance) }
    }
    @Published var accent: AccentPreset {
        didSet { UserDefaults.standard.set(accent.rawValue, forKey: Keys.accent) }
    }

    @Published var updateAvailable = false
    @Published var latestReleaseVersion: String?
    @Published var latestReleaseURL: URL?
    @Published var isCheckingUpdate = false
    @Published var lastUpdateCheckMessage = ""

    var themeColors: ThemeColors { accent.theme }

    var preferredColorScheme: ColorScheme? {
        switch appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    func l10n(_ key: L10nKey) -> String {
        L10n.string(key, language: language)
    }

    func appearanceLabel(_ mode: AppearanceMode) -> String {
        switch mode {
        case .system: return l10n(.appearanceSystem)
        case .light: return l10n(.appearanceLight)
        case .dark: return l10n(.appearanceDark)
        }
    }

    init() {
        let langRaw = UserDefaults.standard.string(forKey: Keys.language)
            ?? UserDefaults.standard.string(forKey: LegacyKeys.language)
        language = AppLanguage(rawValue: langRaw ?? "") ?? Self.defaultLanguage()
        let appearanceRaw = UserDefaults.standard.string(forKey: Keys.appearance)
            ?? UserDefaults.standard.string(forKey: LegacyKeys.appearance)
        appearance = AppearanceMode(rawValue: appearanceRaw ?? "") ?? .system
        let accentRaw = UserDefaults.standard.string(forKey: Keys.accent)
            ?? UserDefaults.standard.string(forKey: LegacyKeys.accent)
        accent = AccentPreset(rawValue: accentRaw ?? "") ?? .cyan
    }

    func checkForUpdates(userInitiated: Bool = false) async {
        isCheckingUpdate = true
        defer { isCheckingUpdate = false }
        guard let release = await UpdateChecker.fetchLatestRelease() else {
            if userInitiated {
                lastUpdateCheckMessage = l10n(.updateCheckFailed)
            }
            return
        }
        latestReleaseVersion = release.version
        latestReleaseURL = release.url
        let newer = AppVersion.isRemoteNewer(remote: release.version, than: AppVersion.short)
        updateAvailable = newer
        if userInitiated {
            lastUpdateCheckMessage = newer
                ? String(format: l10n(.updateAvailableFormat), release.version)
                : l10n(.upToDate)
        }
    }

    private enum Keys {
        static let language = "netra.language"
        static let appearance = "netra.appearance"
        static let accent = "netra.accent"
    }

    private enum LegacyKeys {
        static let language = "ipfinder.language"
        static let appearance = "ipfinder.appearance"
        static let accent = "ipfinder.accent"
    }

    /// 默认英文；仅当系统首选语言为中文时显示中文 UI。
    private static func defaultLanguage() -> AppLanguage {
        let preferred = Locale.preferredLanguages.first ?? "en"
        let code = preferred.lowercased()
        if code.hasPrefix("zh") { return .zhHans }
        return .en
    }
}
