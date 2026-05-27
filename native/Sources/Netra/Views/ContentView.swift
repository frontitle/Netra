import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var prefs: AppPreferences
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            AppTheme.background(theme: theme, dark: colorScheme == .dark)
            Group {
                if showsInspector {
                    NavigationSplitView {
                        sidebar
                    } content: {
                        mainPane
                    } detail: {
                        detailPane
                            .frame(minWidth: 300, idealWidth: 360)
                    }
                } else {
                    NavigationSplitView(columnVisibility: .constant(.doubleColumn)) {
                        sidebar
                    } content: {
                        mainPane
                    } detail: {
                        EmptyView()
                    }
                }
            }
        }
        .environment(\.theme, prefs.themeColors)
        .preferredColorScheme(prefs.preferredColorScheme)
        .onChange(of: app.section) { _ in
            app.syncPingLoopsForCurrentSection()
            if app.section != .wifi {
                app.selectedWifiID = nil
            }
            if app.section != .radar {
                app.selectedDevice = nil
                app.isDeviceInspectorPresented = false
            }
        }
    }

    private var showsInspector: Bool {
        switch app.section {
        case .wifi:
            return app.selectedWifi != nil
        case .radar:
            return app.isDeviceInspectorPresented && app.selectedDevice != nil
        default:
            return false
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if app.section == .wifi {
            WifiInspectorView(network: app.selectedWifi)
        } else {
            DeviceInspectorView(device: app.selectedDevice)
        }
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
                Text(Brand.productName)
                    .font(.system(.title3, design: .rounded).weight(.bold))
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
