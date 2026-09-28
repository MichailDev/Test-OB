import Foundation
import SwiftData

struct StoredSegmentStats: Codable, Hashable {
  var bets: Int; var wins: Int; var losses: Int; var pushes: Int
  var profit: Double; var staked: Double
  var roi: Double; var yieldPct: Double; var hitRate: Double; var avgOdds: Double

  init() {
    bets = 0; wins = 0; losses = 0; pushes = 0
    profit = 0; staked = 0; roi = 0; yieldPct = 0; hitRate = 0; avgOdds = 0
  }
  init(bets: Int, wins: Int, losses: Int, pushes: Int,
       profit: Double, staked: Double, avgOdds: Double) {
    self.bets = bets; self.wins = wins; self.losses = losses; self.pushes = pushes
    self.profit = profit; self.staked = staked
    self.roi = staked > 0 ? profit / staked : 0
    self.yieldPct = self.roi
    let dec = wins + losses
    self.hitRate = dec > 0 ? Double(wins) / Double(dec) : 0
    self.avgOdds = avgOdds
  }
}

struct PosteriorBucket: Codable, Hashable, Identifiable {
  var id: String { "\(probabilityLow)-\(probabilityHigh)" }
  var probabilityLow: Double
  var probabilityHigh: Double
  var n: Int
  var factHitRate: Double
}

struct AutoExcludeRule: Codable, Hashable, Identifiable {
  var id: String { "\(league)|\(market)" }
  var league: String
  var market: String
  var bets: Int
  var roi: Double
  var excluded: Bool
}

struct ModelComparison: Codable, Hashable, Identifiable {
  var id: String { name }
  var name: String
  var matches: Int
  var brier: Double
  var logLoss: Double
  var avgHomeP: Double
  var avgDrawP: Double
  var avgAwayP: Double
}

struct WalkForwardDelta: Codable, Hashable {
  var matches: Int
  var bets: Int
  var wins: Int
  var losses: Int
  var pushes: Int
  var roi: Double
  var sharpe: Double
  var sortino: Double
  var profitFactor: Double
  var brier: Double
  var logLoss: Double
  var avgCLV: Double
  var hitRate: Double
}

enum AutoExclude {
  static let defaultMinBets = 20
  static let defaultMinROI = -0.05
  static func rules(from snapshot: BacktestSnapshot?,
                    minROI: Double = defaultMinROI,
                    minBets: Int = defaultMinBets) -> [AutoExcludeRule] {
    guard let snapshot else { return [] }
    let stats = snapshot.decodedLeagueMarketStats()
    return stats.map { (key, s) in
      let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
      let lg = parts.first ?? key
      let mk = parts.count > 1 ? parts[1] : ""
      let ex = s.bets >= minBets && s.roi < minROI
      return AutoExcludeRule(league: lg, market: mk,
                             bets: s.bets, roi: s.roi, excluded: ex)
    }.sorted { $0.roi < $1.roi }
  }
  static func isExcluded(league: String, market: String,
                         rules: [AutoExcludeRule]) -> Bool {
    rules.contains { r in
      guard r.excluded else { return false }
      guard market.caseInsensitiveCompare(r.market) == .orderedSame else { return false }
      let a = league.lowercased(); let b = r.league.lowercased()
      return a == b || a.contains(b) || b.contains(a)
    }
  }
}

struct AppStats {
  var bets = 0; var wins = 0; var losses = 0; var pushes = 0
  var profit = 0.0; var staked = 0.0
}

struct JournalMetrics {
  var totalEntries = 0; var closedEntries = 0
  var wins = 0; var losses = 0; var pushes = 0; var voids = 0
  var profit = 0.0; var staked = 0.0
  var avgCLV = 0.0; var clvCount = 0
  var brier = 0.0; var logLoss = 0.0
  var calibration: [CalibrationBucket] = []

  var roi: Double { staked > 0 ? profit / staked : 0 }
  var yieldPct: Double { roi }
  var hitRate: Double {
    wins + losses > 0 ? Double(wins) / Double(wins + losses) : 0
  }
  var pending: Int { totalEntries - closedEntries }
}

struct CalibrationBucket: Identifiable {
  let id: String; let midpoint: Double
  let predicted: Double; let actual: Double; let count: Int
}


struct CalibrationSummary: Codable, Hashable {
  var samples: Int
  var brier: Double
  var logLoss: Double
  var calibrationError: Double
  var bias: Double

