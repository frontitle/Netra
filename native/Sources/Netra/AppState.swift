import AppKit
import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var section: AppSection = .radar

    @Published var wifiNetworks: [WifiNetwork] = []
    @Published var selectedWifiID: String?
    var selectedWifi: WifiNetwork? {
        get {
            guard let id = selectedWifiID else { return nil }
            return wifiNetworks.first { $0.id == id }
        }
        set {
            selectedWifiID = newValue?.id
        }
    }
    @Published var lanResult: LanScanResult?
    @Published var devices: [LanDevice] = []
    @Published var quality: QualityReport?
    @Published var snapshots: [ScanSnapshot] = []

    @Published var isScanning = false
    @Published var scanFoundCount = 0
    @Published var qualityLoading = false
    @Published var errorMessage = ""
    @Published var lastScanAt = ""

    @Published var gatewayPings: [String: PingStats] = [:]
    @Published var pingHistory: [String: [Double]] = [:]
    @Published var pingPulse = false
    @Published var pingTick: UInt = 0

    @Published var qualityLivePings: [String: PingStats] = [:]
    @Published var qualityPingHistory: [String: [Double]] = [:]
    @Published var qualityPingPulse = false
    @Published var qualityPingTick: UInt = 0

    @Published var topologyCollapsed = false
    @Published var segmentFilter = ""
    @Published var roleFilter = ""
    @Published var searchText = ""
    @Published var selectedDevice: LanDevice?
    @Published var isDeviceInspectorPresented = false
    @Published var tableSortColumn: DeviceTableColumn = .ip
    @Published var tableSortAscending = true
    @Published var qualityWatch: [String] = []
    @Published var showOfflineDevices = UserDefaults.standard.bool(forKey: "netra.showOfflineDevices")
    @Published var rescanningDeviceIP: String?

    private var pingLoopTask: Task<Void, Never>?
    private var ouiObserver: NSObjectProtocol?

    private enum PingLoopMode {
        case gateway
        case quality
    }
    private let snapshotsKey = "netra.scanHistory"

    var allDevices: [LanDevice] {
        guard showOfflineDevices else { return devices }
        let onlineIPs = Set(devices.map(\.ip))
        let offline = KnownDevicesStore.shared.offlineDevices(excludingOnline: onlineIPs)
        return (devices + offline).sorted { $0.ip.localizedStandardCompare($1.ip) == .orderedAscending }
    }

    var filteredDevices: [LanDevice] {
        allDevices.filter { device in
            if !segmentFilter.isEmpty, device.segment != segmentFilter { return false }
            if !roleFilter.isEmpty, !device.role.contains(roleFilter) { return false }
            if !searchText.isEmpty {
                let q = searchText.lowercased()
                let alias = DeviceNotesStore.shared.alias(for: device.ip) ?? ""
                let hay = [device.ip, device.hostname, alias, device.vendor, device.mac, device.role].joined(separator: " ").lowercased()
                if !hay.contains(q) { return false }
            }
            return true
        }
    }

    var availableSegments: [String] {
        Array(Set(devices.map(\.segment))).sorted()
    }

    var availableRoles: [String] {
        Array(Set(devices.map(\.role))).sorted()
    }

    init() {
        let topoKey = "netra.topologyExpanded"
        let legacyTopo = "ipfinder.topologyExpanded"
        if let raw = UserDefaults.standard.string(forKey: topoKey)
            ?? UserDefaults.standard.string(forKey: legacyTopo) {
            topologyCollapsed = raw != "1"
        }
        snapshots = loadSnapshots()
        OUILookup.startLoading()
        ouiObserver = NotificationCenter.default.addObserver(
            forName: .ouiDatabaseDidLoad,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshDeviceVendors() }
        }
        Task { await runFullScan() }
    }

    deinit {
        if let ouiObserver { NotificationCenter.default.removeObserver(ouiObserver) }
    }

    func liveQualityStats(fallback: PingStats) -> PingStats {
        qualityLivePings[fallback.target] ?? fallback
    }

    func runFullScan() async {
        isScanning = true
        errorMessage = ""
        if let current = try? NetworkInterfaceService.currentInterface(),
           let local = IPv4Helpers.parseIPv4(current.ip) {
            KnownDevicesStore.shared.clear(segment: IPv4Helpers.segmentID(for: local))
        }
        devices = []
        lanResult = nil
        selectedDevice = nil
        isDeviceInspectorPresented = false
        segmentFilter = ""
        gatewayPings = [:]
        pingHistory = [:]
        scanFoundCount = 0
        ScanCancellation.shared.reset()

        await Task.detached(priority: .userInitiated) {
            do {
                let locStatus = await MainActor.run { LocationAuthorizationService.shared.status }
                let wifi = LocationAuthorizationService.canScanWifi(status: locStatus) ? WifiScanner.scan() : []
                let lan = try LANScanner.scan { device in
                    Task { @MainActor in
                        self.upsertDevice(device)
                        self.scanFoundCount = self.devices.count
                    }
                }
                await MainActor.run {
                    self.wifiNetworks = wifi
                    self.lanResult = lan
                    KnownDevicesStore.shared.applyScan(lan.devices)
                    self.scanFoundCount = lan.devices.count
                    self.lastScanAt = Self.timeString(Date())
                    self.saveSnapshot(wifi: wifi, lan: lan)
                    self.isScanning = false
                    self.refreshDeviceVendors()
                    self.syncPingLoopsForCurrentSection()
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isScanning = false
                }
            }
        }.value
    }

    func cancelScan() {
        ScanCancellation.shared.cancel()
        isScanning = false
    }

    func runQualityCheck() async {
        qualityLoading = true
        defer { qualityLoading = false }
        do {
            let watch = qualityWatch
            let report = try await Task.detached {
                try QualityService.check(targets: watch.isEmpty ? nil : watch)
            }.value
            quality = report
            qualityLivePings = [:]
            qualityPingHistory = [:]
            syncPingLoopsForCurrentSection()
            await refreshQualityLivePing()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func rescanDevice(_ device: LanDevice) async {
        rescanningDeviceIP = device.ip
        defer { rescanningDeviceIP = nil }
        do {
            let refreshed = try await Task.detached(priority: .userInitiated) {
                try LANScanner.scanDevice(ip: device.ip)
            }.value
            upsertDevice(refreshed)
            isDeviceInspectorPresented = true
            if var lan = lanResult {
                if let idx = lan.devices.firstIndex(where: { $0.ip == refreshed.ip }) {
                    lan.devices[idx] = refreshed
                } else {
                    lan.devices.append(refreshed)
                }
                lanResult = lan
            }
            selectedDevice = refreshed
            KnownDevicesStore.shared.applyScan(devices)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func closeDeviceInspector() {
        isDeviceInspectorPresented = false
        selectedDevice = nil
    }

    func clearHistory() {
        snapshots = []
        UserDefaults.standard.removeObject(forKey: snapshotsKey)
        UserDefaults.standard.removeObject(forKey: "ipfinder.native.scanHistory")
    }

    func openPort(ip: String, port: Int) {
        let urlString = (port == 443 || port == 8443) ? "https://\(ip):\(port)" : "http://\(ip):\(port)"
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    func setShowOfflineDevices(_ value: Bool) {
        showOfflineDevices = value
        UserDefaults.standard.set(value, forKey: "netra.showOfflineDevices")
    }

    func refreshWifi() {
        guard LocationAuthorizationService.canScanWifi(status: LocationAuthorizationService.shared.status) else { return }
        wifiNetworks = WifiScanner.scan()
        if selectedWifiID == nil {
            selectedWifiID = wifiNetworks.first(where: \.isConnected)?.id ?? wifiNetworks.first?.id
        }
    }

    func syncPingLoopsForCurrentSection() {
        stopPingLoop()
        let mode: PingLoopMode?
        switch section {
        case .radar where lanResult != nil:
            mode = .gateway
        case .quality where quality != nil:
            mode = .quality
        default:
            mode = nil
        }
        guard let mode else { return }
        pingLoopTask = Task { @MainActor in
            while !Task.isCancelled {
                switch mode {
                case .gateway:
                    await refreshGatewayPing()
                case .quality:
                    await refreshQualityLivePing()
                }
                try? await Task.sleep(nanoseconds: 1_200_000_000)
            }
        }
    }

    func refreshDeviceVendors() {
        guard OUILookup.ready else { return }
        var changed = false
        for i in devices.indices {
            let mac = devices[i].mac
            let d = devices[i]
            let vendor = OUILookup.vendor(for: mac, hostname: d.hostname, ports: d.ports)
            if d.vendor != vendor {
                devices[i].vendor = vendor
                let os = DeviceInference.inferOS(ports: d.ports, vendor: vendor, mac: mac)
                devices[i].os = os
                changed = true
            }
        }
        if changed, let lan = lanResult {
            var updated = lan
            updated.devices = devices
            lanResult = updated
        }
    }

    private func upsertDevice(_ device: LanDevice) {
        var online = device
        online.isOnline = true
        let shouldOpenInspector = selectedDevice?.ip == online.ip
        if let idx = devices.firstIndex(where: { $0.ip == online.ip }) {
            devices[idx] = online
        } else {
            devices.append(online)
        }
        devices.sort { $0.ip.localizedStandardCompare($1.ip) == .orderedAscending }
        if shouldOpenInspector {
            selectedDevice = online
            isDeviceInspectorPresented = true
        }
    }

    func stopPingLoop() {
        pingLoopTask?.cancel()
        pingLoopTask = nil
    }

    func refreshGatewayPing() async {
        var targets = Set<String>()
        if let gw = lanResult?.interface.gateway, gw != "未知" { targets.insert(gw) }
        for hop in lanResult?.topology.routerChain ?? [] {
            if !hop.ip.isEmpty { targets.insert(hop.ip) }
            hop.aliasIPs.forEach { if !$0.isEmpty { targets.insert($0) } }
        }
        if let binding = lanResult?.topology.gatewayBinding {
            if !binding.upstreamGateway.isEmpty { targets.insert(binding.upstreamGateway) }
            binding.aliasIPs.forEach { if !$0.isEmpty { targets.insert($0) } }
        }
        guard !targets.isEmpty else { return }

        let targetList = Array(targets)
        let pings = await Task.detached(priority: .userInitiated) {
            await Self.probePings(targets: targetList)
        }.value

        var nextHistory = pingHistory
        for (ip, stat) in pings {
            var samples = nextHistory[ip] ?? []
            samples.append(stat.avgMs)
            if samples.count > 14 { samples.removeFirst(samples.count - 14) }
            nextHistory[ip] = samples
        }
        pingHistory = nextHistory
        gatewayPings = pings
        pingPulse.toggle()
        pingTick &+= 1
    }

    func refreshQualityLivePing() async {
        guard let report = quality else { return }
        var targets = Set<String>()
        targets.insert(report.gateway.target)
        report.external.forEach { targets.insert($0.target) }
        report.devices.forEach { targets.insert($0.target) }
        guard !targets.isEmpty else { return }

        let targetList = Array(targets)
        let pings = await Task.detached(priority: .userInitiated) {
            await Self.probePings(targets: targetList)
        }.value

        var nextHistory = qualityPingHistory
        for (ip, stat) in pings {
            var samples = nextHistory[ip] ?? []
            samples.append(stat.avgMs)
            if samples.count > 14 { samples.removeFirst(samples.count - 14) }
            nextHistory[ip] = samples
        }
        qualityPingHistory = nextHistory
        qualityLivePings = pings
        qualityPingPulse.toggle()
        qualityPingTick &+= 1
    }

    private static func probePings(targets: [String]) async -> [String: PingStats] {
        var pings: [String: PingStats] = [:]
        await withTaskGroup(of: (String, PingStats).self) { group in
            for ip in targets {
                group.addTask { (ip, PingService.stats(target: ip, label: ip, count: 1)) }
            }
            for await pair in group {
                pings[pair.0] = pair.1
            }
        }
        return pings
    }

    private func saveSnapshot(wifi: [WifiNetwork], lan: LanScanResult) {
        let key = wifi.first(where: \.isConnected)?.ssid ?? lan.interface.gateway
        let snapshot = ScanSnapshot(
            id: UUID(),
            networkKey: key,
            networkName: key,
            scannedAt: Date(),
            wifiNetworks: wifi,
            lanResult: lan,
            devices: lan.devices
        )
        snapshots.removeAll { $0.networkKey == key }
        snapshots.insert(snapshot, at: 0)
        snapshots = Array(snapshots.prefix(24))
        if let data = try? JSONEncoder().encode(snapshots) {
            UserDefaults.standard.set(data, forKey: snapshotsKey)
        }
    }

    private func loadSnapshots() -> [ScanSnapshot] {
        let legacyKey = "ipfinder.native.scanHistory"
        let data = UserDefaults.standard.data(forKey: snapshotsKey)
            ?? UserDefaults.standard.data(forKey: legacyKey)
        guard let data,
              let decoded = try? JSONDecoder().decode([ScanSnapshot].self, from: data) else { return [] }
        return decoded
    }

    private static func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .medium
        return f.string(from: date)
    }
}
