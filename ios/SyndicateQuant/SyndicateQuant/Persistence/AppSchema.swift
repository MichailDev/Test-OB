import SwiftData

/// Current persistent business schema.
///
/// HistoricalMarketCache is deliberately excluded: it is derived/cache data and
/// now lives in an Application Support disk store. Its old SwiftData entity is
/// retained only as a migration source in AppSchemaV1.
enum AppSchema {
  static let version = Schema.Version(6, 2, 0)

  static let models: [any PersistentModel.Type] = [
    JournalEntry.self,
    CalibrationSample.self,
    BacktestRun.self,
    BacktestSnapshot.self,
    TeamRating.self,
    LineSnapshot.self,
    TuningConfig.self,
    TuningEvent.self,
    ForecastSnapshot.self
  ]

  static let schema = Schema(models, version: version)
}
