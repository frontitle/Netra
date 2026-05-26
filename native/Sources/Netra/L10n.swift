import Foundation

enum L10nKey: String, CaseIterable {
    case appName
    case appTagline
    case sectionDiscovery
    case sectionDiagnostics
    case navLanDevices
    case navWifi
    case navQuality
    case navHistory
    case navSettings
    case radarTitle
    case radarScan
    case radarCancel
    case devicesCount
    case devicesDiscovering
    case filterAllSegments
    case filterAllRoles
    case searchPlaceholder
    case singleIP
    case probe
    case settingsTitle
    case settingsGeneral
    case settingsLanguage
    case settingsAppearance
    case settingsAccent
    case appearanceSystem
    case appearanceLight
    case appearanceDark
    case accentCyan
    case accentViolet
    case accentGreen
    case accentOrange
    case accentRose
    case aboutTitle
    case version
    case buildNumber
    case checkUpdates
    case checkingUpdates
    case updateAvailableFormat
    case upToDate
    case updateCheckFailed
    case openReleases
    case viewOnGitHub
    case aboutDescription
    case aboutRuntime
    case newVersionBadge
    case inspectorSelectDevice
    case inspectorHint
    case metaVendor
    case metaSegment
    case metaRole
    case metaOS
    case metaDNS
    case metaPortsOpen
    case qualityTitle
    case qualityStart
    case qualityRunning
    case qualityNotRun
    case qualityHint
    case qualityGateway
    case qualityInternalSample
    case wifiTitle
    case wifiRefresh
    case wifiSSID
    case wifiSignal
    case wifiChannel
    case wifiBand
    case wifiSecurity
    case copyIP
    case historyTitle
    case historyDeviceCount
    case topologyTitle
    case topologyExpand
    case topologyCollapse
    case topologyAllSegments
    case tableIP
    case tableHostname
    case tableVendor
    case tableSegment
    case tableRole
    case tablePorts
    case openInBrowser
    case copyright
}

enum L10n {
    static func string(_ key: L10nKey, language: AppLanguage) -> String {
        table[language]?[key] ?? table[.en]?[key] ?? key.rawValue
    }

    private static let table: [AppLanguage: [L10nKey: String]] = [
        .zhHans: zh,
        .en: en,
    ]

    private static let zh: [L10nKey: String] = [
        .appName: "Netra",
        .appTagline: "局域网洞察",
        .sectionDiscovery: "发现",
        .sectionDiagnostics: "诊断",
        .navLanDevices: "局域网设备",
        .navWifi: "附近的 Wi-Fi",
        .navQuality: "局域网质量",
        .navHistory: "历史记录",
        .navSettings: "设置",
        .radarTitle: "局域网扫描",
        .radarScan: "扫描",
        .radarCancel: "中断",
        .devicesCount: "%d 台设备",
        .devicesDiscovering: "已发现 %d 台…",
        .filterAllSegments: "全部网段",
        .filterAllRoles: "全部类型",
        .searchPlaceholder: "搜索 IP / 名称 / 厂商",
        .singleIP: "单 IP",
        .probe: "探测",
        .settingsTitle: "设置",
        .settingsGeneral: "通用",
        .settingsLanguage: "语言",
        .settingsAppearance: "外观",
        .settingsAccent: "主题色",
        .appearanceSystem: "跟随系统",
        .appearanceLight: "浅色",
        .appearanceDark: "深色",
        .accentCyan: "青色",
        .accentViolet: "紫色",
        .accentGreen: "绿色",
        .accentOrange: "橙色",
        .accentRose: "玫红",
        .aboutTitle: "关于",
        .version: "版本",
        .buildNumber: "构建号",
        .checkUpdates: "检查更新",
        .checkingUpdates: "检查中…",
        .updateAvailableFormat: "发现新版本 %@",
        .upToDate: "当前已是最新版本",
        .updateCheckFailed: "暂时无法检查更新，请稍后重试",
        .openReleases: "打开下载页",
        .viewOnGitHub: "在 GitHub 查看",
        .aboutDescription: "Netra 是 macOS 原生局域网扫描与网络拓扑工具，使用 SwiftUI 与 CoreWLAN，不依赖 WebView。",
        .aboutRuntime: "macOS 13+ · SwiftUI · CoreWLAN",
        .newVersionBadge: "有新版本",
        .inspectorSelectDevice: "选择一台设备",
        .inspectorHint: "单击列表行查看详情，双击可快速固定选择。",
        .metaVendor: "厂商",
        .metaSegment: "网段",
        .metaRole: "类型",
        .metaOS: "系统",
        .metaDNS: "DNS",
        .metaPortsOpen: "%d 开放",
        .qualityTitle: "局域网质量",
        .qualityStart: "开始检测",
        .qualityRunning: "检测中…",
        .qualityNotRun: "尚未检测",
        .qualityHint: "点击「开始检测」测量网关与公网延迟",
        .qualityGateway: "网关",
        .qualityInternalSample: "内网抽样",
        .wifiTitle: "附近的 Wi-Fi",
        .wifiRefresh: "刷新",
        .wifiSSID: "SSID",
        .wifiSignal: "信号",
        .wifiChannel: "信道",
        .wifiBand: "频段",
        .wifiSecurity: "安全",
        .copyIP: "复制 IP",
        .historyTitle: "历史记录",
        .historyDeviceCount: "%d 台设备",
        .topologyTitle: "网络拓扑",
        .topologyExpand: "展开",
        .topologyCollapse: "收起",
        .topologyAllSegments: "全部网段",
        .tableIP: "IP",
        .tableHostname: "名称",
        .tableVendor: "厂商",
        .tableSegment: "网段",
        .tableRole: "类型",
        .tablePorts: "端口",
        .openInBrowser: "在浏览器打开",
        .copyright: "© Netra · 开源软件",
    ]

