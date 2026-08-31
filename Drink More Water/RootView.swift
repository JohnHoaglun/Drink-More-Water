import SwiftUI
import SwiftData
import Combine

/// Host for the app's screens: TabView with Main / Stats / Setup / About,
/// gated behind the first-run onboarding flow.
struct RootView: View {
    let modelContainer: ModelContainer
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                mainTabs
            } else {
                OnboardingView(modelContainer: modelContainer) {
                    hasCompletedOnboarding = true
                }
            }
        }
        .modelContainer(modelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .inactive {
                NotificationSoundPlayer.shared.stop()
            }
        }
    }

    private var mainTabs: some View {
        TabView {
            NavigationStack {
                MainView(modelContainer: modelContainer)
            }
            .tabItem {
                Label("Home", systemImage: "drop.fill")
            }

            NavigationStack {
                ReportingView(modelContainer: modelContainer)
            }
            .tabItem {
                Label("Stats", systemImage: "chart.bar")
            }

            NavigationStack {
                SetupView(modelContainer: modelContainer)
            }
            .tabItem {
                Label("Setup", systemImage: "gearshape")
            }

            NavigationStack {
                AboutView(modelContainer: modelContainer)
            }
            .tabItem {
                Label("About", systemImage: "info.circle")
            }
        }
    }
}
