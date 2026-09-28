import Foundation

enum SampleClass: String, Codable {
  case full = "FULL"
  case good = "GOOD"
  case usable = "USABLE"
  case insufficient = "INS."

  static func classify(_ n: Int) -> SampleClass {
    if n >= 15 { return .full }
    if n >= 10 { return .good }
    if n >= 6 { return .usable }
    return .insufficient
  }
  var trustWeight: Double {
    switch self {
    case .full: return 1.0
    case .good: return 0.85
    case .usable: return 0.65
    case .insufficient: return 0.0
    }
  }
  var dcsScore: Double {
    switch self {
    case .full: return 100
    case .good: return 80
    case .usable: return 55
    case .insufficient: return 20
    }
  }
}

enum UncertaintyBand {
  case low, medium, high
  static func from(_ u: Double) -> UncertaintyBand {
    if u < 0.10 { return .low }
    if u < 0.22 { return .medium }
    return .high
  }
  var kellyMultiplier: Double {
    switch self {
    case .low: return 1.00
    case .medium: return 0.75
    case .high: return 0.50
    }
  }
  var label: String {
    switch self {
    case .low: return "LOW"
    case .medium: return "MED"
    case .high: return "HIGH"
    }
  }
}

struct SignalThresholds: Hashable {
  var goalsMinEV: Double
  var goalsMinRobustEV: Double
  var goalsMinQCS: Double
  var goalsMinMSS: Double
  var goalsMaxUncertainty: Double
  var goalsMinSample: Int
  var goalsMaxStake: Double

  var cornersEnabled: Bool
  var cornersMinEV: Double
  var cornersMinRobustEV: Double
  var cornersMinQCS: Double
  var cornersMinMSS: Double
  var cornersMaxUncertainty: Double
  var cornersMinSample: Int
  var cornersMaxStake: Double

  var cardsEnabled: Bool
  var cardsMinEV: Double
  var cardsMinRobustEV: Double
  var cardsMinQCS: Double
  var cardsMinMSS: Double
  var cardsMaxUncertainty: Double
  var cardsMinSample: Int
  var cardsMaxStake: Double

  var blockedByOOS: Set<String> = []

  static let `default` = SignalThresholds(
    goalsMinEV: 0.03, goalsMinRobustEV: 0.0,
    goalsMinQCS: 78, goalsMinMSS: 0, goalsMaxUncertainty: 0.25,
    goalsMinSample: 6, goalsMaxStake: 0.025,
    cornersEnabled: true,
    cornersMinEV: 0.03, cornersMinRobustEV: 0.0,
    cornersMinQCS: 70, cornersMinMSS: 30, cornersMaxUncertainty: 0.22,
    cornersMinSample: 5, cornersMaxStake: 0.02,
    cardsEnabled: true,
    cardsMinEV: 0.03, cardsMinRobustEV: 0.0,
    cardsMinQCS: 70, cardsMinMSS: 30, cardsMaxUncertainty: 0.22,
    cardsMinSample: 5, cardsMaxStake: 0.02)

  static func from(_ cfg: TuningConfig) -> SignalThresholds {
    SignalThresholds(
      goalsMinEV: 0.03,
      goalsMinRobustEV: cfg.goalsMinRobustEV,
      goalsMinQCS: 78, goalsMinMSS: 0,
      goalsMaxUncertainty: cfg.goalsMaxUncertainty,
      goalsMinSample: cfg.goalsMinSample,
      goalsMaxStake: 0.025,
      cornersEnabled: cfg.cornersEnabled,
      cornersMinEV: cfg.cornersMinEV,
      cornersMinRobustEV: cfg.cornersMinRobustEV,
      cornersMinQCS: cfg.cornersMinQCS,
      cornersMinMSS: cfg.cornersMinMSS,
      cornersMaxUncertainty: cfg.cornersMaxUncertainty,
      cornersMinSample: cfg.cornersMinSample,
      cornersMaxStake: cfg.cornersMaxStake,
      cardsEnabled: cfg.cardsEnabled,
      cardsMinEV: cfg.cardsMinEV,
      cardsMinRobustEV: cfg.cardsMinRobustEV,
      cardsMinQCS: cfg.cardsMinQCS,
      cardsMinMSS: cfg.cardsMinMSS,
      cardsMaxUncertainty: cfg.cardsMaxUncertainty,
      cardsMinSample: cfg.cardsMinSample,
      cardsMaxStake: cfg.cardsMaxStake)
  }
}

