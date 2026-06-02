import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var prefs: AppPreferences
    @Environment(\.theme) private var theme

    @State private var confirmClearHistory = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageHeader(prefs.l10n(.historyTitle), subtitle: historySubtitle) {
                Button(role: .destructive) {
                    confirmClearHistory = true
                } label: {
                    Label(prefs.l10n(.historyClear), systemImage: "trash")
                }
                .buttonStyle(FuturisticButtonStyle())
                .disabled(app.snapshots.isEmpty)
            }
            if app.snapshots.isEmpty {
                EmptyStateView(
                    icon: "clock.arrow.circlepath",
                    title: prefs.l10n(.historyEmpty),
                    message: prefs.l10n(.historyEmptyHint)
                )
            } else {
                List(app.snapshots) { snap in
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(theme.accent.opacity(0.10))
                            Image(systemName: "network")
                                .foregroundStyle(theme.accent)
                        }
                        .frame(width: 34, height: 34)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(snap.networkName)
                                .font(.headline)
                                .lineLimit(1)
                            Text("\(String(format: prefs.l10n(.historyDeviceCount), snap.devices.count)) · \(snap.scannedAt.formatted())")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 3)
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .padding()
        .alert(prefs.l10n(.historyClearConfirmTitle), isPresented: $confirmClearHistory) {
            Button(prefs.l10n(.historyClear), role: .destructive) {
                app.clearHistory()
            }
            Button(prefs.l10n(.no), role: .cancel) {}
        } message: {
            Text(prefs.l10n(.historyClearConfirmBody))
        }
    }

    private var historySubtitle: String? {
        guard !app.snapshots.isEmpty else { return nil }
        return String(format: prefs.l10n(.historySnapshotCount), app.snapshots.count)
    }
}
