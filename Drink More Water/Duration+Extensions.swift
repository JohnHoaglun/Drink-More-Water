import Foundation

extension Duration {
    /// Convenience for the app's daily backfill window.
    static func hours(_ value: Double) -> Duration {
        .seconds(Int64(value * 3600))
    }
}
