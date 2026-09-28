import Foundation
import SwiftData

/// SwiftData migration history for OverBet.
///
/// V0 = original v5.6 persistence contract.
/// V1 = 6.0 foundation: adds LineSnapshot and explicit market-check flags.
/// V2 = 6.0.1 W2: removes HistoricalMarketCache from SwiftData and migrates it
///      into a dedicated disk cache under Application Support.
/// V3 = 6.1.0 W3-W6: persists the latest daily forecast snapshot.
/// V4 = 6.2.0 W7-W11: schema contract aligned with the app release.

enum AppSchemaV0: VersionedSchema {
  static let versionIdentifier = Schema.Version(5, 6, 0)

  @Model
  final class HistoricalMarketCache {
    @Attribute(.unique) var gameID: String
    var numericID: Int
    var start: Date?
    var league: String
    var homeID: String?
    var awayID: String?
    var home: String
    var away: String
    var oddsJSON: Data?
    var enriched: Bool
    var hasCorners: Bool
    var hasCards: Bool
    var failedAttempts: Int
    var lastError: String?
    var updatedAt: Date

    init(gameID: String, numericID: Int, start: Date?, league: String,
         homeID: String?, awayID: String?, home: String, away: String) {
      self.gameID = gameID
      self.numericID = numericID
      self.start = start
      self.league = league
      self.homeID = homeID
      self.awayID = awayID
      self.home = home
      self.away = away
      self.oddsJSON = nil
      self.enriched = false
      self.hasCorners = false
      self.hasCards = false
      self.failedAttempts = 0
      self.lastError = nil
      self.updatedAt = Date()
    }
  }

  static let models: [any PersistentModel.Type] = [
    JournalEntry.self,
    CalibrationSample.self,
    BacktestRun.self,
    BacktestSnapshot.self,
    TeamRating.self,
    HistoricalMarketCache.self,
    TuningConfig.self,
    TuningEvent.self
  ]
}

enum AppSchemaV1: VersionedSchema {
  static let versionIdentifier = Schema.Version(6, 0, 0)

  @Model
  final class HistoricalMarketCache {
    @Attribute(.unique) var gameID: String
    var numericID: Int
    var start: Date?
    var league: String
    var homeID: String?
    var awayID: String?
    var home: String
    var away: String
    var oddsJSON: Data?
    var enriched: Bool
    var hasCorners: Bool
    var hasCards: Bool
    var cornersChecked: Bool = false
    var cardsChecked: Bool = false
    var failedAttempts: Int
    var lastError: String?
    var updatedAt: Date

    init(gameID: String, numericID: Int, start: Date?, league: String,
         homeID: String?, awayID: String?, home: String, away: String) {
      self.gameID = gameID
      self.numericID = numericID
      self.start = start
      self.league = league
      self.homeID = homeID
      self.awayID = awayID
      self.home = home
      self.away = away
      self.oddsJSON = nil
      self.enriched = false
      self.hasCorners = false
      self.hasCards = false
      self.failedAttempts = 0
      self.lastError = nil
      self.updatedAt = Date()
    }
  }

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

enum AppSchemaV2: VersionedSchema {
  static let versionIdentifier = Schema.Version(6, 0, 1)
  static let models: [any PersistentModel.Type] = [
    JournalEntry.self,
    CalibrationSample.self,
    BacktestRun.self,
    BacktestSnapshot.self,
    TeamRating.self,
    LineSnapshot.self,
    TuningConfig.self,
    TuningEvent.self
  ]
}

enum AppSchemaV3: VersionedSchema {
  static let versionIdentifier = Schema.Version(6, 1, 0)
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
}

enum AppSchemaV4: VersionedSchema {
  static let versionIdentifier = Schema.Version(6, 2, 0)
  static let models: [any PersistentModel.Type] = AppSchemaV3.models
}

enum AppMigrationPlan: SchemaMigrationPlan {
  static let schemas: [any VersionedSchema.Type] = [
    AppSchemaV0.self,
    AppSchemaV1.self,
    AppSchemaV2.self,
    AppSchemaV3.self,
    AppSchemaV4.self
  ]

  static let stages: [MigrationStage] = [
    .lightweight(
      fromVersion: AppSchemaV0.self,
      toVersion: AppSchemaV1.self
    ),
    .custom(
      fromVersion: AppSchemaV1.self,
      toVersion: AppSchemaV2.self,
      willMigrate: { context in
        let rows = try context.fetch(
          FetchDescriptor<AppSchemaV1.HistoricalMarketCache>(
            sortBy: [SortDescriptor(\AppSchemaV1.HistoricalMarketCache.updatedAt, order: .forward)]
          )
        )

        let records = rows.map { row in
          HistoricalMarketCacheRecord(
            gameID: row.gameID,
            numericID: row.numericID,
            start: row.start,
            league: row.league,
            homeID: row.homeID,
            awayID: row.awayID,
            home: row.home,
            away: row.away,
            oddsJSON: row.oddsJSON,
            enriched: row.enriched,
            hasCorners: row.hasCorners,
            hasCards: row.hasCards,
            cornersChecked: row.cornersChecked,
            cardsChecked: row.cardsChecked,
            failedAttempts: row.failedAttempts,
            lastError: row.lastError,
            updatedAt: row.updatedAt
          )
        }

        if !records.isEmpty {
          try HistoricalMarketCacheDiskStore.mergeAndPersist(records)
        }

        for row in rows {
          context.delete(row)
        }
        if context.hasChanges {
          try context.save()
        }
      },
      didMigrate: nil
    ),
    .lightweight(
      fromVersion: AppSchemaV2.self,
      toVersion: AppSchemaV3.self
    ),
    .lightweight(
      fromVersion: AppSchemaV3.self,
      toVersion: AppSchemaV4.self
    )
  ]
}
