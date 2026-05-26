import SwiftUI

struct TopologyView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var prefs: AppPreferences
    @Environment(\.theme) private var theme

    let result: LanScanResult
    @Binding var collapsed: Bool
    @Binding var selectedSegment: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(prefs.l10n(.topologyTitle), systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.headline)
                    .foregroundStyle(theme.accent)
                Spacer()
                Button(collapsed ? prefs.l10n(.topologyExpand) : prefs.l10n(.topologyCollapse)) {
                    withAnimation(.spring(response: 0.35)) { collapsed.toggle() }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            if !collapsed {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        nodeCard(title: "Internet", subtitle: "WAN", ip: "", pingKeys: [], style: .internet, confirmed: true)
                        let chain = result.topology.routerChain
                        if chain.isEmpty, let gw = result.topology.gatewayBinding?.localGateway, !gw.isEmpty {
                            connector
                            routerNode(title: prefs.l10n(.qualityGateway), hop: nil, ip: gw, style: .router)
                        } else {
                            ForEach(Array(chain.enumerated()), id: \.element.id) { index, hop in
                                connector
                                let style: NodeStyle = index == chain.count - 1 ? .gateway : .router
                                routerNode(title: hop.label, hop: hop, ip: hop.ip, style: style, aliases: hop.aliasIPs)
                            }
                        }
                        connector
                        localMacCard
                    }
                    .padding(12)
                }
                .frame(maxHeight: 168)
                .background(AppTheme.glassPanel(cornerRadius: 12, theme: theme))

                segmentFilters
            }
        }
        .onAppear { app.syncPingLoopsForCurrentSection() }
    }

    private var localMacCard: some View {
        let endpoints = result.localEndpoints ?? []
        let primary = endpoints.first(where: \.isPrimary) ?? endpoints.first
        return VStack(alignment: .leading, spacing: 6) {
            Text(prefs.l10n(.localThisMac))
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.accent)
            if let primary {
                HStack(spacing: 6) {
                    Text(prefs.l10n(.localPrimaryIP))
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(theme.accent.opacity(0.25), in: Capsule())
                    Text(primary.ip)
                        .font(.system(.callout, design: .monospaced).weight(.semibold))
                }
                Text("\(primary.interfaceName) · \(primary.label)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            ForEach(endpoints.filter { !$0.isPrimary }) { ep in
                Text("\(ep.interfaceName): \(ep.ip)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 168, alignment: .leading)
        .padding(12)
        .background(theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(theme.accent.opacity(0.55), lineWidth: 1.5)
        )
    }

    private func routerNode(title: String, hop: RouterHop?, ip: String, style: NodeStyle, aliases: [String] = []) -> some View {
        let pingKeys = ([ip] + aliases).filter { !$0.isEmpty }
        return nodeCard(
            title: title,
            subtitle: hop?.segment ?? "",
            ip: ip,
            pingKeys: pingKeys,
            style: style,
            aliases: aliases,
            confirmed: hop?.confirmed ?? true
        )
    }

    private var segmentFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(prefs.l10n(.topologyAllSegments), active: selectedSegment.isEmpty) { selectedSegment = "" }
                ForEach(result.topology.segments.filter { !$0.cidr.contains("169.254") }) { seg in
                    filterChip("\(seg.cidr) (\(seg.deviceCount))", active: selectedSegment == seg.cidr) {
                        selectedSegment = seg.cidr
                    }
                }
            }
        }
    }

    private func filterChip(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(active ? theme.accent.opacity(0.25) : .white.opacity(0.06), in: Capsule())
                .overlay(Capsule().stroke(active ? theme.accent : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var connector: some View {
        HStack(spacing: 0) {
            Rectangle().fill(theme.accent.opacity(0.35)).frame(width: 24, height: 2)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(theme.accent.opacity(0.5))
        }
        .padding(.horizontal, 2)
    }

    private enum NodeStyle { case internet, router, gateway, local }

    private func resolvePing(keys: [String]) -> (stats: PingStats?, samples: [Double], key: String) {
        for k in keys {
            if let stats = app.gatewayPings[k] {
                return (stats, app.pingHistory[k] ?? [], k)
            }
        }
        return (nil, [], keys.first ?? "")
    }

    private func nodeCard(
        title: String,
        subtitle: String,
        ip: String,
        pingKeys: [String],
        style: NodeStyle,
        aliases: [String] = [],
        confirmed: Bool
    ) -> some View {
        let pingResolved = resolvePing(keys: pingKeys)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(theme.accent)
                if style != .internet {
                    Text(confirmed ? prefs.l10n(.routerConfirmed) : prefs.l10n(.routerUnconfirmed))
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background((confirmed ? Color.green : Color.orange).opacity(0.2), in: Capsule())
                        .foregroundStyle(confirmed ? .green : .orange)
                }
            }
            if !ip.isEmpty {
                Text(ip).font(.system(.callout, design: .monospaced)).lineLimit(2)
            }
            if !subtitle.isEmpty {
                Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            if !aliases.isEmpty {
                Text(aliases.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if style != .internet, !pingKeys.isEmpty {
                LivePingView(
                    samples: pingResolved.samples,
                    stats: pingResolved.stats,
                    pulse: app.pingPulse
                )
                .id("\(pingResolved.key)-\(app.pingTick)")
            }
        }
        .frame(minWidth: 152, alignment: .leading)
        .padding(12)
        .background(.white.opacity(style == .local ? 0.1 : 0.05), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(theme.accent.opacity(style == .internet ? 0.2 : 0.45), lineWidth: 1)
        )
    }
}
