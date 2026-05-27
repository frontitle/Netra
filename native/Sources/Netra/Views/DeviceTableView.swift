import AppKit
import SwiftUI

enum DeviceTableColumn: String, CaseIterable, Identifiable {
  case ip, hostname, vendor, role, ports
  var id: String { rawValue }

  static var visibleColumns: [DeviceTableColumn] {
    [.ip, .hostname, .vendor, .role, .ports]
  }

  func title(language: AppLanguage) -> String {
    switch self {
    case .ip: return L10n.string(.tableIP, language: language)
    case .hostname: return L10n.string(.tableHostname, language: language)
    case .vendor: return L10n.string(.tableVendor, language: language)
    case .role: return L10n.string(.tableRole, language: language)
    case .ports: return L10n.string(.tablePorts, language: language)
    }
  }
  var width: CGFloat {
    switch self {
    case .ip: return 130
    case .hostname: return 180
    case .vendor: return 140
    case .role: return 180
    case .ports: return 200
    }
  }
}

enum SegmentRowColors {
  static func background(for segment: String, dark: Bool) -> NSColor {
    let hash = abs(segment.hashValue)
    let hue = CGFloat(hash % 360) / 360.0
    if dark {
      return NSColor(calibratedHue: hue, saturation: 0.35, brightness: 0.22, alpha: 1)
    }
    return NSColor(calibratedHue: hue, saturation: 0.18, brightness: 0.94, alpha: 1)
  }
}

struct DeviceTableView: NSViewRepresentable {
  @EnvironmentObject private var prefs: AppPreferences
  @ObservedObject private var notes = DeviceNotesStore.shared
  @Environment(\.colorScheme) private var colorScheme

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
    table.rowHeight = 30
    table.usesAlternatingRowBackgroundColors = false
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

    for col in DeviceTableColumn.visibleColumns {
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
    context.coordinator.language = prefs.language
    context.coordinator.isDark = colorScheme == .dark
    if let table = context.coordinator.tableView {
      for col in DeviceTableColumn.visibleColumns {
        if let column = table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(col.rawValue)) {
          column.title = col.title(language: prefs.language)
        }
      }
    }
    let signature = devices.map { "\($0.ip)|\($0.isOnline)|\($0.hostname)|\($0.ports.map(\.port))" }.joined(separator: "\n")
      + "|\(prefs.language.rawValue)|\(notes.revision)"
    guard signature != context.coordinator.lastDeviceSignature else { return }
    context.coordinator.lastDeviceSignature = signature
    context.coordinator.reload()
  }

  final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var parent: DeviceTableView
    weak var tableView: NSTableView?
    var lastDeviceSignature = ""
    var isDark = true
    var language: AppLanguage = .en
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
          case .role: return a.role.localizedStandardCompare(b.role)
          case .ports:
            let pa = a.ports.map { String($0.port) }.joined(separator: ",")
            let pb = b.ports.map { String($0.port) }.joined(separator: ",")
            return pa.localizedStandardCompare(pb)
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

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
      let view = NSTableRowView()
      if row < sorted.count {
        view.backgroundColor = SegmentRowColors.background(for: sorted[row].segment, dark: isDark)
      }
      return view
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
      guard let id = tableColumn?.identifier.rawValue,
            let col = DeviceTableColumn(rawValue: id),
            row < sorted.count else { return nil }
      let device = sorted[row]
      let value = value(device, col: col)
      if isLoadingValue(value) {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.alignment = .centerY
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.startAnimation(nil)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.widthAnchor.constraint(equalToConstant: 14).isActive = true
        spinner.heightAnchor.constraint(equalToConstant: 14).isActive = true
        let label = NSTextField(labelWithString: value)
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        stack.addArrangedSubview(spinner)
        stack.addArrangedSubview(label)
        return stack
      }
      let textField = NSTextField(labelWithString: value)
      textField.lineBreakMode = .byTruncatingTail
      textField.font = col == .ip || col == .ports ? .monospacedSystemFont(ofSize: 12, weight: .regular) : .systemFont(ofSize: 13)
      textField.textColor = device.isOnline ? .labelColor : .secondaryLabelColor
      textField.backgroundColor = .clear
      textField.isBordered = false
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
      case .hostname:
        let discovered = device.hostname.isEmpty || device.hostname == "—" ? "—" : device.hostname
        if device.isOnline { return discovered }
        return "\(discovered) (\(L10n.string(.deviceOffline, language: language)))"
      case .vendor: return device.vendor
      case .role: return device.role
      case .ports:
        if device.ports.isEmpty { return "—" }
        return device.ports.map { String($0.port) }.joined(separator: ", ")
      }
    }

    private func isLoadingValue(_ value: String) -> Bool {
      value.contains("扫描中") || value.contains("识别中")
    }
  }
}