struct CornerWeights: Hashable {
  var recentOwn: Double
  var recentOpp: Double
  var leagueAvg: Double
  var xgFactor: Double
  var possession: Double
  var h2h: Double

  static let `default` = CornerWeights(
    recentOwn: 0.35, recentOpp: 0.25,
    leagueAvg: 0.15, xgFactor: 0.10,
    possession: 0.05, h2h: 0.10)

  static func from(_ cfg: TuningConfig) -> CornerWeights {
    CornerWeights(
      recentOwn: cfg.cornersWeightRecentOwn,
      recentOpp: cfg.cornersWeightRecentOpp,
      leagueAvg: cfg.cornersWeightLeague,
      xgFactor: cfg.cornersWeightXG,
      possession: cfg.cornersWeightPossession,
      h2h: cfg.cornersWeightH2H)
  }
}

struct CardWeights: Hashable {
  var recentOwn: Double
  var recentOpp: Double
  var leagueAvg: Double
  var fouls: Double
  var referee: Double
  var h2h: Double

  static let `default` = CardWeights(
    recentOwn: 0.30, recentOpp: 0.20,
    leagueAvg: 0.15, fouls: 0.10,
    referee: 0.20, h2h: 0.05)

  static func from(_ cfg: TuningConfig) -> CardWeights {
    CardWeights(
      recentOwn: cfg.cardsWeightRecentOwn,
      recentOpp: cfg.cardsWeightRecentOpp,
      leagueAvg: cfg.cardsWeightLeague,
      fouls: cfg.cardsWeightFouls,
      referee: cfg.cardsWeightReferee,
      h2h: cfg.cardsWeightH2H)
  }
}

struct Match: Identifiable, Codable, Hashable {
  let id: String
  let home: String
  let away: String
  let league: String
  let start: Date?
  let homeID: String?
  let awayID: String?
  var homeFT: Double?
  var awayFT: Double?
  var oddsJSON: JSONValue?
  var numericID: Int?
  var status: Int? = nil

  var homeCorners: Int? = nil
  var awayCorners: Int? = nil
  var homeYellows: Int? = nil
  var awayYellows: Int? = nil
  var homeReds: Int? = nil
  var awayReds: Int? = nil
}

struct Quote: Codable, Hashable {
  let market: String
  let selection: String
  let line: Double?
  let odds: Double
  let bookmaker: String
}

struct BetSignal: Identifiable, Codable, Hashable {
  let id: String
  let gameID: String
  let home: String
  let away: String
  let league: String
  let market: String
  let selection: String
  let line: Double?
  let odds: Double
  let probability: Double
  let fairOdds: Double
  let ev: Double
  let robustEV: Double
  let model: String
  let timestamp: Date
  let classification: String
  var stake: Double
  let priceAnomaly: Bool
  let bookmakers: Int

  let dcs: Double
  let ms: Double
  let mes: Double
  let ts: Double
  let rs: Double
  let qcs: Double

  let sampleClass: String
  let homeSample: Int
  let awaySample: Int
  let uncertainty: Double
  let uncertaintyBand: String
  let marketProbability: Double
  let marketMAD: Double
  let probabilityLow: Double
  let probabilityHigh: Double

  let kellyFraction: Double
  let quarterKelly: Double
  let stakeCap: Double
  var portfolioCorrelation: Double
  var correlationReason: String

  var probabilityRaw: Double? = nil
  var posteriorWeight: Double? = nil
  var posteriorSource: String? = nil

  var stopApplied: String? = nil
  var stakeBeforeStop: Double? = nil

  var playerImpactHome: Double? = nil
  var playerImpactAway: Double? = nil

  var stakeMoney: Double? = nil
  var bestOdds: Double? = nil
  var bestBook: String? = nil
  var worstOdds: Double? = nil
  var worstBook: String? = nil
  var avgOdds: Double? = nil

  var sharpMoney: Bool? = nil
  var sharpMovement: Double? = nil
  var liveMovement: Double? = nil

  var modelVote: Int? = nil
  var modelVoteDetail: String? = nil

  var oddsSource: String? = nil
  var startTime: Date? = nil
  var mss: Double? = nil
}
