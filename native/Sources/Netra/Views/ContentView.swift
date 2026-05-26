import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var prefs: AppPreferences
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            AppTheme.background(theme: theme, dark: colorScheme == .dark)
            NavigationSplitView(columnVisibility: .constant(.all)) {
                sidebar
            } content: {
                mainPane
            } detail: {
                DeviceInspectorView(device: app.selectedDevice)
                    .frame(minWidth: 300, idealWidth: 340)
            }
        }
        .environment(\.theme, prefs.themeColors)
        .preferredColorScheme(prefs.preferredColorScheme)
    }

    private var sidebar: some View {
        List(selection: $app.section) {
            Section(prefs.l10n(.sectionDiscovery)) {
                navRow(prefs.l10n(.navLanDevices), "dot.radiowaves.left.and.right", .radar)
                navRow(prefs.l10n(.navWifi), "wifi", .wifi)
            }
            Section(prefs.l10n(.sectionDiagnostics)) {
                navRow(prefs.l10n(.navQuality), "waveform.path.ecg", .quality)
                navRow(prefs.l10n(.navHistory), "clock.arrow.circlepath", .history)
            }
            Section {
                navRow(prefs.l10n(.navSettings), "gearshape", .settings, showUpdateBadge: prefs.updateAvailable)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .top) {
            HStack(spacing: 10) {
                NetraLogo(size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Netra")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                    Text(prefs.l10n(.appTagline))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
    }

    private func navRow(_ title: String, _ icon: String, _ section: AppSection, showUpdateBadge: Bool = false) -> some View {
        HStack(spacing: 6) {
            Label(title, systemImage: icon)
            if showUpdateBadge {
                Circle()
                    .fill(Color.red)
                    .frame(width: 7, height: 7)
                    .accessibilityLabel(prefs.l10n(.newVersionBadge))
            }
        }
        .tag(section)
        .foregroundStyle(app.section == section ? theme.accent : .primary)
    }

    @ViewBuilder
    private var mainPane: some View {
        Group {
            switch app.section {
            case .radar: RadarView()
            case .quality: QualityView()
            case .wifi: WifiView()
            case .history: HistoryView()
            case .settings: SettingsView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