    private static let en: [L10nKey: String] = [
        .appName: "Netra",
        .appTagline: "LAN insight",
        .sectionDiscovery: "Discover",
        .sectionDiagnostics: "Diagnostics",
        .navLanDevices: "LAN Devices",
        .navWifi: "Nearby Wi-Fi",
        .navQuality: "Network Quality",
        .navHistory: "History",
        .navSettings: "Settings",
        .radarTitle: "LAN Scan",
        .radarScan: "Scan",
        .radarCancel: "Stop",
        .devicesCount: "%d devices",
        .devicesDiscovering: "Found %d…",
        .filterAllSegments: "All segments",
        .filterAllRoles: "All roles",
        .searchPlaceholder: "Search IP / name / vendor",
        .singleIP: "Single IP",
        .probe: "Probe",
        .settingsTitle: "Settings",
        .settingsGeneral: "General",
        .settingsLanguage: "Language",
        .settingsAppearance: "Appearance",
        .settingsAccent: "Accent color",
        .appearanceSystem: "System",
        .appearanceLight: "Light",
        .appearanceDark: "Dark",
        .accentCyan: "Cyan",
        .accentViolet: "Violet",
        .accentGreen: "Green",
        .accentOrange: "Orange",
        .accentRose: "Rose",
        .aboutTitle: "About",
        .version: "Version",
        .buildNumber: "Build",
        .checkUpdates: "Check for Updates",
        .checkingUpdates: "Checking…",
        .updateAvailableFormat: "New version %@ available",
        .upToDate: "You're up to date",
        .updateCheckFailed: "Could not check for updates. Try again later.",
        .openReleases: "Open Releases",
        .viewOnGitHub: "View on GitHub",
        .aboutDescription: "Netra is a native macOS LAN scanner and network topology tool built with SwiftUI and CoreWLAN — no WebView.",
        .aboutRuntime: "macOS 13+ · SwiftUI · CoreWLAN",
        .newVersionBadge: "Update available",
        .inspectorSelectDevice: "Select a device",
        .inspectorHint: "Click a row for details; double-click to pin selection.",
        .metaVendor: "Vendor",
        .metaSegment: "Segment",
        .metaRole: "Role",
        .metaOS: "OS",
        .metaDNS: "DNS",
        .metaPortsOpen: "%d open",
        .qualityTitle: "Network Quality",
        .qualityStart: "Run Test",
        .qualityRunning: "Testing…",
        .qualityNotRun: "No test yet",
        .qualityHint: "Tap Run Test to measure gateway and internet latency",
        .qualityGateway: "Gateway",
        .qualityInternalSample: "LAN sample",
        .wifiTitle: "Nearby Wi-Fi",
        .wifiRefresh: "Refresh",
        .wifiSSID: "SSID",
        .wifiSignal: "Signal",
        .wifiChannel: "Channel",
        .wifiBand: "Band",
        .wifiSecurity: "Security",
        .copyIP: "Copy IP",
        .historyTitle: "History",
        .historyDeviceCount: "%d devices",
        .topologyTitle: "Topology",
        .topologyExpand: "Expand",
        .topologyCollapse: "Collapse",
        .topologyAllSegments: "All segments",
        .tableIP: "IP",
        .tableHostname: "Name",
        .tableVendor: "Vendor",
        .tableSegment: "Segment",
        .tableRole: "Role",
        .tablePorts: "Ports",
        .openInBrowser: "Open in browser",
        .copyright: "© Netra · Open source",
    ]
}
