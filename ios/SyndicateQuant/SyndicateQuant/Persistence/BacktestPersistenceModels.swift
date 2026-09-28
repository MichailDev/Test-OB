import Foundation
import SwiftData

@Model final class BacktestSnapshot {
  @Attribute(.unique) var id: String
  var version: Int
  var builtAt: Date?
  var fromDate: Date?
  var toDate: Date?
  var totalMatches: Int
  var totalBets: Int
  var buildProgress: Double
  var buildStatus: String
  var lastError: String?
  var perLeagueJSON: Data?
  var perMarketJSON: Data?
  var perLeagueMarketJSON: Data?
  var evBucketsJSON: Data?
  var oddsBucketsJSON: Data?
  var classificationJSON: Data?
  var posteriorJSON: Data?
  var modelComparisonJSON: Data?
  var avgROI: Double
  var avgCLV: Double
  var brier: Double
  var logLoss: Double
  var sharpe: Double
  var sortino: Double
  var profitFactor: Double

  var enrichmentProgress: Int = 0
  var enrichmentTotal: Int = 0

  var posteriorCornersJSON: Data?
  var posteriorCardsJSON: Data?

  var buildCursorTimestamp: Double = 0
  var buildMatchesCount: Int = 0

  var buildJobID: String? = nil
  var historicalCacheCount: Int = 0

  var oosValidationJSON: Data? = nil

  var trainReportJSON: Data? = nil
  var validationReportJSON: Data? = nil
  var holdoutReportJSON: Data? = nil
  var walkForwardMode: String = "off"

  init(id: String = "current") {
    self.id = id; self.version = 1
    self.builtAt = nil; self.fromDate = nil; self.toDate = nil
    self.totalMatches = 0; self.totalBets = 0
    self.buildProgress = 0; self.buildStatus = "idle"; self.lastError = nil
    self.perLeagueJSON = nil; self.perMarketJSON = nil
    self.perLeagueMarketJSON = nil; self.evBucketsJSON = nil
    self.oddsBucketsJSON = nil; self.classificationJSON = nil
    self.posteriorJSON = nil; self.modelComparisonJSON = nil
    self.posteriorCornersJSON = nil; self.posteriorCardsJSON = nil
    self.avgROI = 0; self.avgCLV = 0; self.brier = 0; self.logLoss = 0
    self.sharpe = 0; self.sortino = 0; self.profitFactor = 0
  }
}

@Model final class BacktestRun {
  @Attribute(.unique) var id: String
  var createdAt: Date
  var matches: Int
  var bets: Int
  var wins: Int
  var losses: Int
  var pushes: Int
  var profit: Double
  var staked: Double
  var roi: Double
  var yieldPct: Double
  var hitRate: Double
  var maxDrawdown: Double
  var maxLosingStreak: Int
  var sharpe: Double
  var brier: Double
  var logLoss: Double
  var avgCLV: Double

  init(id: String = UUID().uuidString, createdAt: Date = Date(),
       matches: Int, bets: Int, wins: Int, losses: Int, pushes: Int,
       profit: Double, staked: Double, roi: Double, yieldPct: Double,
       hitRate: Double, maxDrawdown: Double, maxLosingStreak: Int,
       sharpe: Double, brier: Double, logLoss: Double, avgCLV: Double) {
    self.id = id; self.createdAt = createdAt
    self.matches = matches; self.bets = bets
    self.wins = wins; self.losses = losses; self.pushes = pushes
    self.profit = profit; self.staked = staked; self.roi = roi
    self.yieldPct = yieldPct; self.hitRate = hitRate
    self.maxDrawdown = maxDrawdown; self.maxLosingStreak = maxLosingStreak
    self.sharpe = sharpe; self.brier = brier
    self.logLoss = logLoss; self.avgCLV = avgCLV
  }
}
