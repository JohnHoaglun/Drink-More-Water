import Foundation

/// What the user did with a reminder. Codable so SwiftData can persist it.
enum ResponseType: String, Codable {
    case drink
    case ignore
    case missed   // written by backfillMissed, never by a notification action
}
