import Foundation
import SwiftData

struct AutoDecision: Identifiable, Hashable {
  var id: String; var title: String; var summary: String
  var detail: String; var enabled: Bool; var flagKey: String
}

struct MarketOOSReport: Codable, Hashable {
  var market: String
  var bets: Int
  var wins: Int
  var losses: Int
  var pushes: Int
  var staked: Double
  var profit: Double
  var roi: Double
  var hitRate: Double
  var avgCLV: Double
  var positiveCLVRate: Double
  var brier: Double
  var logLoss: Double
  var profitFactor: Double

  enum CodingKeys: String, CodingKey {
    case market, bets, wins, losses, pushes, staked, profit, roi, hitRate
    case avgCLV, positiveCLVRate, brier, logLoss, profitFactor
  }

  init(market: String, bets: Int, wins: Int, losses: Int, pushes: Int,
       staked: Double, profit: Double, roi: Double, hitRate: Double,
       avgCLV: Double = 0, positiveCLVRate: Double = 0, brier: Double = 0,
       logLoss: Double = 0, profitFactor: Double = 0) {
    self.market = market; self.bets = bets; self.wins = wins; self.losses = losses
    self.pushes = pushes; self.staked = staked; self.profit = profit
    self.roi = roi; self.hitRate = hitRate; self.avgCLV = avgCLV
    self.positiveCLVRate = positiveCLVRate; self.brier = brier
    self.logLoss = logLoss; self.profitFactor = profitFactor
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    market = try c.decode(String.self, forKey: .market)
    bets = try c.decode(Int.self, forKey: .bets)
    wins = try c.decode(Int.self, forKey: .wins)
    losses = try c.decode(Int.self, forKey: .losses)
    pushes = try c.decode(Int.self, forKey: .pushes)
    staked = try c.decode(Double.self, forKey: .staked)
    profit = try c.decode(Double.self, forKey: .profit)
    roi = try c.decode(Double.self, forKey: .roi)
    hitRate = try c.decode(Double.self, forKey: .hitRate)
    avgCLV = try c.decodeIfPresent(Double.self, forKey: .avgCLV) ?? 0
    positiveCLVRate = try c.decodeIfPresent(Double.self, forKey: .positiveCLVRate) ?? 0
    brier = try c.decodeIfPresent(Double.self, forKey: .brier) ?? 0
    logLoss = try c.decodeIfPresent(Double.self, forKey: .logLoss) ?? 0
    profitFactor = try c.decodeIfPresent(Double.self, forKey: .profitFactor) ?? 0
  }
}

struct OOSValidationReport: Codable, Hashable {
  var generatedAt: Date
  var totalEntries: Int
  var windowDays: Int
  var windowStart: Date?
  var byMarket: [String: MarketOOSReport]

  static let empty = OOSValidationReport(
    generatedAt: .distantPast, totalEntries: 0,
    windowDays: 0, windowStart: nil, byMarket: [:])

  func report(for market: String) -> MarketOOSReport? { byMarket[market] }
}

enum OOSBuilder {
  static func build(from journal: [JournalEntry],
                    windowDays: Int = 90) -> OOSValidationReport {
    let cutoff = Date().addingTimeInterval(-Double(max(1, windowDays)) * 86400)
    let closed = journal.filter {
      $0.status == "CLOSED"
        && $0.createdAt >= cutoff
        && ($0.result == "WIN" || $0.result == "LOSS" || $0.result == "PUSH")
    }
    guard !closed.isEmpty else {
      return OOSValidationReport(generatedAt: Date(), totalEntries: 0,
                                 windowDays: windowDays, windowStart: nil, byMarket: [:])
    }

    var byMarket: [String: MarketOOSReport] = [:]
    let grouped = Dictionary(grouping: closed, by: { $0.market })
    for (mk, list) in grouped {
      var wins = 0, losses = 0, pushes = 0
      var staked = 0.0, profit = 0.0
      var clvSum = 0.0, clvCount = 0, positiveCLV = 0
      var brierSum = 0.0, logLossSum = 0.0, calibrationCount = 0
      var grossWin = 0.0, grossLoss = 0.0
      for e in list {
        staked += e.stake
        if let p = e.profit {
          profit += p
          if p > 0 { grossWin += p }
          if p < 0 { grossLoss += abs(p) }
        }
        if let clv = e.clv {
          clvSum += clv; clvCount += 1
          if clv > 0 { positiveCLV += 1 }
        }
        switch e.result {
        case "WIN": wins += 1
        case "LOSS": losses += 1
        case "PUSH": pushes += 1
        default: break
        }
        if e.result == "WIN" || e.result == "LOSS" {
          let actual = e.result == "WIN" ? 1.0 : 0.0
          let p = min(0.999999, max(0.000001, e.probability))
          brierSum += (p - actual) * (p - actual)
          logLossSum += actual > 0.5 ? -log(p) : -log(1 - p)
          calibrationCount += 1
        }
      }
      let roi = staked > 0 ? profit / staked : 0
      let dec = wins + losses
      let hitRate = dec > 0 ? Double(wins) / Double(dec) : 0
      byMarket[mk] = MarketOOSReport(
        market: mk, bets: list.count, wins: wins, losses: losses, pushes: pushes,
        staked: staked, profit: profit, roi: roi, hitRate: hitRate,
        avgCLV: clvCount > 0 ? clvSum / Double(clvCount) : 0,
        positiveCLVRate: clvCount > 0 ? Double(positiveCLV) / Double(clvCount) : 0,
        brier: calibrationCount > 0 ? brierSum / Double(calibrationCount) : 0,
        logLoss: calibrationCount > 0 ? logLossSum / Double(calibrationCount) : 0,
        profitFactor: grossLoss > 0 ? grossWin / grossLoss : (grossWin > 0 ? 999 : 0))
    }
    return OOSValidationReport(
      generatedAt: Date(),
      totalEntries: closed.count,
      windowDays: windowDays,
      windowStart: closed.map { $0.createdAt }.min(),
      byMarket: byMarket)
  }

