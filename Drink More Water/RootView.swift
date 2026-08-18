import SwiftUI
import SwiftData

/// Host for the app's screens: TabView with Main / Stats / Setup / About,
/// gated behind the first-run onboarding flow.
struct RootView: View {
    let modelContainer: ModelContainer
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

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
