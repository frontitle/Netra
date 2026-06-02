import SwiftUI

struct RadarView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var prefs: AppPreferences

    var body: some View {
        HStack(spacing: 0) {
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
                missingDevicesNotice
                    .padding(.horizontal, 20)
                    .padding(.bottom, app.missingDevices.isEmpty ? 0 : 8)
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
            .frame(minWidth: 620, maxWidth: .infinity, maxHeight: .infinity)

            if app.isDeviceInspectorPresented, app.selectedDevice != nil {
                Divider()
                DeviceInspectorView(device: app.selectedDevice)
                    .frame(width: 340)
            }
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
            Button {
                if app.isScanning { app.cancelScan() } else { Task { await app.runFullScan() } }
            } label: {
                Label(
                    app.isScanning ? prefs.l10n(.radarCancel) : prefs.l10n(.radarScan),
                    systemImage: app.isScanning ? "stop.fill" : "dot.radiowaves.left.and.right"
                )
            }
            .buttonStyle(FuturisticButtonStyle(prominent: true))
            .keyboardShortcut("r", modifiers: .command)
            .disabled(false)
        }
    }

    @ViewBuilder
    private var missingDevicesNotice: some View {
        let missing = app.missingDevices
        if !missing.isEmpty {
            DisclosureGroup(isExpanded: $app.missingDevicesExpanded) {
                VStack(spacing: 0) {
                    ForEach(missing) { device in
                        HStack(spacing: 10) {
                            Image(systemName: "questionmark.diamond")
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(DeviceNotesStore.shared.displayName(discovered: device.hostname, ip: device.ip))
                                    .font(.callout.weight(.semibold))
                                HStack(spacing: 8) {
                                    Text(device.ip)
                                        .font(.system(.caption, design: .monospaced))
                                    if let lastSeen = KnownDevicesStore.shared.lastSeen(ip: device.ip) {
                                        Text(String(format: prefs.l10n(.missingDevicesLastSeen), Self.relativeDate(lastSeen)))
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                app.selectedDevice = device
                                app.isDeviceInspectorPresented = true
                            } label: {
                                Image(systemName: "sidebar.right")
                            }
                            .buttonStyle(.borderless)
                            .help(prefs.l10n(.inspectorSelectDevice))
                            Button {
                                Task { await app.rescanDevice(device) }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.borderless)
                            .help(prefs.l10n(.missingDevicesCheck))
                            .disabled(app.rescanningDeviceIP == device.ip)
                            Button(role: .destructive) {
                                app.forgetKnownDevice(device)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help(prefs.l10n(.missingDevicesForget))
                        }
                        .padding(.vertical, 8)
                        if device.id != missing.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.top, 8)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.magnifyingglass")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: prefs.l10n(.missingDevicesTitle), missing.count))
                            .font(.callout.weight(.semibold))
                        Text(prefs.l10n(.missingDevicesHint))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .padding(10)
            .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        }
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

    private static func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
