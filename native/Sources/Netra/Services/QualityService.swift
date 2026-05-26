import Foundation

enum QualityService {
    static func check(targets: [String]? = nil) throws -> QualityReport {
        let interface = try NetworkInterfaceService.currentInterface()
        let gateway = PingService.stats(target: interface.gateway == "未知" ? "1.1.1.1" : interface.gateway, label: "Gateway")
        let external = ["1.1.1.1", "223.5.5.5", "8.8.8.8"].map { PingService.stats(target: $0, label: $0) }
        let arp = ARPService.readAll()
        var deviceTargets = targets ?? []
        if deviceTargets.isEmpty {
            deviceTargets = arp.keys.prefix(8).map { IPv4Helpers.ipv4String($0) }
        }
        let devices = deviceTargets.map { PingService.stats(target: $0, label: $0) }
        let bad = devices.filter { $0.status == .bad || $0.status == .down }
        let diagnosis: String
        if gateway.status == .down {
            diagnosis = "默认网关不可达，请检查路由器或本机网络设置。"
        } else if !bad.isEmpty {
            diagnosis = "局部链路异常：发现 \(bad.count) 个内网设备延迟/丢包异常。"
        } else {
            diagnosis = "当前局域网质量正常。"
        }
        return QualityReport(
            interface: interface,
            gateway: gateway,
            external: external,
            devices: devices,
            diagnosis: diagnosis,
            suspects: bad.map(\.target)
        )
    }
}
