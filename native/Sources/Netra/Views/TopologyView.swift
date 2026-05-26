import SwiftUI

struct TopologyView: View {
    @EnvironmentObject private var prefs: AppPreferences
    @Environment(\.theme) private var theme

    let result: LanScanResult
    @Binding var collapsed: Bool
    @Binding var selectedSegment: String
    let gatewayPings: [String: PingStats]

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
                        nodeCard(title: "Internet", subtitle: "WAN", ip: "", ping: nil, style: .internet)
                        let chain = result.topology.routerChain
                        if chain.isEmpty, let gw = result.topology.gatewayBinding?.localGateway, !gw.isEmpty {
                            connector
                            nodeCard(title: prefs.l10n(.qualityGateway), subtitle: gw, ip: gw, ping: gatewayPings[gw], style: .router)
                        } else {
                            ForEach(Array(chain.enumerated()), id: \.element.id) { index, hop in
                                connector
                                let style: NodeStyle = index == chain.count - 1 ? .gateway : .router
                                nodeCard(
                                    title: hop.label,
                                    subtitle: hop.segment,
                                    ip: hop.ip,
                                    ping: gatewayPings[hop.ip],
                                    style: style,
                                    aliases: hop.aliasIPs
                                )
                            }
                        }
                        connector
                        nodeCard(
                            title: "Mac",
                            subtitle: result.interface.name,
                            ip: result.localIPs.joined(separator: " · "),
                            ping: nil,
                            style: .local
                        )
                    }
                    .padding(12)
                }
                .frame(maxHeight: 140)
                .background(AppTheme.glassPanel(cornerRadius: 12, theme: theme))

                segmentFilters
            }
        }
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

    private func nodeCard(title: String, subtitle: String, ip: String, ping: PingStats?, style: NodeStyle, aliases: [String] = []) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(theme.accent)
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
            if let ping {
                HStack(spacing: 6) {
                    Text("\(Int(ping.avgMs))ms")
                    Text("±\(Int(ping.jitterMs))")
                        .foregroundStyle(.secondary)
                }
                .font(.caption2.monospacedDigit())
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
