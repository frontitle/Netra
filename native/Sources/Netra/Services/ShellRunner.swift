import Foundation

enum ShellRunner {
    static func run(_ executable: String, _ args: [String] = []) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    static func runLines(_ executable: String, _ args: [String] = []) -> [String] {
        guard let output = run(executable, args) else { return [] }
        return output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }
}

final class ScanCancellation {
    static let shared = ScanCancellation()
    private let lock = NSLock()
    private var cancelled = false

    func reset() {
        lock.lock()
        cancelled = false
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}
