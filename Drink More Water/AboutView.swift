import SwiftUI
import SwiftData

/// Spec: "About screen" + "clear all history" + "export history as CSV ...
/// using the native iOS share sheet."
struct AboutView: View {
    let modelContainer: ModelContainer
    @Query private var events: [ReminderEvent]
    @Query private var settings: [AppSettings]

    @State private var showClearConfirmation = false
    @State private var showCleared = false

    private var csv: HydrationCSV {
        HydrationCSV(text: CSVExporter.csv(for: events))
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: "waterbottle")
                        .font(.largeTitle)
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading) {
                        Text("Drink More Water")
                            .font(.headline)
                        Text("Version \(appVersion)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text("Author: john@hoaglun.com")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Data") {
                LabeledContent("Reminders recorded", value: "\(events.count)")

                NavigationLink {
                    Text("Your name appears here")
                } label: {
                    LabeledContent("Display name", value: settings.first?.personName ?? "You")
                }
                .disabled(true)

                ShareLink(
                    item: csv,
                    preview: SharePreview("hydration-history.csv", image: Image(systemName: "waterbottle"))
                ) {
                    Label("Export history (CSV)", systemImage: "square.and.arrow.up")
                }
            }

            Section {
                Label("Open the Watch app on iPhone", systemImage: "applewatch")
                Label("Go to Notifications > Drink More Water", systemImage: "bell")
                Label("Turn off mirroring to hear custom sounds on iPhone", systemImage: "speaker.wave.2")
            } header: {
                Text("Apple Watch Notifications")
            } footer: {
                Text("Apple Watch can receive mirrored iPhone reminders while the phone is locked. In that case, watchOS may use its default alert sound instead of the custom iPhone tone.")
            }

            Section {
                Button(role: .destructive) {
                    showClearConfirmation = true
                } label: {
                    Label("Clear all history", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
            } footer: {
                Text("Deletes every drink/ignore/missed record. This cannot be undone.")
            }
        }
        .navigationTitle("About")
        .alert("Clear all history?", isPresented: $showClearConfirmation) {
            Button("Keep history", role: .cancel) { }
            Button("Delete \(events.count) records", role: .destructive) {
                clearHistory()
            }
        } message: {
            Text("This permanently removes all tracking data.")
        }
        .alert("History cleared", isPresented: $showCleared) {
            Button("OK", role: .cancel) { }
        }
    }

    private func clearHistory() {
        Task {
            await HydrationEventStore(modelContainer: modelContainer).clearAllHistory()
            showCleared = true
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
