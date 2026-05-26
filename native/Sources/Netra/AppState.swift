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
    @Published var topologyCollapsed = false
    @Published var segmentFilter = ""
    @Published var roleFilter = ""
    @Published var searchText = ""
    @Published var selectedDevice: LanDevice?
    @Published var singleScanIP = ""
    @Published var singleScanLoading = false

    @Published var tableSortColumn: DeviceTableColumn = .ip
    @Published var tableSortAscending = true
    @Published var qualityWatch: [String] = []

    private var pingTimer: Timer?
    private let snapshotsKey = "netra.scanHistory"

    var filteredDevices: [LanDevice] {
        devices.filter { device in
            if !segmentFilter.isEmpty, device.segment != segmentFilter { return false }
            if !roleFilter.isEmpty, !device.role.contains(roleFilter) { return false }
            if !searchText.isEmpty {
                let q = searchText.lowercased()
                let hay = [device.ip, device.hostname, device.vendor, device.mac, device.role].joined(separator: " ").lowercased()
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
        Task { await runFullScan() }
    }

    func runFullScan() async {
        isScanning = true
        errorMessage = ""
        devices = []
        lanResult = nil
        selectedDevice = nil
        segmentFilter = ""
        gatewayPings = [:]
        pingHistory = [:]
        scanFoundCount = 0
        ScanCancellation.shared.reset()

        await Task.detached(priority: .userInitiated) {
            OUILookup.warmup()
            do {
                let locStatus = await MainActor.run { LocationAuthorizationService.shared.status }
                let wifi = LocationAuthorizationService.canScanWifi(status: locStatus) ? WifiScanner.scan() : []
                var foundCount = 0
                let lan = try LANScanner.scan { _ in
                    foundCount += 1
                    if foundCount == 1 || foundCount % 8 == 0 {
                        let count = foundCount
                        Task { @MainActor in self.scanFoundCount = count }
                    }
                }
                await MainActor.run {
                    self.wifiNetworks = wifi
                    self.lanResult = lan
                    self.devices = lan.devices
                    self.scanFoundCount = lan.devices.count
                    self.lastScanAt = Self.timeString(Date())
                    self.saveSnapshot(wifi: wifi, lan: lan)
                    self.isScanning = false
                    self.startGatewayPingLoop()
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

    func scanSingleIP() async {
        let ip = singleScanIP.trimmingCharacters(in: .whitespaces)
        guard !ip.isEmpty else { return }
        singleScanLoading = true
        defer { singleScanLoading = false }
        do {
            let device = try await Task.detached { try LANScanner.scanHost(ip: ip) }.value
            upsertDevice(device)
            selectedDevice = device
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func runQualityCheck() async {
        qualityLoading = true
        defer { qualityLoading = false }
        do {
            let watch = qualityWatch
            quality = try await Task.detached {
                try QualityService.check(targets: watch.isEmpty ? nil : watch)
            }.value
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openPort(ip: String, port: Int) {
        let urlString = (port == 443 || port == 8443) ? "https://\(ip):\(port)" : "http://\(ip):\(port)"
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    private func upsertDevice(_ device: LanDevice) {
        if let idx = devices.firstIndex(where: { $0.ip == device.ip }) {
            devices[idx] = device
        } else {
            devices.append(device)
        }
        devices.sort { $0.ip.localizedStandardCompare($1.ip) == .orderedAscending }
    }

    func startGatewayPingLoop() {
        pingTimer?.invalidate()
        guard section == .radar else { return }
        pingTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
            Task { await self?.refreshGatewayPing() }
        }
        Task { await refreshGatewayPing() }
    }

    func stopGatewayPingLoop() {
        pingTimer?.invalidate()
        pingTimer = nil
    }

    func refreshGatewayPing() async {
        var targets = Set<String>()
        if let gw = lanResult?.interface.gateway, gw != "未知" { targets.insert(gw) }
        for hop in lanResult?.topology.routerChain ?? [] {
            targets.insert(hop.ip)
            hop.aliasIPs.forEach { targets.insert($0) }
        }
        if let upstream = lanResult?.topology.gatewayBinding?.upstreamGateway, !upstream.isEmpty {
            targets.insert(upstream)
        }
        var pings: [String: PingStats] = [:]
        await withTaskGroup(of: (String, PingStats).self) { group in
            for ip in targets {
                group.addTask { (ip, PingService.stats(target: ip, label: ip, count: 1)) }
            }
            for await pair in group {
                pings[pair.0] = pair.1
            }
        }
        for (ip, stat) in pings {
            var samples = pingHistory[ip] ?? []
            samples.append(stat.avgMs)
            if samples.count > 14 { samples.removeFirst(samples.count - 14) }
            pingHistory[ip] = samples
        }
        gatewayPings = pings
        pingPulse.toggle()
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
