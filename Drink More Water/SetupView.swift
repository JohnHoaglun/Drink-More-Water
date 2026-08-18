import SwiftUI
import SwiftData
import AVFoundation
import Combine

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
        showSaved = true

        Task {
            let store = HydrationEventStore(modelContainer: modelContainer)
            // Mark every past slot as missed so the Home page shows the
            // countdown immediately instead of stale Drink/Ignore buttons.
            await store.backfillMissed(settings: settings, lookback: .hours(24), forceAll: true)
            NotificationScheduler(modelContainer: modelContainer).reschedule(settings: settings)
        }
    }
}

private struct SetupForm: View {
    @Bindable var settings: AppSettings
    var onSaved: () -> Void

    @State private var startDate: Date
    @State private var endDate: Date
    @State private var invalidRange = false

    @State private var selectedSound: String
    @State private var colorSchemeOverride: String?
    @State private var colorSchemeSelection: ColorSchemeOption

    enum ColorSchemeOption: String, CaseIterable, Identifiable {
        case system
        case light
        case dark
        var id: String { rawValue }
        var label: String {
            switch self {
            case .system: return "Follow System"
            case .light: return "Light"
            case .dark: return "Dark"
            }
        }
    }

    private static let systemTones: [String] = [
        "default",
        "sms-received1.caf",
        "sms-received2.caf",
        "sms-received3.caf",
        "sms-received4.caf",
        "sms-received5.caf",
        "sms-received6.caf"
    ]
    
    private static let toneIDs: [String: SystemSoundID] = [
        "default": 1007,
        "sms-received1.caf": 1007,
        "sms-received2.caf": 1016,
        "sms-received3.caf": 1022,
        "sms-received4.caf": 1023,
        "sms-received5.caf": 1024,
        "sms-received6.caf": 1025
    ]

    private func playPreview() {
        guard settings.isAudible else { return }
        let id = Self.toneIDs[selectedSound] ?? 1007
        AudioServicesPlaySystemSound(id)
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
        _colorSchemeOverride = State(initialValue: settings.colorSchemeOverride)
        let initialSelection: ColorSchemeOption = {
            switch settings.colorSchemeOverride {
            case "light": return .light
            case "dark": return .dark
            default: return .system
            }
        }()
        _colorSchemeSelection = State(initialValue: initialSelection)
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
                Stepper(value: $settings.intervalMinutes, in: 10...600, step: 5) {
                    Text("Every \(settings.intervalMinutes) minutes")
                }
            }

            Section("Alerts") {
                Toggle("Audible alerts", isOn: $settings.isAudible)
                Picker("Tone", selection: $selectedSound) {
                    ForEach(Self.systemTones, id: \.self) { tone in
                        Text(tone == "default" ? "Default" : tone).tag(tone)
                    }
                }
                .disabled(!settings.isAudible)
                .onChange(of: selectedSound) {
                    playPreview()
                }
            }

            Section("Appearance") {
                Picker("Color Scheme", selection: $colorSchemeSelection) {
                    ForEach(ColorSchemeOption.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
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
        switch colorSchemeSelection {
        case .system: settings.colorSchemeOverride = nil
        case .light:  settings.colorSchemeOverride = "light"
        case .dark:   settings.colorSchemeOverride = "dark"
        }
        NotificationCenter.default.post(name: .colorSchemeOverrideDidChange, object: nil)

        invalidRange = false
        onSaved()
    }
}

extension Notification.Name {
    static let colorSchemeOverrideDidChange = Notification.Name("ColorSchemeOverrideDidChange")
}
