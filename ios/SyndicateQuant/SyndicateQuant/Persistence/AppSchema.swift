import SwiftData

enum AppSchema {
  static let models: [any PersistentModel.Type] = [
    JournalEntry.self,
    CalibrationSample.self,
    BacktestRun.self,
    BacktestSnapshot.self,
    TeamRating.self,
    HistoricalMarketCache.self,
    LineSnapshot.self,
    TuningConfig.self,
    TuningEvent.self
  ]
}
