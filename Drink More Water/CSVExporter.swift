import Foundation
import CoreTransferable
import UniformTypeIdentifiers

/// Builds CSV from `ReminderEvent` rows (spec: timestamp, response, personName).
enum CSVExporter {
    static func csv(for events: [ReminderEvent]) -> String {
        let formatter = ISO8601DateFormatter()
        let sorted = events.sorted { $0.scheduledAt < $1.scheduledAt }

        var lines = ["scheduled_at,response,person"]
        for event in sorted {
            let name = event.personName.contains(",")
                ? "\"\(event.personName)\""
                : event.personName
            lines.append(
                "\(formatter.string(from: event.scheduledAt)),\(event.response.rawValue),\(name)"
            )
        }
        return lines.joined(separator: "\n")
    }
}

/// Transferable CSV file so the share sheet offers it as a `.csv`
/// attachment (Mail can email it directly).
struct HydrationCSV: Transferable {
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { file in
            file.text.data(using: .utf8) ?? Data()
        }
        .suggestedFileName("hydration-history.csv")
    }
}