  static let empty = CalibrationSummary(
    samples: 0, brier: 0, logLoss: 0, calibrationError: 0, bias: 0)
}

struct MarketCLV: Codable, Hashable {
  var count: Int
  var avgCLV: Double
  var positiveRate: Double
}

struct CLVReport {
  var totalWithCLV: Int
  var positiveCount: Int
  var neutralCount: Int
  var negativeCount: Int
  var avgCLV: Double
  var medianCLV: Double
  var byMarket: [String: MarketCLV]
  var pnlPositive: Double
  var pnlNegative: Double
  var positiveRate: Double
  var verdict: String
  var note: String
}

enum MarketRegime: String {
  case normal          = "NORMAL"
  case highVolatility  = "HIGH VOL"
  case lowLiquidity    = "LOW LIQ"
  case lineDislocation = "DISLOCATION"
  case unknown         = "UNKNOWN"

  var label: String { rawValue }
}

struct MarketRegimeReport {
  var regime: MarketRegime
  var avgBooksPerMarket: Double
  var avgSpreadPct: Double
  var sharpMovements: Int
  var totalMovements: Int
  var note: String
}

struct EquityPoint: Identifiable, Hashable {
  let id: String; let date: Date
  let cumulativeProfit: Double; let cumulativeStaked: Double
  let bets: Int
}

struct BollingerPoint: Identifiable, Hashable {
  var id: String
  let date: Date
  let index: Int
  let value: Double
  let ma: Double?
  let upper: Double?
  let lower: Double?
  let isBreakout: Bool
}

struct BollingerRisk {
  enum State: String {
    case normal = "NORMAL"
    case expanding = "EXPANDING"
    case high = "HIGH"
    case risk = "RISK"
  }

  struct Report {
    var state: State
    var width: Double?
    var avgWidth: Double?
    var widthRatio: Double
    var recentBreakouts: Int
    var breakoutRate: Double
    var window: Int
    var note: String
  }

  static func evaluate(_ bands: [BollingerPoint], window: Int = 20) -> Report {
    guard bands.count >= window + 2 else {
      return Report(state: .normal, width: nil, avgWidth: nil,
                    widthRatio: 1, recentBreakouts: 0, breakoutRate: 0,
                    window: window,
                    note: "Недостаточно данных (\(bands.count)/\(window + 2))")
    }
    var widths: [Double] = []
    widths.reserveCapacity(bands.count)
    for p in bands {
      if let u = p.upper, let l = p.lower, u >= l { widths.append(u - l) }
    }
    guard widths.count >= window else {
      return Report(state: .normal, width: nil, avgWidth: nil,
                    widthRatio: 1, recentBreakouts: 0, breakoutRate: 0,
                    window: window, note: "Нет полос")
    }
    let recent = Array(widths.suffix(window))
    let currentWidth = recent.last ?? 0
    let avgWidth = recent.reduce(0, +) / Double(recent.count)
    let widthRatio = avgWidth > 0 ? currentWidth / avgWidth : 1

    let tail = Array(bands.suffix(window))
    let breakouts = tail.filter { $0.isBreakout }.count
    let breakoutRate = Double(breakouts) / Double(max(tail.count, 1))

    let state: State
    let note: String
    if widthRatio > 1.5 && breakoutRate > 0.25 {
      state = .risk
      note = "Высокая волатильность P/L и частые выходы за полосу"
    } else if widthRatio > 1.5 {
      state = .high
      note = "Полосы расширяются — волатильность P/L растёт"
    } else if breakoutRate > 0.25 {
      state = .expanding
      note = "Частые выходы за полосу при стабильной ширине"
    } else {
      state = .normal
      note = "Штатный режим волатильности"
    }
    return Report(state: state,
                  width: currentWidth, avgWidth: avgWidth,
                  widthRatio: widthRatio,
                  recentBreakouts: breakouts, breakoutRate: breakoutRate,
                  window: window, note: note)
  }
}

