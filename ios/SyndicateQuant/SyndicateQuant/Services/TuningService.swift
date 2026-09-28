import Foundation
import SwiftData

@MainActor
enum TuningService {
  static func fetchOrCreate(in context: ModelContext) -> TuningConfig {
    let d = FetchDescriptor<TuningConfig>()
    if let existing = try? context.fetch(d).first { return existing }
    let cfg = TuningConfig()
    context.insert(cfg); try? context.save()
    return cfg
  }

  static func log(context: ModelContext, kind: String, target: String,
                  before: String, after: String, note: String = "") {
    let e = TuningEvent(kind: kind, target: target,
                        beforeValue: before, afterValue: after, note: note)
    context.insert(e); try? context.save()
  }

  static func recentEvents(context: ModelContext, limit: Int = 30) -> [TuningEvent] {
    var d = FetchDescriptor<TuningEvent>(
      sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
    d.fetchLimit = limit
    return (try? context.fetch(d)) ?? []
  }

  static func rollbackLastThreshold(in context: ModelContext) -> TuningEvent? {
    let d = FetchDescriptor<TuningEvent>(
      sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
    guard let events = try? context.fetch(d) else { return nil }
    guard let last = events.first(where: {
      ($0.kind == "threshold" || $0.kind == "toggle") && !$0.rolledBack
    }) else { return nil }

    let cfg = fetchOrCreate(in: context)
    switch last.target {
    case "posteriorWeight": cfg.posteriorWeight = Double(last.beforeValue) ?? cfg.posteriorWeight
    case "autoExcludeMinROI": cfg.autoExcludeMinROI = Double(last.beforeValue) ?? cfg.autoExcludeMinROI
    case "autoExcludeMinBets": cfg.autoExcludeMinBets = Int(last.beforeValue) ?? cfg.autoExcludeMinBets
    case "stopLossCapStreak": cfg.stopLossCapStreak = Int(last.beforeValue) ?? cfg.stopLossCapStreak
    case "stopLossPauseStreak": cfg.stopLossPauseStreak = Int(last.beforeValue) ?? cfg.stopLossPauseStreak
    case "autoExcludeEnabled": cfg.autoExcludeEnabled = Bool(last.beforeValue) ?? cfg.autoExcludeEnabled
    case "posteriorEnabled": cfg.posteriorEnabled = Bool(last.beforeValue) ?? cfg.posteriorEnabled
    case "stopLossEnabled": cfg.stopLossEnabled = Bool(last.beforeValue) ?? cfg.stopLossEnabled
    case "correlationEnabled": cfg.correlationEnabled = Bool(last.beforeValue) ?? cfg.correlationEnabled
    case "playerImpactEnabled": cfg.playerImpactEnabled = Bool(last.beforeValue) ?? cfg.playerImpactEnabled
    case "teamRatingEnabled": cfg.teamRatingEnabled = Bool(last.beforeValue) ?? cfg.teamRatingEnabled
    case "cornersEnabled": cfg.cornersEnabled = Bool(last.beforeValue) ?? cfg.cornersEnabled
    case "cardsEnabled": cfg.cardsEnabled = Bool(last.beforeValue) ?? cfg.cardsEnabled
    case "cornersMinEV": cfg.cornersMinEV = Double(last.beforeValue) ?? cfg.cornersMinEV
    case "cardsMinEV": cfg.cardsMinEV = Double(last.beforeValue) ?? cfg.cardsMinEV
    case "cornersMinQCS": cfg.cornersMinQCS = Double(last.beforeValue) ?? cfg.cornersMinQCS
    case "cardsMinQCS": cfg.cardsMinQCS = Double(last.beforeValue) ?? cfg.cardsMinQCS
    case "cornersMaxStake": cfg.cornersMaxStake = Double(last.beforeValue) ?? cfg.cornersMaxStake
    case "cardsMaxStake": cfg.cardsMaxStake = Double(last.beforeValue) ?? cfg.cardsMaxStake
    case "cornersMinSample": cfg.cornersMinSample = Int(last.beforeValue) ?? cfg.cornersMinSample
    case "cardsMinSample": cfg.cardsMinSample = Int(last.beforeValue) ?? cfg.cardsMinSample
    case "goalsMinRobustEV": cfg.goalsMinRobustEV = Double(last.beforeValue) ?? cfg.goalsMinRobustEV
    case "goalsMinSample": cfg.goalsMinSample = Int(last.beforeValue) ?? cfg.goalsMinSample
    case "goalsMaxUncertainty": cfg.goalsMaxUncertainty = Double(last.beforeValue) ?? cfg.goalsMaxUncertainty
    case "cornersMinRobustEV": cfg.cornersMinRobustEV = Double(last.beforeValue) ?? cfg.cornersMinRobustEV
    case "cornersMinMSS": cfg.cornersMinMSS = Double(last.beforeValue) ?? cfg.cornersMinMSS
    case "cornersMaxUncertainty": cfg.cornersMaxUncertainty = Double(last.beforeValue) ?? cfg.cornersMaxUncertainty
    case "cardsMinRobustEV": cfg.cardsMinRobustEV = Double(last.beforeValue) ?? cfg.cardsMinRobustEV
    case "cardsMinMSS": cfg.cardsMinMSS = Double(last.beforeValue) ?? cfg.cardsMinMSS
    case "cardsMaxUncertainty": cfg.cardsMaxUncertainty = Double(last.beforeValue) ?? cfg.cardsMaxUncertainty
    case "oosGateEnabled": cfg.oosGateEnabled = Bool(last.beforeValue) ?? cfg.oosGateEnabled
    case "oosMinBets": cfg.oosMinBets = Int(last.beforeValue) ?? cfg.oosMinBets
    case "oosWindowDays": cfg.oosWindowDays = Int(last.beforeValue) ?? cfg.oosWindowDays
    case "goalsOOSMinROI": cfg.goalsOOSMinROI = Double(last.beforeValue) ?? cfg.goalsOOSMinROI
    case "cornersOOSMinROI": cfg.cornersOOSMinROI = Double(last.beforeValue) ?? cfg.cornersOOSMinROI
    case "cardsOOSMinROI": cfg.cardsOOSMinROI = Double(last.beforeValue) ?? cfg.cardsOOSMinROI
    case "cornersWeightRecentOwn": cfg.cornersWeightRecentOwn = Double(last.beforeValue) ?? cfg.cornersWeightRecentOwn
    case "cornersWeightRecentOpp": cfg.cornersWeightRecentOpp = Double(last.beforeValue) ?? cfg.cornersWeightRecentOpp
    case "cornersWeightLeague": cfg.cornersWeightLeague = Double(last.beforeValue) ?? cfg.cornersWeightLeague
    case "cornersWeightXG": cfg.cornersWeightXG = Double(last.beforeValue) ?? cfg.cornersWeightXG
    case "cornersWeightPossession": cfg.cornersWeightPossession = Double(last.beforeValue) ?? cfg.cornersWeightPossession
    case "cornersWeightH2H": cfg.cornersWeightH2H = Double(last.beforeValue) ?? cfg.cornersWeightH2H
    case "cardsWeightRecentOwn": cfg.cardsWeightRecentOwn = Double(last.beforeValue) ?? cfg.cardsWeightRecentOwn
    case "cardsWeightRecentOpp": cfg.cardsWeightRecentOpp = Double(last.beforeValue) ?? cfg.cardsWeightRecentOpp
    case "cardsWeightLeague": cfg.cardsWeightLeague = Double(last.beforeValue) ?? cfg.cardsWeightLeague
    case "cardsWeightFouls": cfg.cardsWeightFouls = Double(last.beforeValue) ?? cfg.cardsWeightFouls
    case "cardsWeightReferee": cfg.cardsWeightReferee = Double(last.beforeValue) ?? cfg.cardsWeightReferee
    case "cardsWeightH2H": cfg.cardsWeightH2H = Double(last.beforeValue) ?? cfg.cardsWeightH2H
    default: break
    }
    cfg.updatedAt = Date()
    last.rolledBack = true
    try? context.save()
    return last
  }

  static func decisions(config: TuningConfig, snapshot: BacktestSnapshot?,
                        journal: [JournalEntry], corr: CorrelationMatrix) -> [AutoDecision] {
    var out: [AutoDecision] = []
    let rules = snapshot.map {
      AutoExclude.rules(from: $0, minROI: config.autoExcludeMinROI,
                        minBets: config.autoExcludeMinBets)
    } ?? []
    let activeRules = rules.filter { $0.excluded }.count
    out.append(AutoDecision(id: "autoexclude", title: "Auto-Exclude",
      summary: config.autoExcludeEnabled ? "\(activeRules) активных правил" : "выключено",
      detail: String(format: "Порог: ROI < %.1f%% при n ≥ %d",
                     config.autoExcludeMinROI * 100, config.autoExcludeMinBets),
      enabled: config.autoExcludeEnabled, flagKey: "autoExcludeEnabled"))

    let buckets = snapshot?.decodedPosteriorBuckets() ?? []
    let usable = buckets.filter { $0.n >= 20 }.count
    out.append(AutoDecision(id: "posterior", title: "Bayesian posterior",
      summary: config.posteriorEnabled ? "\(usable) бакетов (n≥20)" : "выключено",
      detail: String(format: "p_adj = (1 − %.2f)·p + %.2f·p_post",
                     config.posteriorWeight, config.posteriorWeight),
      enabled: config.posteriorEnabled, flagKey: "posteriorEnabled"))

    let streak = VolatilityStop.evaluate(journal,
      capThreshold: config.stopLossCapStreak,
      pauseThreshold: config.stopLossPauseStreak)
    out.append(AutoDecision(id: "stoploss", title: "Volatility stop",
      summary: config.stopLossEnabled
        ? "\(streak.streak) проигрышей · \(streak.state.label)" : "выключено",
      detail: "Cap ≥ \(config.stopLossCapStreak) → 5%; Pause ≥ \(config.stopLossPauseStreak)",
      enabled: config.stopLossEnabled, flagKey: "stopLossEnabled"))

    out.append(AutoDecision(id: "correlation", title: "Correlation matrix",
      summary: config.correlationEnabled
        ? "\(corr.marketPairsN.count + corr.leaguePairsN.count) пар (n≥20)" : "выключено",
      detail: "Эмпирические φ-коэффициенты из журнала; fallback — структурные",
      enabled: config.correlationEnabled, flagKey: "correlationEnabled"))

    out.append(AutoDecision(id: "playerimpact", title: "Player impact",
      summary: config.playerImpactEnabled ? "ждём составы от API" : "выключено",
      detail: "λ × 0.88…1.00 в зависимости от отсутствия топ-8",
      enabled: config.playerImpactEnabled, flagKey: "playerImpactEnabled"))

    out.append(AutoDecision(id: "teamrating", title: "Team rating (Elo)",
      summary: config.teamRatingEnabled ? "активно (≥ 3 матчей на команду)" : "выключено",
      detail: "Старт 1500, HFA 60, K=32→20; влияет на λ через glickoAdjust",
      enabled: config.teamRatingEnabled, flagKey: "teamRatingEnabled"))

    let oosReport = OOSBuilder.build(from: journal, windowDays: config.oosWindowDays)
    let blocked = OOSBuilder.blockedMarkets(report: oosReport, cfg: config)
    let oosSummary: String = {
      if !config.oosGateEnabled { return "выключено" }
      if blocked.isEmpty { return "активно · блокировок нет" }
      return "активно · блок: \(blocked.sorted().joined(separator: ", "))"
    }()
    out.append(AutoDecision(id: "oos", title: "OOS-валидация",
      summary: oosSummary,
      detail: String(format: "Окно %d дней · n≥%d · порог ROI −%.1f%%",
                     config.oosWindowDays, config.oosMinBets,
                     abs(config.goalsOOSMinROI) * 100),
      enabled: config.oosGateEnabled, flagKey: "oosGateEnabled"))

    out.append(AutoDecision(id: "corners", title: "Рынок CORNERS",
      summary: config.cornersEnabled
        ? String(format: "EV ≥ %.1f%%, robEV ≥ %.1f%%, QCS ≥ %.0f, MSS ≥ %.0f, sample ≥ %d, unc ≤ %.2f",
                 config.cornersMinEV * 100, config.cornersMinRobustEV * 100,
                 config.cornersMinQCS, config.cornersMinMSS,
                 config.cornersMinSample, config.cornersMaxUncertainty)
        : "выключен",
      detail: String(format: "Pinnacle. Вес λ: own %.2f/opp %.2f · xG %.2f · H2H %.2f · poss %.2f",
                     config.cornersWeightRecentOwn, config.cornersWeightRecentOpp,
                     config.cornersWeightXG, config.cornersWeightH2H,
                     config.cornersWeightPossession),
      enabled: config.cornersEnabled, flagKey: "cornersEnabled"))

    out.append(AutoDecision(id: "cards", title: "Рынок CARDS",
      summary: config.cardsEnabled
        ? String(format: "EV ≥ %.1f%%, robEV ≥ %.1f%%, QCS ≥ %.0f, MSS ≥ %.0f, sample ≥ %d, unc ≤ %.2f",
                 config.cardsMinEV * 100, config.cardsMinRobustEV * 100,
                 config.cardsMinQCS, config.cardsMinMSS,
                 config.cardsMinSample, config.cardsMaxUncertainty)
        : "выключен",
      detail: String(format: "Best available. Вес λ: fouls %.2f, ref %.2f, H2H %.2f",
                     config.cardsWeightFouls, config.cardsWeightReferee,
                     config.cardsWeightH2H),
      enabled: config.cardsEnabled, flagKey: "cardsEnabled"))

    return out
  }
}
