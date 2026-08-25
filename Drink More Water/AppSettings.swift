import Foundation
import SwiftData

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
