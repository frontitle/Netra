import AppKit
import CoreLocation
import Combine

final class LocationAuthorizationService: NSObject, ObservableObject {
    static let shared = LocationAuthorizationService()

    @Published private(set) var status: CLAuthorizationStatus = .notDetermined

    /// 定位授权成功后调用（用于立即刷新 Wi-Fi 列表）。
    var onAuthorized: (() -> Void)?

    private let manager = CLLocationManager()

    static func canScanWifi(status: CLAuthorizationStatus) -> Bool {
        switch status {
        case .authorizedAlways, .authorized: return true
        default: return false
        }
    }

    var canScanWifi: Bool { Self.canScanWifi(status: status) }

    var needsAuthorization: Bool {
        switch status {
        case .notDetermined, .denied, .restricted:
            return true
        default:
            return false
        }
    }

    override private init() {
        super.init()
        manager.delegate = self
        refreshStatus()
    }

    func refreshStatus() {
        DispatchQueue.main.async {
            self.status = self.manager.authorizationStatus
        }
    }

    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func openSystemLocationSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_LocationServices",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices",
            "x-apple.systempreferences:com.apple.preference.security?Privacy",
        ]
        for raw in candidates {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}

extension LocationAuthorizationService: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            let previous = self.status
            self.status = manager.authorizationStatus
            if !Self.canScanWifi(status: previous), Self.canScanWifi(status: self.status) {
                self.onAuthorized?()
            }
        }
    }
}
