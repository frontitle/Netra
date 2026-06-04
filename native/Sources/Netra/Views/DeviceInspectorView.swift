import AppKit
import SwiftUI

struct DeviceInspectorView: View {
    @EnvironmentObject private var prefs: AppPreferences
    @Environment(\.theme) private var theme
    @EnvironmentObject private var app: AppState
    @ObservedObject private var notes = DeviceNotesStore.shared

    let device: LanDevice?

    @State private var aliasDraft = ""
    @State private var roleDraft = ""
    @State private var osDraft = ""
    @State private var isEditingAlias = false

    var body: some View {
        Group {
            if let device {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header(device)
                        metaGrid(device)
                        annotationSection(device)
                        portsSection(device)
                        actions(device)
                    }
                    .padding(20)
                }
                .onAppear { resetAliasDraft(for: device) }
                .onChange(of: device.ip) { _ in resetAliasDraft(for: device) }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 36))
                        .foregroundStyle(theme.accent.opacity(0.6))
                    Text(prefs.l10n(.inspectorSelectDevice))
                        .font(.headline)
                    Text(prefs.l10n(.inspectorHint))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(.ultraThinMaterial)
    }

    private func header(_ device: LanDevice) -> some View {
        let display = notes.displayName(discovered: device.hostname, device: device)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        if isEditingAlias {
                            TextField(prefs.l10n(.deviceAliasPlaceholder), text: $aliasDraft)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.title3, design: .rounded).weight(.bold))
                                .onSubmit { saveAlias(for: device) }
                            Button {
                                saveAlias(for: device)
                            } label: {
                                Image(systemName: "checkmark.circle.fill")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(theme.accent)
                            .help(prefs.l10n(.deviceAliasSave))
                        } else {
                            Text(display.isEmpty ? device.ip : display)
                                .font(.system(.title2, design: .rounded).weight(.bold))
                                .lineLimit(2)
                            Button {
                                aliasDraft = notes.alias(for: device) ?? display
                                isEditingAlias = true
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                            .help(prefs.l10n(.deviceAliasLabel))
                        }
                        if !device.isOnline {
                            Text(prefs.l10n(.deviceOffline))
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.secondary.opacity(0.2), in: Capsule())
                        }
                    }
                    if display != device.hostname, !device.hostname.isEmpty {
                        Text(String(format: prefs.l10n(.deviceDiscoveredName), device.hostname))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    valueWithCopy(device.ip, value: device.ip, style: .ip)
                    valueWithCopy(device.mac, value: device.mac, style: .mac)
                }
                Spacer()
                Button {
                    app.closeDeviceInspector()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(prefs.l10n(.inspectorClose))
            }
        }
    }

    private enum InspectorValueStyle {
        case ip, mac
    }

    private func valueWithCopy(_ text: String, value: String, style: InspectorValueStyle) -> some View {
        HStack(spacing: 5) {
            Text(text)
                .font(style == .ip ? .system(.body, design: .monospaced) : .caption.monospaced())
                .foregroundStyle(style == .ip ? AnyShapeStyle(theme.accent) : AnyShapeStyle(.secondary))
                .lineLimit(1)
                .truncationMode(.middle)
            CopyIconButton(value: value)
        }
    }

    private func metaGrid(_ device: LanDevice) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            metaCell(prefs.l10n(.metaVendor), device.vendor)
            metaCell(prefs.l10n(.metaSegment), device.segment)
            metaCell(prefs.l10n(.metaRole), device.role)
            metaCell(prefs.l10n(.metaOS), device.os)
            metaCell(prefs.l10n(.metaDNS), device.localDNS)
            metaCell(prefs.l10n(.tablePorts), String(format: prefs.l10n(.metaPortsOpen), device.ports.count))
        }
    }

    private func metaCell(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout).lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    private func annotationSection(_ device: LanDevice) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(prefs.l10n(.deviceAnnotationTitle)).font(.headline)
            annotationRow(
                title: prefs.l10n(.metaRole),
                text: $roleDraft,
                options: Self.rolePresets,
                save: { saveRole(for: device) },
                clear: { clearRole(for: device) }
            )
            annotationRow(
                title: prefs.l10n(.metaOS),
                text: $osDraft,
                options: Self.osPresets,
                save: { saveOS(for: device) },
                clear: { clearOS(for: device) }
            )
        }
        .padding(12)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    private func annotationRow(
        title: String,
        text: Binding<String>,
        options: [String],
        save: @escaping () -> Void,
        clear: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .leading)
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            Menu {
                ForEach(options, id: \.self) { option in
                    Button(option) {
                        text.wrappedValue = option
                        save()
                    }
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
            }
            .menuStyle(.borderlessButton)
            .help(prefs.l10n(.deviceAnnotationPick))
            Button(action: save) {
                Image(systemName: "checkmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(theme.accent)
            .help(prefs.l10n(.deviceAliasSave))
            Button(action: clear) {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(prefs.l10n(.deviceAnnotationClear))
        }
    }

    private func portsSection(_ device: LanDevice) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(prefs.l10n(.tablePorts)).font(.headline)
            if device.ports.isEmpty {
                Text("—").foregroundStyle(.secondary).font(.callout)
            } else {
                ForEach(device.ports) { port in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(port.port) · \(port.service)").font(.system(.body, design: .monospaced))
                            Text(port.hint).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if device.isOnline {
                            Button(prefs.l10n(.openInBrowser)) { app.openPort(ip: device.ip, port: port.port) }
                                .buttonStyle(.borderless)
                                .foregroundStyle(theme.accent)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func actions(_ device: LanDevice) -> some View {
        HStack {
            Button(app.rescanningDeviceIP == device.ip ? prefs.l10n(.deviceRescanning) : prefs.l10n(.deviceRescan)) {
                Task { await app.rescanDevice(device) }
            }
            .buttonStyle(FuturisticButtonStyle(prominent: true))
            .disabled(app.rescanningDeviceIP == device.ip)
            Spacer()
        }
    }

    private func resetAliasDraft(for device: LanDevice) {
        aliasDraft = notes.alias(for: device) ?? ""
        roleDraft = notes.roleOverride(for: device) ?? device.role
        osDraft = notes.osOverride(for: device) ?? device.os
        isEditingAlias = false
    }

    private func saveAlias(for device: LanDevice) {
        notes.setAlias(aliasDraft, for: device)
        isEditingAlias = false
    }

    private func saveRole(for device: LanDevice) {
        notes.setRoleOverride(roleDraft, for: device)
        app.applyUserOverrides(for: device)
    }

    private func saveOS(for device: LanDevice) {
        notes.setOSOverride(osDraft, for: device)
        app.applyUserOverrides(for: device)
    }

    private func clearRole(for device: LanDevice) {
        roleDraft = ""
        notes.setRoleOverride("", for: device)
        app.applyUserOverrides(for: device)
        roleDraft = app.selectedDevice?.role ?? device.role
    }

    private func clearOS(for device: LanDevice) {
        osDraft = ""
        notes.setOSOverride("", for: device)
        app.applyUserOverrides(for: device)
        osDraft = app.selectedDevice?.os ?? device.os
    }

    private static let rolePresets = [
        "Gateway / Router", "OpenWrt Router", "Router / Gateway Candidate", "Android Device",
        "iPhone / iPad", "IPC Camera", "NVR Recorder", "NAS / Storage", "Server",
        "Printer", "Web Service", "Network Device",
    ]

    private static let osPresets = [
        "OpenWrt", "Android", "iOS / iPadOS", "macOS", "Windows", "Linux",
        "Linux / Unix", "Embedded Linux", "Camera Firmware", "NVR Firmware", "Unknown",
    ]
}
