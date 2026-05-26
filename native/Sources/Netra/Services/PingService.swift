import Foundation

enum PingService {
    static func sweep(_ ips: [String]) {
        let group = DispatchGroup()
        let lock = NSLock()
        var pending = 0
        for ip in ips {
            if ScanCancellation.shared.isCancelled { break }
            group.enter()
            lock.lock()
            pending += 1
            let shouldWait = pending >= 24
            lock.unlock()
            DispatchQueue.global(qos: .utility).async {
                _ = ShellRunner.run("/sbin/ping", ["-c", "1", "-W", "120", ip])
                group.leave()
            }
            if shouldWait {
                group.wait()
                lock.lock()
                pending = 0
                lock.unlock()
            }
        }
        group.wait()
    }

    static func stats(target: String, label: String, count: UInt8 = 2) -> PingStats {
        let output = ShellRunner.run("/sbin/ping", ["-c", "\(count)", "-W", "250", "-i", "0.2", target]) ?? ""
        var avg = 0.0, minV = 0.0, maxV = 0.0, loss = 100.0
        for line in output.split(separator: "\n") {
            let row = String(line)
            if row.contains("round-trip") || row.contains("avg") {
                let nums = row.split(whereSeparator: { !"0123456789./".contains($0) })
                    .compactMap { Double($0) }
                if nums.count >= 3 {
                    minV = nums[0]; avg = nums[1]; maxV = nums[2]
                }
            }
            if row.contains("packet loss"), let pct = row.split(separator: "%").first?.split(separator: " ").last,
               let value = Double(pct) {
                loss = value
            }
        }
        let jitter = max(0, maxV - minV)
        let status: PingQuality = loss >= 100 ? .down : (loss > 5 || avg > 80 ? .bad : (loss > 1 || avg > 30 ? .warning : .good))
        return PingStats(target: target, label: label, avgMs: avg, minMs: minV, maxMs: maxV, jitterMs: jitter, packetLoss: loss, status: status)
    }
}
