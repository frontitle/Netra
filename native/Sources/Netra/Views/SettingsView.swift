import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var prefs: AppPreferences
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                generalSection
                aboutSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(prefs.l10n(.settingsTitle))
        .task { await prefs.checkForUpdates(userInitiated: false) }
    }

    private var generalSection: some View {
        settingsCard(title: prefs.l10n(.settingsGeneral)) {
            LabeledContent(prefs.l10n(.settingsLanguage)) {
                Picker("", selection: $prefs.language) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.label).tag(lang)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
            }
            Divider().opacity(0.25)
            LabeledContent(prefs.l10n(.settingsAppearance)) {
                Picker("", selection: $prefs.appearance) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(prefs.appearanceLabel(mode)).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
            }
            Divider().opacity(0.25)
            LabeledContent(prefs.l10n(.settingsAccent)) {
                HStack(spacing: 10) {
                    ForEach(AccentPreset.allCases) { preset in
                        accentSwatch(preset)
                    }
                }
            }
        }
    }

    private var aboutSection: some View {
        settingsCard(title: prefs.l10n(.aboutTitle)) {
            HStack(spacing: 12) {
                NetraLogo(size: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(prefs.l10n(.appFullName))
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(prefs.l10n(.appTagline))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                LabeledContent(prefs.l10n(.version), value: AppVersion.display)
                if AppVersion.isBeta {
                    Text("BETA")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(theme.accent.opacity(0.2), in: Capsule())
                        .foregroundStyle(theme.accent)
                }
                if prefs.updateAvailable {
                    updateBadge
                }
            }
            LabeledContent(prefs.l10n(.buildNumber), value: AppVersion.build)
            LabeledContent(prefs.l10n(.aboutRuntime), value: "Swift Native")
            if prefs.updateAvailable, let ver = prefs.latestReleaseVersion {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.red)
                    Text(String(format: prefs.l10n(.updateAvailableFormat), ver))
                        .foregroundStyle(.red)
                        .font(.callout.weight(.medium))
                }
            }
            if !prefs.lastUpdateCheckMessage.isEmpty {
                Text(prefs.lastUpdateCheckMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Button(prefs.isCheckingUpdate ? prefs.l10n(.checkingUpdates) : prefs.l10n(.checkUpdates)) {
                    Task { await prefs.checkForUpdates(userInitiated: true) }
                }
                .buttonStyle(FuturisticButtonStyle(prominent: true))
                .disabled(prefs.isCheckingUpdate)
                if prefs.updateAvailable {
                    Button(prefs.l10n(.openReleases)) { openReleases() }
                        .buttonStyle(FuturisticButtonStyle())
                }
                Button(prefs.l10n(.viewOnGitHub)) {
                    NSWorkspace.shared.open(AppConfig.repositoryURL)
                }
                .buttonStyle(FuturisticButtonStyle())
            }
            .padding(.top, 4)
            Text(prefs.l10n(.aboutDescription))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(prefs.l10n(.brandStory))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(prefs.l10n(.copyright))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var updateBadge: some View {
        Text(prefs.l10n(.newVersionBadge))
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.red.opacity(0.2), in: Capsule())
            .overlay(Capsule().stroke(Color.red.opacity(0.6), lineWidth: 1))
            .foregroundStyle(.red)
    }

    private func accentSwatch(_ preset: AccentPreset) -> some View {
        let selected = prefs.accent == preset
        return Button {
            prefs.accent = preset
        } label: {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [preset.theme.accent, preset.theme.accentDim],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 28, height: 28)
                .overlay {
                    if selected {
                        Circle().stroke(theme.accent, lineWidth: 2).padding(-3)
                        Image(systemName: "checkmark")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                    }
                }
        }
        .buttonStyle(.plain)
        .help(preset.label(language: prefs.language))
    }

    private func settingsCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)
                .foregroundStyle(theme.accent)
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(16)
            .frame(maxWidth: 560, alignment: .leading)
            .background(AppTheme.glassPanel(cornerRadius: 14, theme: theme))
        }
    }

    private func openReleases() {
        let url = prefs.latestReleaseURL ?? AppConfig.releasesPageURL
        NSWorkspace.shared.open(url)
    }
}