  static func blockedMarkets(report: OOSValidationReport,
                             cfg: TuningConfig) -> Set<String> {
    guard cfg.oosGateEnabled else { return [] }
    var out: Set<String> = []
    for (mk, r) in report.byMarket where r.bets >= cfg.oosMinBets {
      let threshold: Double
      switch mk {
      case "CORNERS": threshold = cfg.cornersOOSMinROI
      case "CARDS":   threshold = cfg.cardsOOSMinROI
      default:        threshold = cfg.goalsOOSMinROI
      }
      if r.roi < threshold { out.insert(mk) }
    }
    return out
  }
}

enum VolatilityState: Equatable {
  case normal, cap(Double), pause
  var label: String {
    switch self {
    case .normal: return "NORMAL"
    case .cap(let v): return String(format: "CAP %.1f%%", v * 100)
    case .pause: return "PAUSE"
    }
  }
  var isPause: Bool { if case .pause = self { return true }; return false }
  var capValue: Double? { if case .cap(let v) = self { return v }; return nil }
}

enum VolatilityStop {
  static let defaultCapThreshold = 4
  static let defaultPauseThreshold = 7
  static let defaultCapValue = 0.05

  static func evaluate(_ journal: [JournalEntry],
                       capThreshold: Int = defaultCapThreshold,
                       pauseThreshold: Int = defaultPauseThreshold,
                       capValue: Double = defaultCapValue)
    -> (streak: Int, state: VolatilityState) {
    let sorted = journal
      .filter { $0.status == "CLOSED" }
      .sorted { $0.createdAt > $1.createdAt }
    var streak = 0
    for e in sorted {
      guard let r = e.result else { continue }
      if r == "VOID" || r == "PUSH" { continue }
      if r == "LOSS" { streak += 1; continue }
      break
    }
    if streak >= pauseThreshold { return (streak, .pause) }
    if streak >= capThreshold { return (streak, .cap(capValue)) }
    return (streak, .normal)
  }
}

struct CorrelationMatrix: Codable, Hashable {
  var marketPairs: [String: Double]
  var leaguePairs: [String: Double]
  var marketPairsN: [String: Int]
  var leaguePairsN: [String: Int]
  var totalPairs: Int
  var lastUpdated: Date
  static let empty = CorrelationMatrix(
    marketPairs: [:], leaguePairs: [:],
    marketPairsN: [:], leaguePairsN: [:],
    totalPairs: 0, lastUpdated: Date.distantPast)
}

enum CorrelationBuilder {
  static let minPairs = 20
  static func build(from journal: [JournalEntry]) -> CorrelationMatrix {
    let closed = journal.filter {
      $0.status == "CLOSED" && ($0.result == "WIN" || $0.result == "LOSS")
    }
    guard closed.count >= minPairs else { return .empty }

    let cal = Calendar(identifier: .gregorian)
    let byDay = Dictionary(grouping: closed) { cal.startOfDay(for: $0.createdAt) }

    var marketSum: [String: (both: Double, a: Double, b: Double, n: Int)] = [:]
    var leagueSum: [String: (both: Double, a: Double, b: Double, n: Int)] = [:]
    var totalPairs = 0

    for (_, entries) in byDay where entries.count >= 2 {
      for i in 0..<entries.count {
        for j in (i+1)..<entries.count {
          let ea = entries[i]; let eb = entries[j]
          if ea.gameID == eb.gameID { continue }
          let aW = ea.result == "WIN" ? 1.0 : 0.0
          let bW = eb.result == "WIN" ? 1.0 : 0.0

          let mk = [ea.market, eb.market].sorted().joined(separator: "|")
          var m = marketSum[mk] ?? (0, 0, 0, 0)
          m.both += aW * bW; m.a += aW; m.b += bW; m.n += 1
          marketSum[mk] = m

          let lk = [ea.league, eb.league].sorted().joined(separator: "|")
          var l = leagueSum[lk] ?? (0, 0, 0, 0)
          l.both += aW * bW; l.a += aW; l.b += bW; l.n += 1
          leagueSum[lk] = l

          totalPairs += 1
        }
      }
    }

    func toCorr(_ s: [String: (both: Double, a: Double, b: Double, n: Int)])
      -> ([String: Double], [String: Int]) {
      var corr: [String: Double] = [:]; var ns: [String: Int] = [:]
      for (k, v) in s where v.n >= minPairs {
        let n = Double(v.n)
        let pAB = v.both / n; let pA = v.a / n; let pB = v.b / n
        let denom = sqrt(pA * (1 - pA) * pB * (1 - pB))
        let phi = denom > 1e-9 ? (pAB - pA * pB) / denom : 0
        corr[k] = max(-1, min(1, phi)); ns[k] = v.n
      }
      return (corr, ns)
    }

    let (mc, mn) = toCorr(marketSum)
    let (lc, ln) = toCorr(leagueSum)

    return CorrelationMatrix(marketPairs: mc, leaguePairs: lc,
                             marketPairsN: mn, leaguePairsN: ln,
                             totalPairs: totalPairs, lastUpdated: Date())
  }
}
