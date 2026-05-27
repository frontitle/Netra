import SwiftUI

struct RadarView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var prefs: AppPreferences

    var body: some View {
        VStack(spacing: 0) {
            scanHeader
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)
            if !app.errorMessage.isEmpty {
                Text(app.errorMessage)
                    .foregroundStyle(.red)
                    .font(.callout)
                    .padding(.horizontal, 20)
            }
            if let lan = app.lanResult {
                TopologyView(
                    result: lan,
                    collapsed: $app.topologyCollapsed
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            offlineToggle
                .padding(.horizontal, 20)
                .padding(.bottom, 6)
            filterBar
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            DeviceTableView(
                devices: app.filteredDevices,
                selection: Binding(
                    get: { app.selectedDevice },
                    set: { newValue in
                        app.selectedDevice = newValue
                        app.isDeviceInspectorPresented = newValue != nil
                    }
                ),
                sortColumn: $app.tableSortColumn,
                sortAscending: $app.tableSortAscending
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }

    private var scanHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(prefs.l10n(.radarTitle))
                    .font(.system(.title2, design: .rounded).weight(.bold))
                HStack(spacing: 12) {
                    if !app.lastScanAt.isEmpty {
                        Label(app.lastScanAt, systemImage: "clock")
                    }
                    if app.isScanning, app.scanFoundCount > 0 {
                        Label(String(format: prefs.l10n(.devicesDiscovering), app.scanFoundCount), systemImage: "desktopcomputer")
                    } else {
                        Label(String(format: prefs.l10n(.devicesCount), app.devices.count), systemImage: "desktopcomputer")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if app.isScanning {
                ProgressView().controlSize(.small).padding(.trailing, 8)
            }
            Button(app.isScanning ? prefs.l10n(.radarCancel) : prefs.l10n(.radarScan)) {
                if app.isScanning { app.cancelScan() } else { Task { await app.runFullScan() } }
            }
            .buttonStyle(FuturisticButtonStyle(prominent: true))
            .keyboardShortcut("r", modifiers: .command)
            .disabled(false)
        }
    }

    private var offlineToggle: some View {
        Toggle(isOn: Binding(
            get: { app.showOfflineDevices },
            set: { app.setShowOfflineDevices($0) }
        )) {
            Text(prefs.l10n(.showOfflineDevices))
        }
        .toggleStyle(.checkbox)
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            Picker(prefs.l10n(.tableSegment), selection: $app.segmentFilter) {
                Text(prefs.l10n(.filterAllSegments)).tag("")
                ForEach(app.availableSegments, id: \.self) { seg in
                    Text(seg).tag(seg)
                }
            }
            .frame(width: 200)
            Picker(prefs.l10n(.tableRole), selection: $app.roleFilter) {
                Text(prefs.l10n(.filterAllRoles)).tag("")
                ForEach(app.availableRoles, id: \.self) { role in
                    Text(role).tag(role)
                }
            }
            .frame(width: 180)
            TextField(prefs.l10n(.searchPlaceholder), text: $app.searchText)
                .textFieldStyle(.roundedBorder)
        }
    }
}
