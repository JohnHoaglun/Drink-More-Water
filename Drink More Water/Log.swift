import Foundation

enum Log {
    static func error(_ message: String) {
        print("🔴 [Error] \(message)")
    }

    static func info(_ message: String) {
        print("ℹ️  [Info] \(message)")
    }
}
