import Foundation
import SwiftData

/// One scheduled reminder slot and how the user answered it (or that it was missed).
@Model
final class ReminderEvent {
    var scheduledAt: Date
    var response: ResponseType
    var personName: String    // denormalized display label (spec)
    var createdAt: Date

    init(scheduledAt: Date, response: ResponseType, personName: String = "You") {
        self.scheduledAt = scheduledAt
        self.response = response
        self.personName = personName
        self.createdAt = Date()
    }
}
