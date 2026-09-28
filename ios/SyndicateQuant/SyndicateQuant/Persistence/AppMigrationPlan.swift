import SwiftData

/// Persistence contract for OverBet 6.0 foundation. Persisted model changes
/// must be versioned explicitly instead of relying on implicit store mutation.
enum AppMigrationPlan {
  static let currentVersion = 1
}
