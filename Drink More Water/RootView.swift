import SwiftUI
import SwiftData
import Combine

/// Host for the app's screens: TabView with Main / Stats / Setup / About,
/// gated behind the first-run onboarding flow.
struct RootView: View {
    let modelContainer: ModelContainer
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: AppTab = .home

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
        TabView(selection: $selectedTab) {
            NavigationStack {
                MainView(modelContainer: modelContainer)
            }
            .tag(AppTab.home)
            .tabItem {
                Label("Home", systemImage: "drop.fill")
            }

            NavigationStack {
                ReportingView(modelContainer: modelContainer)
            }
            .tag(AppTab.stats)
            .tabItem {
                Label("Stats", systemImage: "chart.bar")
            }

            NavigationStack {
                SetupView(modelContainer: modelContainer) {
                    selectedTab = .home
                }
            }
            .tag(AppTab.setup)
            .tabItem {
                Label("Setup", systemImage: "gearshape")
            }

            NavigationStack {
                AboutView(modelContainer: modelContainer)
            }
            .tag(AppTab.about)
            .tabItem {
                Label("About", systemImage: "info.circle")
            }
        }
    }
}

enum AppTab: Hashable {
    case home
    case stats
    case setup
    case about
}
