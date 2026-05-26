import AppKit
import SwiftUI

enum DeviceTableColumn: String, CaseIterable, Identifiable {
    case ip, hostname, vendor, segment, role, ports
    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .ip: return L10n.string(.tableIP, language: language)
        case .hostname: return L10n.string(.tableHostname, language: language)
        case .vendor: return L10n.string(.tableVendor, language: language)
        case .segment: return L10n.string(.tableSegment, language: language)
        case .role: return L10n.string(.tableRole, language: language)
        case .ports: return L10n.string(.tablePorts, language: language)
        }
    }
    var width: CGFloat {
        switch self {
        case .ip: return 130
        case .hostname: return 180
        case .vendor: return 140
        case .segment: return 150
        case .role: return 160
        case .ports: return 56
        }
    }
}

struct DeviceTableView: NSViewRepresentable {
    @EnvironmentObject private var prefs: AppPreferences

    let devices: [LanDevice]
    @Binding var selection: LanDevice?
    @Binding var sortColumn: DeviceTableColumn
    @Binding var sortAscending: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false

        let table = NSTableView()
        table.style = .fullWidth
        table.rowHeight = 28
        table.usesAlternatingRowBackgroundColors = true
        table.backgroundColor = .clear
        table.gridColor = NSColor.white.withAlphaComponent(0.06)
        table.gridStyleMask = .solidHorizontalGridLineMask
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.allowsMultipleSelection = false
        table.delegate = context.coordinator
        table.dataSource = context.coordinator
        table.target = context.coordinator
        table.doubleAction = #selector(Coordinator.doubleClick(_:))
        table.headerView = NSTableHeaderView()

        for col in DeviceTableColumn.allCases {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(col.rawValue))
            column.title = col.title(language: prefs.language)
            column.width = col.width
            column.minWidth = 48
            column.resizingMask = .userResizingMask
            column.sortDescriptorPrototype = NSSortDescriptor(key: col.rawValue, ascending: true)
            table.addTableColumn(column)
        }
        table.sortDescriptors = [NSSortDescriptor(key: DeviceTableColumn.ip.rawValue, ascending: true)]

        scroll.documentView = table
        context.coordinator.tableView = table
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        if let table = context.coordinator.tableView {
            for col in DeviceTableColumn.allCases {
                if let column = table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(col.rawValue)) {
                    column.title = col.title(language: prefs.language)
                }
            }
        }
        let signature = devices.map(\.ip).joined(separator: "\n") + "|\(prefs.language.rawValue)"
        guard signature != context.coordinator.lastDeviceSignature else { return }
        context.coordinator.lastDeviceSignature = signature
        context.coordinator.reload()
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: DeviceTableView
        weak var tableView: NSTableView?
        var lastDeviceSignature = ""
        private var sorted: [LanDevice] = []

        init(_ parent: DeviceTableView) {
            self.parent = parent
        }

        func reload() {
            sorted = parent.devices.sorted { a, b in
                let cmp: ComparisonResult = {
                    switch parent.sortColumn {
                    case .ip: return a.ip.localizedStandardCompare(b.ip)
                    case .hostname: return a.hostname.localizedStandardCompare(b.hostname)
                    case .vendor: return a.vendor.localizedStandardCompare(b.vendor)
                    case .segment: return a.segment.localizedStandardCompare(b.segment)
                    case .role: return a.role.localizedStandardCompare(b.role)
                    case .ports: return a.ports.count == b.ports.count ? .orderedSame : (a.ports.count < b.ports.count ? .orderedAscending : .orderedDescending)
                    }
                }()
                return parent.sortAscending ? cmp == .orderedAscending : cmp == .orderedDescending
            }
            tableView?.reloadData()
            if let sel = parent.selection, let row = sorted.firstIndex(where: { $0.id == sel.id }) {
                tableView?.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int { sorted.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let id = tableColumn?.identifier.rawValue,
                  let col = DeviceTableColumn(rawValue: id),
                  row < sorted.count else { return nil }
            let device = sorted[row]
            let textField = NSTextField(labelWithString: value(device, col: col))
            textField.lineBreakMode = .byTruncatingTail
            textField.font = col == .ip ? .monospacedSystemFont(ofSize: 12, weight: .regular) : .systemFont(ofSize: 13)
            textField.textColor = .labelColor
            return textField
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let table = tableView else { return }
            let row = table.selectedRow
            parent.selection = row >= 0 && row < sorted.count ? sorted[row] : nil
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard let sort = tableView.sortDescriptors.first,
                  let key = sort.key,
                  let col = DeviceTableColumn(rawValue: key) else { return }
            parent.sortColumn = col
            parent.sortAscending = sort.ascending
            reload()
        }

        @objc func doubleClick(_ sender: Any?) {
            guard let table = tableView else { return }
            let row = table.clickedRow
            if row >= 0, row < sorted.count {
                parent.selection = sorted[row]
            }
        }

        private func value(_ device: LanDevice, col: DeviceTableColumn) -> String {
            switch col {
            case .ip: return device.ip
            case .hostname: return device.hostname
            case .vendor: return device.vendor
            case .segment: return device.segment
            case .role: return device.role
            case .ports: return "\(device.ports.count)"
            }
        }
    }
}
