import SwiftUI
import SwiftData
import UserNotifications
import UIKit

/// Spec: "an onboarding/first-run flow requesting notification permission,
/// plus handling for the case where the user denies it."
struct OnboardingView: View {
    let modelContainer: ModelContainer
    var onFinish: () -> Void

    @State private var status: UNAuthorizationStatus = .notDetermined
    @State private var promptShown = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "waterbottle")
                .font(.system(size: 96))
                .foregroundStyle(.blue)

            Text("Drink More Water")
                .font(.largeTitle.weight(.bold))

            Text("Get a reminder to drink water every few minutes, between your morning and evening hours. Answer with Drink or Ignore — right from the notification.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            permissionCard

            Spacer()

            Button {
                onFinish()
            } label: {
                Text("Get started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .task {
            await refreshStatus()
        }
    }

    // MARK: Permission

    @ViewBuilder
    private var permissionCard: some View {
        switch status {
        case .authorized, .provisional:
            Label("Reminders are on", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)
        case .denied:
            VStack(spacing: 8) {
                Label("Reminders are off", systemImage: "xmark.octagon")
                    .font(.headline)
                    .foregroundStyle(.red)
                Text("You turned notifications off. You can still use the app, but reminders won't appear.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Open Settings") {
                    openAppSettings()
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .frame(maxWidth: 320)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 16))
        default:
            Group {
                if promptShown {
                    Button {
                        openAppSettings()
                    } label: {
                        Label("Enable notifications in Settings", systemImage: "gearshape.fill")
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        Task {
                            await requestPermission()
                        }
                    } label: {
                        Label("Enable reminders", systemImage: "bell.badge")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                }
            }
            .padding(.horizontal, 32)
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func requestPermission() async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        promptShown = true
        await refreshStatus()
    }

    private func refreshStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        status = settings.authorizationStatus
    }
}
