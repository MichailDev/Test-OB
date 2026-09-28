import Foundation
import SwiftData

@Model final class TeamRating {
  @Attribute(.unique) var teamID: String
  var name: String
  var rating: Double
  var matches: Int
  var lastDelta: Double
  var updatedAt: Date

  init(teamID: String, name: String = "",
       rating: Double = 1500, matches: Int = 0) {
    self.teamID = teamID
    self.name = name
    self.rating = rating
    self.matches = matches
    self.lastDelta = 0
    self.updatedAt = Date()
  }
}

@Model final class HistoricalMarketCache {
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
  var cornersChecked: Bool
  var cardsChecked: Bool
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
    self.cornersChecked = false
    self.cardsChecked = false
    self.failedAttempts = 0
    self.lastError = nil
    self.updatedAt = Date()
  }
}

@Model final class LineSnapshot {
  @Attribute(.unique) var id: String
  var gameID: String
  var numericID: Int?
  var market: String
  var selection: String
  var line: Double?
  var startTime: Date?
  var league: String
  var home: String
  var away: String
  var takenAt: Date
  var minutesToStart: Int
  var bucketMinutes: Int
  var avgOdds: Double
  var bestOdds: Double
  var worstOdds: Double
  var booksCount: Int
  var bookmakerJSON: Data?

  init(id: String, gameID: String, numericID: Int?,
       market: String, selection: String, line: Double?,
       startTime: Date?, league: String, home: String, away: String,
       takenAt: Date, minutesToStart: Int, bucketMinutes: Int,
       avgOdds: Double, bestOdds: Double, worstOdds: Double,
       booksCount: Int, bookmakerJSON: Data?) {
    self.id = id
    self.gameID = gameID
    self.numericID = numericID
    self.market = market
    self.selection = selection
    self.line = line
    self.startTime = startTime
    self.league = league
    self.home = home
    self.away = away
    self.takenAt = takenAt
    self.minutesToStart = minutesToStart
    self.bucketMinutes = bucketMinutes
    self.avgOdds = avgOdds
    self.bestOdds = bestOdds
    self.worstOdds = worstOdds
    self.booksCount = booksCount
    self.bookmakerJSON = bookmakerJSON
  }
}

@Model final class TuningConfig {
  @Attribute(.unique) var id: String
  var autoExcludeEnabled: Bool
  var posteriorEnabled: Bool
  var stopLossEnabled: Bool
  var correlationEnabled: Bool
  var playerImpactEnabled: Bool
  var teamRatingEnabled: Bool
  var posteriorWeight: Double
  var autoExcludeMinROI: Double
  var autoExcludeMinBets: Int
  var stopLossCapStreak: Int
  var stopLossPauseStreak: Int
  var updatedAt: Date

  var cornersEnabled: Bool = true
  var cardsEnabled: Bool = true
  var cornersMinEV: Double = 0.03
  var cardsMinEV: Double = 0.03
  var cornersMinQCS: Double = 70
  var cardsMinQCS: Double = 70
  var cornersMaxStake: Double = 0.02
  var cardsMaxStake: Double = 0.02
  var cornersMinSample: Int = 5
  var cardsMinSample: Int = 5

  var goalsMinRobustEV: Double = 0.0
  var goalsMinSample: Int = 6
  var goalsMaxUncertainty: Double = 0.25

  var cornersMinRobustEV: Double = 0.0
  var cornersMinMSS: Double = 30
  var cornersMaxUncertainty: Double = 0.22

  var cardsMinRobustEV: Double = 0.0
  var cardsMinMSS: Double = 30
  var cardsMaxUncertainty: Double = 0.22

  var oosGateEnabled: Bool = false
  var oosMinBets: Int = 100
  var oosWindowDays: Int = 90
  var goalsOOSMinROI: Double = -0.03
  var cornersOOSMinROI: Double = -0.03
  var cardsOOSMinROI: Double = -0.03

  var cornersWeightRecentOwn: Double = 0.35
  var cornersWeightRecentOpp: Double = 0.25
  var cornersWeightLeague: Double = 0.15
  var cornersWeightXG: Double = 0.10
  var cornersWeightPossession: Double = 0.05
  var cornersWeightH2H: Double = 0.10

  var cardsWeightRecentOwn: Double = 0.30
  var cardsWeightRecentOpp: Double = 0.20
  var cardsWeightLeague: Double = 0.15
  var cardsWeightFouls: Double = 0.10
  var cardsWeightReferee: Double = 0.20
  var cardsWeightH2H: Double = 0.05

  init(id: String = "current") {
    self.id = id
    self.autoExcludeEnabled = true
    self.posteriorEnabled = true
    self.stopLossEnabled = true
    self.correlationEnabled = true
    self.playerImpactEnabled = true
    self.teamRatingEnabled = true
    self.posteriorWeight = 0.15
    self.autoExcludeMinROI = -0.05
    self.autoExcludeMinBets = 20
    self.stopLossCapStreak = 4
    self.stopLossPauseStreak = 7
    self.updatedAt = Date()
  }
}

@Model final class TuningEvent {
  @Attribute(.unique) var id: String
  var createdAt: Date
  var kind: String
  var target: String
  var beforeValue: String
  var afterValue: String
  var note: String
  var rolledBack: Bool

  init(id: String = UUID().uuidString, createdAt: Date = Date(),
       kind: String, target: String,
       beforeValue: String, afterValue: String,
       note: String = "", rolledBack: Bool = false) {
    self.id = id; self.createdAt = createdAt
    self.kind = kind; self.target = target
    self.beforeValue = beforeValue; self.afterValue = afterValue
    self.note = note; self.rolledBack = rolledBack
  }
}
