import SwiftUI
import SwiftData
import AVFoundation
import AudioToolbox

/// Spec: "Setup screen" — start/end time, interval, sound, name.
struct SetupView: View {
    let modelContainer: ModelContainer
    @Environment(\.modelContext) private var context
    @State private var settings: AppSettings?
    @State private var showSaved = false

    var body: some View {
        Group {
            if let settings {
                SetupForm(settings: settings) {
                    save(settings)
                }
            } else {
                ProgressView("Loading…")
            }
        }
        .navigationTitle("Setup")
        .task {
            if settings == nil {
                var descriptor = FetchDescriptor<AppSettings>()
                descriptor.fetchLimit = 1
                if let existing = try? context.fetch(descriptor).first {
                    settings = existing
                } else {
                    let newSettings = AppSettings()
                    context.insert(newSettings)
                    try? context.save()
                    settings = newSettings
                }
            }
        }
        .alert("Schedule updated", isPresented: $showSaved) {
            Button("OK", role: .cancel) { }
        }
    }

    private func save(_ settings: AppSettings) {
        settings.hasCompletedSetup = true
        try? context.save()
        AppSettingsBackup.save(settings)
        showSaved = true

        Task {
            NotificationScheduler(modelContainer: modelContainer).reschedule(settings: settings)
        }
    }
}

// MARK: - Sound options

/// A tone the user can pick. `id` is the filename in the app bundle;
/// `"default"` maps to `UNNotificationSound.default`.
struct SoundOption: Identifiable, Hashable {
    let id: String
    let label: String

    static let all: [SoundOption] = [
        SoundOption(id: "default",     label: "Default"),
        SoundOption(id: "Drink1.caf",  label: "Drink 1"),
        SoundOption(id: "Drink2.caf",  label: "Drink 2"),
        SoundOption(id: "Drink3.caf",  label: "Drink 3"),
        SoundOption(id: "Drink4.caf",  label: "Drink 4"),
        SoundOption(id: "Drum1.caf",   label: "Drum 1"),
        SoundOption(id: "Drum2.caf",   label: "Drum 2"),
        SoundOption(id: "Drum3.caf",   label: "Drum 3"),
    ]

    static func match(_ id: String) -> SoundOption {
        all.first { $0.id == id } ?? all[0]
    }
}

// MARK: - Form

private struct SetupForm: View {
    @Bindable var settings: AppSettings
    var onSaved: () -> Void

    @State private var startDate: Date
    @State private var endDate: Date
    @State private var invalidRange = false

    @State private var selectedSound: String

    private func playPreview() {
        guard settings.isAudible else { return }
        NotificationSoundPlayer.shared.stop()

        if selectedSound == "default" {
            AudioServicesPlaySystemSound(1007)
            return
        }

        NotificationSoundPlayer.shared.play(selectedSound)
    }


    init(settings: AppSettings, onSaved: @escaping () -> Void) {
        self.settings = settings
        self.onSaved = onSaved
        let calendar = Calendar.current
        _startDate = State(initialValue: calendar.date(
            bySettingHour: settings.startHour, minute: settings.startMinute,
            second: 0, of: .now) ?? .now)
        _endDate = State(initialValue: calendar.date(
            bySettingHour: settings.endHour, minute: settings.endMinute,
            second: 0, of: .now) ?? .now)
        _selectedSound = State(initialValue: settings.soundName)
    }

    var body: some View {
        Form {
            Section("Name") {
                TextField("Display name", text: $settings.personName)
            }

            Section("Schedule") {
                DatePicker("First reminder",
                           selection: $startDate,
                           displayedComponents: .hourAndMinute)
                DatePicker("Last reminder",
                           selection: $endDate,
                           displayedComponents: .hourAndMinute)
                Stepper(value: $settings.intervalMinutes, in: 5...600, step: 5) {
                    Text("Every \(settings.intervalMinutes) minutes")
                }
            }

            Section("Alerts") {
                Toggle("Audible alerts", isOn: $settings.isAudible)
                Picker("Tone", selection: $selectedSound) {
                    ForEach(SoundOption.all) { option in
                        Text(option.label).tag(option.id)
                    }
                }
                .disabled(!settings.isAudible)
                .onChange(of: selectedSound) {
                    playPreview()
                }
            }

            if invalidRange {
                Section {
                    Text("The last reminder must be after the first one.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
            }
        }
    }

    private func save() {
        guard startDate < endDate else {
            invalidRange = true
            return
        }
        let calendar = Calendar.current
        let start = calendar.dateComponents([.hour, .minute], from: startDate)
        let end = calendar.dateComponents([.hour, .minute], from: endDate)

        settings.startHour = start.hour ?? settings.startHour
        settings.startMinute = start.minute ?? settings.startMinute
        settings.endHour = end.hour ?? settings.endHour
        settings.endMinute = end.minute ?? settings.endMinute

        settings.soundName = selectedSound
        invalidRange = false
        onSaved()
    }
}