enum Metrics {
  static func compute(_ entries: [JournalEntry]) -> JournalMetrics {
    var m = JournalMetrics()
    m.totalEntries = entries.count
    let closed = entries.filter { $0.status == "CLOSED" }
    m.closedEntries = closed.count

    var brierSum = 0.0; var logLossSum = 0.0; var brierCount = 0
    var clvSum = 0.0; var clvCount = 0
    var bucketPredicted: [Int: Double] = [:]
    var bucketActual: [Int: Double] = [:]
    var bucketCount: [Int: Int] = [:]

    for e in closed {
      m.staked += e.stake
      if let p = e.profit { m.profit += p }
      switch e.result {
      case "WIN": m.wins += 1
      case "LOSS": m.losses += 1
      case "PUSH": m.pushes += 1
      case "VOID": m.voids += 1
      default: break
      }
      if let clv = e.clv { clvSum += clv; clvCount += 1 }
      if e.result == "WIN" || e.result == "LOSS" {
        let actual = e.result == "WIN" ? 1.0 : 0.0
        let p = e.probability
        brierSum += (p - actual) * (p - actual)
        let eps = 1e-9
        let clamped = min(1 - eps, max(eps, p))
        let ll = actual == 1 ? -log(clamped) : -log(1 - clamped)
        logLossSum += ll
        brierCount += 1
        let bucket = min(9, max(0, Int(p * 10.0)))
        bucketPredicted[bucket, default: 0] += p
        bucketActual[bucket, default: 0] += actual
        bucketCount[bucket, default: 0] += 1
      }
    }
    if clvCount > 0 { m.avgCLV = clvSum / Double(clvCount) }
    if brierCount > 0 {
      m.brier = brierSum / Double(brierCount)
      m.logLoss = logLossSum / Double(brierCount)
    }
    var buckets: [CalibrationBucket] = []
    for i in 0..<10 {
      guard let n = bucketCount[i], n > 0 else { continue }
      let avgPred = (bucketPredicted[i] ?? 0) / Double(n)
      let actual = (bucketActual[i] ?? 0) / Double(n)
      buckets.append(CalibrationBucket(id: "b\(i)",
        midpoint: Double(i) / 10.0 + 0.05,
        predicted: avgPred, actual: actual, count: n))
    }
    m.calibration = buckets
    return m
  }

  static func calibrationError(_ m: JournalMetrics) -> Double {
    guard !m.calibration.isEmpty else { return 0 }
    var weightedSum = 0.0; var totalN = 0
    for b in m.calibration {
      weightedSum += abs(b.predicted - b.actual) * Double(b.count)
      totalN += b.count
    }
    return totalN > 0 ? weightedSum / Double(totalN) : 0
  }

  static func equityCurve(_ entries: [JournalEntry],
                          bankroll: Double? = nil) -> [EquityPoint] {
    let closed = entries
      .filter { $0.status == "CLOSED" && $0.profit != nil }
      .sorted { $0.createdAt < $1.createdAt }
    guard !closed.isEmpty else { return [] }

    var curve: [EquityPoint] = []
    var cumProfit = 0.0; var cumStaked = 0.0
    let mult = bankroll ?? 1.0
    for (i, e) in closed.enumerated() {
      cumProfit += (e.profit ?? 0) * mult
      cumStaked += e.stake * mult
      curve.append(EquityPoint(id: "eq\(i)_\(e.id)", date: e.createdAt,
        cumulativeProfit: cumProfit, cumulativeStaked: cumStaked, bets: i + 1))
    }
    return curve
  }

  static func bollingerBands(
    _ curve: [EquityPoint],
    window: Int = 20,
    sigmaMultiplier: Double = 2.0
  ) -> [BollingerPoint] {
    guard curve.count >= window else { return [] }
    var out: [BollingerPoint] = []
    out.reserveCapacity(curve.count)
    for i in 0..<curve.count {
      let p = curve[i]
      if i < window - 1 {
        out.append(BollingerPoint(
          id: p.id, date: p.date, index: i,
          value: p.cumulativeProfit,
          ma: nil, upper: nil, lower: nil, isBreakout: false))
        continue
      }
      let slice = curve[(i - window + 1)...i].map { $0.cumulativeProfit }
      let mean = slice.reduce(0, +) / Double(slice.count)
      let variance = slice.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(slice.count)
      let sd = sqrt(variance)
      let upper = mean + sigmaMultiplier * sd
      let lower = mean - sigmaMultiplier * sd
      let value = p.cumulativeProfit
      let breakout = value > upper || value < lower
      out.append(BollingerPoint(
        id: p.id, date: p.date, index: i,
        value: value, ma: mean, upper: upper, lower: lower,
        isBreakout: breakout))
    }
    return out
  }

