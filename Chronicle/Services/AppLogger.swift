import Foundation

enum AppLogger {
    private static let launchDate = Date()

    static func log(_ message: String) {
        let elapsed = Date().timeIntervalSince(launchDate)
        let mins = Int(elapsed) / 60
        let secs = elapsed - Double(mins * 60)
        print("[\(String(format: "%02d:%05.2f", mins, secs))] \(message)")
    }
}
