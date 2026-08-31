import Foundation
import SwiftData

// MARK: - UserDefaults backup

/// Mirrors AppSettings to UserDefaults so settings survive a SwiftData store wipe.
enum AppSettingsBackup {
    private static let prefix = "AppSettings."

    static func save(_ s: AppSettings) {
        let ud = UserDefaults.standard
        ud.set(s.startHour,         forKey: prefix + "startHour")
        ud.set(s.startMinute,       forKey: prefix + "startMinute")
        ud.set(s.endHour,           forKey: prefix + "endHour")
        ud.set(s.endMinute,         forKey: prefix + "endMinute")
        ud.set(s.intervalMinutes,   forKey: prefix + "intervalMinutes")
        ud.set(s.isAudible,         forKey: prefix + "isAudible")
        ud.set(s.soundName,         forKey: prefix + "soundName")
        ud.set(s.personName,        forKey: prefix + "personName")
        ud.set(s.hasCompletedSetup, forKey: prefix + "hasCompletedSetup")
        Log.info("Settings backed up to UserDefaults (sound=\(s.soundName), audible=\(s.isAudible))", category: .settings)
    }

    static var hasBackup: Bool {
        UserDefaults.standard.object(forKey: prefix + "hasCompletedSetup") != nil
    }

    static func restore(into s: AppSettings) {
        let ud = UserDefaults.standard
        s.startHour         = ud.integer(forKey: prefix + "startHour")
        s.startMinute       = ud.integer(forKey: prefix + "startMinute")
        s.endHour           = ud.integer(forKey: prefix + "endHour")
        s.endMinute         = ud.integer(forKey: prefix + "endMinute")
        s.intervalMinutes   = ud.integer(forKey: prefix + "intervalMinutes")
        s.isAudible         = ud.bool(forKey: prefix + "isAudible")
        s.soundName         = ud.string(forKey: prefix + "soundName") ?? "default"
        s.personName        = ud.string(forKey: prefix + "personName") ?? "You"
        s.hasCompletedSetup = ud.bool(forKey: prefix + "hasCompletedSetup")
        Log.info("Settings restored from UserDefaults backup (sound=\(s.soundName), audible=\(s.isAudible))", category: .settings)
    }
}

// MARK: - AppSettings model

/// Singleton-ish settings record (the app upserts one row).
@Model
final class AppSettings {
    @Attribute(.unique) var id: UUID
    var startHour: Int
    var startMinute: Int
    var endHour: Int
    var endMinute: Int
    var intervalMinutes: Int   // (B) — minutes between drinks
    var isAudible: Bool
    var soundName: String      // reserved for v2 custom sounds; v1 uses system default
    var personName: String     // display label for stats
    var hasCompletedSetup: Bool // true only after the user saves in Setup
    var createdAt: Date

    init(
        startHour: Int = 8, startMinute: Int = 0,
        endHour: Int = 21, endMinute: Int = 0,
        intervalMinutes: Int = 15,
        isAudible: Bool = true,
        soundName: String = "default",
        personName: String = "You"
    ) {
        self.id = UUID()
        self.startHour = startHour
        self.startMinute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
        self.intervalMinutes = intervalMinutes
        self.isAudible = isAudible
        self.soundName = soundName
        self.personName = personName
        self.hasCompletedSetup = false
        self.createdAt = Date()
    }
}
