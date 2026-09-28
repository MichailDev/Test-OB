import Foundation
import SwiftData

@Model final class JournalEntry {
  @Attribute(.unique) var id: String
  var gameID: String
  var home: String
  var away: String
  var league: String
  var market: String
  var selection: String
  var line: Double?
  var odds: Double
  var probability: Double
  var ev: Double
  var robustEV: Double
  var qcs: Double
  var dcs: Double
  var classification: String
  var stake: Double
  var status: String
  var createdAt: Date
  var result: String?
  var closingOdds: Double?
  var clv: Double?
  var profit: Double?
  var openingOdds: Double?
  var movement: Double?
  var stakeMoney: Double?
  var matchStart: Date?

  init(signal: BetSignal, status: String = "OPEN") {
    id = signal.id
    gameID = signal.gameID
    home = signal.home
    away = signal.away
    league = signal.league
    market = signal.market
    selection = signal.selection
    line = signal.line
    odds = signal.odds
    probability = signal.probability
    ev = signal.ev
    robustEV = signal.robustEV
    qcs = signal.qcs
    dcs = signal.dcs
    classification = signal.classification
    stake = signal.stake
    self.status = status
    createdAt = signal.timestamp
    result = nil
    closingOdds = nil
    clv = nil
    profit = nil
    openingOdds = signal.odds
    movement = nil
    stakeMoney = signal.stakeMoney
    matchStart = signal.startTime
  }
}

@Model final class CalibrationSample {
  @Attribute(.unique) var id: String
  var predicted: Double
  var actual: Double
  var market: String
  var createdAt: Date
  init(id: String, predicted: Double, actual: Double, market: String,
       createdAt: Date = Date()) {
    self.id = id; self.predicted = predicted; self.actual = actual
    self.market = market; self.createdAt = createdAt
  }
}
