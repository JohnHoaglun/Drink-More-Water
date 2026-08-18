import Foundation
import SwiftUI
import SwiftData
import Combine

final class AppearanceController: ObservableObject {
    @Published var scheme: ColorScheme? = nil

    private var context: ModelContext?
    private var observation: Task<Void, Never>?

    init(modelContainer: ModelContainer) {
        self.context = ModelContext(modelContainer)
        startObserving()
    }

    deinit {
        observation?.cancel()
    }

    private func startObserving() {
        observation = Task { [weak self] in
            guard let self else { return }
            let descriptor = FetchDescriptor<AppSettings>()
            var lastOverride: String? = nil
            while !Task.isCancelled {
                let settings = (try? context?.fetch(descriptor)) ?? []
                let override = settings.first?.colorSchemeOverride
                if override != lastOverride {
                    DispatchQueue.main.async {
                        switch override {
                        case "light": self.scheme = .light
                        case "dark": self.scheme = .dark
                        default: self.scheme = nil
                        }
                    }
                    lastOverride = override
                }
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms polling for immediate feedback
            }
        }
    }
}
