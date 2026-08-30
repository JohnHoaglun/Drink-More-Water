import Foundation

// MARK: - Log Entry

struct LogEntry: Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let severity: LogSeverity
    let category: LogCategory
    let message: String
    let file: String
    let line: Int
}

// MARK: - Log Levels

enum LogSeverity: String, Sendable {
    case debug = "DEBUG"
    case info  = "INFO"
    case warn  = "WARN"
    case error = "ERROR"
}

// MARK: - Log Categories

enum LogCategory: String, Sendable {
    case notification = "NOTIF"
    case scheduler    = "SCHED"
    case sound        = "SOUND"
    case ui           = "UI"
    case event        = "EVENT"
    case app          = "APP"
    case settings     = "SETTINGS"
    case interaction  = "INTERACT"
    case timing       = "TIMING"
}

// MARK: - Log

enum Log {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    private static let bufferLock = NSLock()
    private static var _entries: [LogEntry] = []
    static let maxEntries = 500

    /// Thread-safe snapshot of recent entries — suitable for UI display or export.
    static var entries: [LogEntry] {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        return _entries
    }

    static func clearEntries() {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        _entries.removeAll()
    }

    static func timestamp() -> String {
        formatter.string(from: Date())
    }

    static func log(
        severity: LogSeverity,
        category: LogCategory,
        message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        let now = Date()
        let filename = (file as NSString).lastPathComponent
        let entry = LogEntry(
            id: UUID(),
            timestamp: now,
            severity: severity,
            category: category,
            message: message,
            file: filename,
            line: line
        )

        bufferLock.lock()
        _entries.append(entry)
        if _entries.count > maxEntries {
            _entries.removeFirst(_entries.count - maxEntries)
        }
        bufferLock.unlock()

        let prefix   = "[\(formatter.string(from: now))] [\(severity.rawValue)] [\(category.rawValue)]"
        let location = "\(filename):\(line) (\(function))"
        print("\(prefix) \(message) <-- \(location)")
    }

    static func debug(_ message: String, category: LogCategory = .app, file: String = #file, function: String = #function, line: Int = #line) {
        log(severity: .debug, category: category, message: message, file: file, function: function, line: line)
    }

    static func info(_ message: String, category: LogCategory = .app, file: String = #file, function: String = #function, line: Int = #line) {
        log(severity: .info, category: category, message: message, file: file, function: function, line: line)
    }

    static func warn(_ message: String, category: LogCategory = .app, file: String = #file, function: String = #function, line: Int = #line) {
        log(severity: .warn, category: category, message: message, file: file, function: function, line: line)
    }

    static func error(_ message: String, category: LogCategory = .app, file: String = #file, function: String = #function, line: Int = #line) {
        log(severity: .error, category: category, message: message, file: file, function: function, line: line)
    }
}