  static func calibrationSummary(_ samples: [CalibrationSample]) -> CalibrationSummary {
    guard !samples.isEmpty else { return .empty }
    let bounded = samples.map { CalibrationSampleView(
      predicted: min(0.999999, max(0.000001, $0.predicted)), actual: $0.actual) }
    let brier = bounded.reduce(0.0) { $0 + ($1.predicted - $1.actual) * ($1.predicted - $1.actual) }
      / Double(bounded.count)
    let logLoss = bounded.reduce(0.0) { sum, x in
      sum + (x.actual > 0.5 ? -log(x.predicted) : -log(1 - x.predicted))
    } / Double(bounded.count)
    var bins: [Int: (sumP: Double, sumY: Double, n: Int)] = [:]
    for x in bounded {
      let bin = min(9, max(0, Int(x.predicted * 10)))
      var b = bins[bin] ?? (0, 0, 0)
      b.sumP += x.predicted; b.sumY += x.actual; b.n += 1
      bins[bin] = b
    }
    var calErr = 0.0
    var bias = 0.0
    for b in bins.values {
      let p = b.sumP / Double(b.n)
      let y = b.sumY / Double(b.n)
      calErr += abs(p - y) * Double(b.n)
      bias += (p - y) * Double(b.n)
    }
    let n = Double(bounded.count)
    return CalibrationSummary(
      samples: bounded.count, brier: brier, logLoss: logLoss,
      calibrationError: calErr / n, bias: bias / n)
  }

  private struct CalibrationSampleView {
    let predicted: Double
    let actual: Double
  }

  static func clvReport(_ entries: [JournalEntry]) -> CLVReport {
    let closed = entries.filter { $0.status == "CLOSED" && $0.clv != nil }
    guard !closed.isEmpty else {
      return CLVReport(
        totalWithCLV: 0, positiveCount: 0, neutralCount: 0, negativeCount: 0,
        avgCLV: 0, medianCLV: 0, byMarket: [:],
        pnlPositive: 0, pnlNegative: 0, positiveRate: 0,
        verdict: "NO DATA",
        note: "Нет закрытых записей с CLV")
    }
    let clvs = closed.compactMap { $0.clv }
    let avg = clvs.reduce(0, +) / Double(clvs.count)
    let median = QuantMath.median(clvs) ?? 0

    let pos = closed.filter { ($0.clv ?? 0) > 0.005 }
    let neg = closed.filter { ($0.clv ?? 0) < -0.005 }
    let neu = closed.count - pos.count - neg.count

    var byMarket: [String: MarketCLV] = [:]
    let grouped = Dictionary(grouping: closed, by: { $0.market })
    for (mk, list) in grouped {
      let vals = list.compactMap { $0.clv }
      guard !vals.isEmpty else { continue }
      let a = vals.reduce(0, +) / Double(vals.count)
      let p = Double(list.filter { ($0.clv ?? 0) > 0.005 }.count) / Double(list.count)
      byMarket[mk] = MarketCLV(count: list.count, avgCLV: a, positiveRate: p)
    }

    let pnlPos = pos.compactMap { $0.profit }.reduce(0, +)
    let pnlNeg = neg.compactMap { $0.profit }.reduce(0, +)
    let rate = Double(pos.count) / Double(closed.count)

    let verdict: String
    let note: String
    if avg > 0.015 && rate > 0.55 {
      verdict = "STRONG"
      note = "Сигналы системно берут цену лучше закрытия — edge до рынка подтверждён"
    } else if avg > 0.005 && rate > 0.45 {
      verdict = "OK"
      note = "Средний CLV положительный, доля плюсовых ставок приемлемая"
    } else if avg > -0.005 && rate > 0.35 {
      verdict = "WEAK"
      note = "CLV около нуля — преимущество слабое, следите за выборкой"
    } else if avg < -0.01 {
      verdict = "NEGATIVE"
      note = "Цена систематически хуже закрытия — edge под вопросом"
    } else {
      verdict = "MIXED"
      note = "CLV асимметричный — нестабильная картина"
    }
    return CLVReport(
      totalWithCLV: closed.count,
      positiveCount: pos.count, neutralCount: neu, negativeCount: neg.count,
      avgCLV: avg, medianCLV: median, byMarket: byMarket,
      pnlPositive: pnlPos, pnlNegative: pnlNeg,
      positiveRate: rate, verdict: verdict, note: note)
  }

  static func oosFromJournal(_ entries: [JournalEntry],
                             windowDays: Int = 90) -> OOSValidationReport {
    OOSBuilder.build(from: entries, windowDays: windowDays)
  }
}
