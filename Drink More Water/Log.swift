import Foundation
import os

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
    /// OSLog subsystem — matches the app's bundle ID so `log stream` can filter by it.
    static let subsystem = Bundle.main.bundleIdentifier ?? "DrinkMoreWater"

    /// iCloud container — must match the entitlement added in Signing & Capabilities.
    static let iCloudContainerID = "iCloud.Hoaglun.com.Drink-More-Water"

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    // MARK: Verbose gate

    /// When false, debug and info messages are suppressed everywhere (file, OSLog, buffer).
    /// warn and error always log. Controlled by the Debug Logging toggle in Setup.
    static var isVerboseEnabled: Bool = false

    // MARK: In-memory buffer

    private static let bufferLock = NSLock()
    private static var _entries: [LogEntry] = []
    static let maxEntries = 500

    static var entries: [LogEntry] {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        return _entries
    }

    // MARK: File handles

    private static let fileLock = NSLock()
    private static var _localHandle: FileHandle?   // local Documents — persistent handle, no iCloud replacement
    private static var _cloudLogURL: URL?           // iCloud — URL only; opened fresh per write to survive atomic replacement

    // MARK: Setup

    /// Call once from app init. Sets up local file immediately, then iCloud on a background thread.
    static func setup() {
        isVerboseEnabled = UserDefaults.standard.bool(forKey: "AppSettings.isDebugLoggingEnabled")
        _localHandle = openHandle(at: localLogURL(), label: "Local")

        // iCloud resolution must happen off the main thread — it can block.
        DispatchQueue.global(qos: .utility).async {
            guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: iCloudContainerID) else {
                print("[Log] iCloud container '\(iCloudContainerID)' not available — add iCloud Documents capability in Xcode.")
                return
            }
            let docsURL = containerURL.appendingPathComponent("Documents")
            try? FileManager.default.createDirectory(at: docsURL, withIntermediateDirectories: true)
            let logURL = docsURL.appendingPathComponent("app_debug.log")
            trimFile(at: logURL)

            // Write session separator once.
            let sep = "\n\n=== Session \(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)) ===\n"
            appendToFile(at: logURL, string: sep)
            print("[Log] iCloud file: \(logURL.path)")

            fileLock.lock()
            _cloudLogURL = logURL
            fileLock.unlock()

            // Flush any entries that were logged before iCloud was ready.
            let pending = entries
            if !pending.isEmpty {
                let block = pending.map({ formatLine($0) }).joined()
                appendToFile(at: logURL, string: block)
            }
        }
    }

    /// Opens the file at `url` by PATH (not inode) on every call so writes survive iCloud atomic replacement.
    private static func appendToFile(at url: URL, string: String) {
        guard let data = string.data(using: .utf8) else { return }
        if let h = FileHandle(forWritingAtPath: url.path) {
            h.seekToEndOfFile()
            h.write(data)
            h.closeFile()
        }
    }

    private static func localLogURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let url  = docs.appendingPathComponent("app_debug.log")
        trimFile(at: url)
        return url
    }

    private static func trimFile(at url: URL) {
        let maxBytes = 200 * 1024
        if let existing = try? Data(contentsOf: url), existing.count > maxBytes {
            try? existing.suffix(maxBytes).write(to: url, options: .atomic)
        }
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
    }

    private static func openHandle(at url: URL, label: String) -> FileHandle? {
        let h = try? FileHandle(forWritingTo: url)
        h?.seekToEndOfFile()
        let sep = "\n\n=== Session \(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)) ===\n"
        if let d = sep.data(using: .utf8) { h?.write(d) }
        print("[Log] \(label) file: \(url.path)")
        return h
    }

    private static func formatLine(_ entry: LogEntry) -> String {
        let ts = formatter.string(from: entry.timestamp)
        return "[\(ts)] [\(entry.severity.rawValue)] [\(entry.category.rawValue)] \(entry.message) <-- \(entry.file):\(entry.line)\n"
    }

    // MARK: Clearing

    static func clearEntries() {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        _entries.removeAll()
    }

    // MARK: Core

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
        // Suppress debug/info when verbose logging is disabled; warn/error always go through.
        if severity == .debug || severity == .info {
            guard isVerboseEnabled else { return }
        }

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

        // In-memory buffer
        bufferLock.lock()
        _entries.append(entry)
        if _entries.count > maxEntries {
            _entries.removeFirst(_entries.count - maxEntries)
        }
        bufferLock.unlock()

        // OSLog — visible via `log stream` on a connected device or simulator.
        let osLog = Logger(subsystem: subsystem, category: category.rawValue)
        switch severity {
        case .debug: osLog.debug("\(message, privacy: .public)")
        case .info:  osLog.info("\(message, privacy: .public)")
        case .warn:  osLog.warning("\(message, privacy: .public)")
        case .error: osLog.error("\(message, privacy: .public)")
        }

        // File output — local always; iCloud when available.
        // Cloud writes open by path each time so they survive iCloud atomic file replacement.
        let line_str = formatLine(entry)
        fileLock.lock()
        if let data = line_str.data(using: .utf8) {
            _localHandle?.write(data)
        }
        let cloudURL = _cloudLogURL
        fileLock.unlock()
        if cloudURL != nil {
            appendToFile(at: cloudURL!, string: line_str)
        }
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
