import AppKit
import SwiftUI

struct DeviceInspectorView: View {
    @EnvironmentObject private var prefs: AppPreferences
    @Environment(\.theme) private var theme
    @EnvironmentObject private var app: AppState

    let device: LanDevice?

    var body: some View {
        Group {
            if let device {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header(device)
                        metaGrid(device)
                        portsSection(device)
                        actions(device)
                    }
                    .padding(20)
                }
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
        VStack(alignment: .leading, spacing: 6) {
            Text(device.hostname)
                .font(.system(.title2, design: .rounded).weight(.bold))
            Text(device.ip)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(theme.accent)
            Text(device.mac)
                .font(.caption)
                .foregroundStyle(.secondary)
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
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
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
                        Button(prefs.l10n(.openInBrowser)) { app.openPort(ip: device.ip, port: port.port) }
                            .buttonStyle(.borderless)
                            .foregroundStyle(theme.accent)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func actions(_ device: LanDevice) -> some View {
        HStack {
            Button(prefs.l10n(.copyIP)) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(device.ip, forType: .string)
            }
            Spacer()
        }
    }
}
