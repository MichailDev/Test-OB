import Foundation
import SwiftData

@MainActor
final class ScanCoordinator {
  static let shared = ScanCoordinator()
  private var isScanning = false
  private init() {}

  struct ScanSummary {
    var signals: [BetSignal] = []
    var scannedMatches = 0
    var skippedExcluded = 0
    var notes: [String] = []
    var finishedAt: Date?
    var success: Bool = false
    var lossStreak: Int = 0
    var volatilityLabel: String = "NORMAL"
    var correlationPairs: Int = 0
    var lineupsFound: Int = 0
    var tuningNote: String? = nil
    var cornersSignals: Int = 0
    var cardsSignals: Int = 0
    var liveDropped: Int = 0
    var h2hFetched: Int = 0
    var oosBlocked: [String] = []
  }

  func scan(settings: AppSettings? = nil,
            selectedLeague: String = "Все") async -> ScanSummary {
    if isScanning { return ScanSummary(notes: ["Уже выполняется"]) }
    isScanning = true
    defer { isScanning = false }

    var summary = ScanSummary()
    let resolvedSettings: AppSettings = settings ?? AppSettings()
    let key = resolvedSettings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty else {
      summary.notes.append("API key не задан")
      return summary
    }

    let container = AppDependencies.shared.container
    let journalContext = container.map { ModelContext($0) }
    let ratingContext = container.map { ModelContext($0) }

    let tuning: TuningConfig = {
      guard let ctx = journalContext else { return TuningConfig() }
      return TuningService.fetchOrCreate(in: ctx)
    }()

    var thresholds = SignalThresholds.from(tuning)
    let journalEntries: [JournalEntry] = {
      guard let ctx = journalContext else { return [] }
      let d = FetchDescriptor<JournalEntry>()
      return (try? ctx.fetch(d)) ?? []
    }()

    if tuning.oosGateEnabled {
      let oosReport = OOSBuilder.build(from: journalEntries,
                                       windowDays: tuning.oosWindowDays)
      let blocked = OOSBuilder.blockedMarkets(report: oosReport, cfg: tuning)
      thresholds.blockedByOOS = blocked
      summary.oosBlocked = Array(blocked).sorted()
      if !blocked.isEmpty {
        summary.notes.append("OOS-блок: \(summary.oosBlocked.joined(separator: ", "))")
      }
      if let container = container {
        let snapCtx = ModelContext(container)
        let snap = BacktestService.fetchOrCreate(in: snapCtx)
        snap.oosValidationJSON = try? JSONEncoder().encode(oosReport)
        try? snapCtx.save()
      }
    }

    let cornerWeights = CornerWeights.from(tuning)
    let cardWeights = CardWeights.from(tuning)

    let corrMatrix: CorrelationMatrix = {
      CorrelationBuilder.build(from: journalEntries)
    }()
    summary.correlationPairs = corrMatrix.marketPairsN.count + corrMatrix.leaguePairsN.count

    let streak: (streak: Int, state: VolatilityState) = {
      VolatilityStop.evaluate(journalEntries,
        capThreshold: tuning.stopLossCapStreak,
        pauseThreshold: tuning.stopLossPauseStreak)
    }()
    summary.lossStreak = streak.streak
    summary.volatilityLabel = tuning.stopLossEnabled ? streak.state.label : "OFF"

    if !tuning.stopLossEnabled { summary.notes.append("Self-Tuning: stop-loss отключён") }
    else if streak.streak > 0 { summary.notes.append("LossStreak: \(streak.streak) · \(streak.state.label)") }
    if !tuning.autoExcludeEnabled { summary.notes.append("Self-Tuning: Auto-Exclude отключён") }
    if !tuning.posteriorEnabled { summary.notes.append("Self-Tuning: posterior отключён") }
    if !tuning.correlationEnabled { summary.notes.append("Self-Tuning: correlation отключён") }
    if !tuning.playerImpactEnabled { summary.notes.append("Self-Tuning: player impact отключён") }
    if !tuning.teamRatingEnabled { summary.notes.append("Self-Tuning: TeamRating отключён") }
    if !thresholds.cornersEnabled { summary.notes.append("Self-Tuning: рынок CORNERS выключен") }
    if !thresholds.cardsEnabled { summary.notes.append("Self-Tuning: рынок CARDS выключен") }

    do {
      let client = SStatsClient(settings: resolvedSettings)
      let engine = QuantEngine()

      let base = engine.matches(from: try await client.listToday(fresh: true))
        .filter { !Self.isExcluded($0) }

      var all = base.filter { m in
        guard let st = m.status else { return true }
        return st == 2
      }
      summary.liveDropped = base.count - all.count
      summary.skippedExcluded = max(0, base.count - all.count)
      summary.notes.append("Всего матчей сегодня: \(base.count)")
      if summary.liveDropped > 0 {
        summary.notes.append("Отсеяно начавшихся/завершённых: \(summary.liveDropped)")
      }

      if selectedLeague != "Все" {
        all = all.filter { $0.league.localizedCaseInsensitiveContains(selectedLeague) }
      }
      let matches = all
      summary.notes.append("К обработке без лимита: \(matches.count)")

      let posteriorBuckets: [PosteriorBucket] = tuning.posteriorEnabled
        ? Self.loadPosteriorBuckets() : []
      let posteriorCornersBuckets: [PosteriorBucket] = tuning.posteriorEnabled
        ? Self.loadPosteriorCornersBuckets() : []
      let posteriorCardsBuckets: [PosteriorBucket] = tuning.posteriorEnabled
        ? Self.loadPosteriorCardsBuckets() : []

      let usableBuckets = posteriorBuckets.filter { $0.n >= 20 }.count
      if usableBuckets > 0 { summary.notes.append("Posterior: \(usableBuckets) надёжных бакетов") }
      let usableCorners = posteriorCornersBuckets.filter { $0.n >= 20 }.count
      let usableCards = posteriorCardsBuckets.filter { $0.n >= 20 }.count
      if usableCorners > 0 || usableCards > 0 {
        summary.notes.append("Posterior CORNERS/CARDS: \(usableCorners)/\(usableCards) надёжных")
      }

      let excludedRules: [AutoExcludeRule] = tuning.autoExcludeEnabled
        ? Self.loadExcludedRules(minROI: tuning.autoExcludeMinROI,
                                 minBets: tuning.autoExcludeMinBets) : []
      let stopState: VolatilityState = tuning.stopLossEnabled ? streak.state : .normal

      var signalsOut: [BetSignal] = []
      var count = 0
      var lineupsFound = 0
      var cornersCount = 0
      var cardsCount = 0
      var h2hFetched = 0

      for match in matches {
        guard let h = match.homeID, let a = match.awayID else { continue }
        count += 1
        let hs = await client.fetchTeamHistory(
          teamID: h, count: resolvedSettings.historyMatches)
        let awayRecords = await client.fetchTeamHistory(
          teamID: a, count: resolvedSettings.historyMatches)
        guard let info = try? await client.gameInfo(match.id, fresh: true) else { continue }

        let data = info.object?["data"]?.object ?? info.object ?? [:]
        let game = data["game"]?.object ?? data
        let oddsFromInfo = game["odds"] ?? data["odds"]
          ?? match.oddsJSON ?? .array([])

        var fullBooks: [BookmakerOdds] = []
        if let nid = match.numericID {
          fullBooks = (try? await client.fullOdds(gameId: nid, fresh: true)) ?? []
        }

        var h2hRecords: [TeamRecord] = []
        let hasCornersOrCards = fullBooks.contains { book in
          book.odds.contains { m in
            m.marketId == MarketID.totalCorners || m.marketId == MarketID.totalCards
          }
        }
        if hasCornersOrCards && (thresholds.cornersEnabled || thresholds.cardsEnabled) {
          h2hRecords = await client.fetchH2H(
            homeID: h, awayID: a,
            homeName: match.home, awayName: match.away,
            count: 3)
          if !h2hRecords.isEmpty { h2hFetched += 1 }
        }

        let glicko = try? await client.glicko(match.id)

        let ratings: (Double?, Double?) = {
          guard tuning.teamRatingEnabled, let ctx = ratingContext else { return (nil, nil) }
          return (TeamRatingService.usableRating(for: h, context: ctx),
                  TeamRatingService.usableRating(for: a, context: ctx))
        }()

        let lineups: (home: [String], away: [String])? = {
          guard tuning.playerImpactEnabled else { return nil }
          return Self.parseUpcomingLineups(from: info)
        }()
        if lineups != nil { lineupsFound += 1 }

        var s = engine.signals(
          match: match, info: info, oddsJSON: oddsFromInfo,
          fullOdds: fullBooks,
          homeHistory: hs, awayHistory: awayRecords, glicko: glicko,
          h2hRecords: h2hRecords,
          posteriorBuckets: posteriorBuckets,
          posteriorBucketsByMarket: [
            "CORNERS": posteriorCornersBuckets,
            "CARDS": posteriorCardsBuckets
          ],
          posteriorWeight: tuning.posteriorWeight,
          teamRatings: (home: ratings.0, away: ratings.1),
          upcomingLineups: lineups,
          thresholds: thresholds,
          cornerWeights: cornerWeights,
          cardWeights: cardWeights)

        for sig in s {
          if sig.market == "CORNERS" { cornersCount += 1 }
          if sig.market == "CARDS"   { cardsCount += 1 }
        }

        s = s.map { sig in
          var x = sig
          let liveKey = "\(x.market)|\(x.selection.lowercased())|\(x.line.map { String($0) } ?? "")"
          if let cur = LiveMonitor.shared.snapshots[x.gameID],
             let prev = LiveMonitor.shared.previousSnapshotForDebug(matchID: x.gameID),
             let curAvg = cur.avg(forKey: liveKey),
             let prevAvg = prev.avg(forKey: liveKey),
             prevAvg > 1 {
            let delta = (curAvg - prevAvg) / prevAvg
            x.liveMovement = delta
            let moving = cur.booksMoving(forKey: liveKey, vs: prev, threshold: 0.01)
            if moving.count >= 3 && abs(delta) > 0.02 {
              x.sharpMoney = true
              x.sharpMovement = delta
            }
          }
          return x
        }
        signalsOut.append(contentsOf: s)
      }
      summary.lineupsFound = lineupsFound
      summary.h2hFetched = h2hFetched
      if lineupsFound > 0 { summary.notes.append("Lineups: \(lineupsFound)") }
      if h2hFetched > 0 { summary.notes.append("H2H загружено: \(h2hFetched)") }
      summary.cornersSignals = cornersCount
      summary.cardsSignals = cardsCount

      let filtered = signalsOut.filter { s in
        !AutoExclude.isExcluded(league: s.league, market: s.market, rules: excludedRules)
      }
      let removed = signalsOut.count - filtered.count
      if removed > 0 {
        summary.notes.append("Auto-Exclude: убрано \(removed) из \(signalsOut.count)")
      }

      summary.scannedMatches = count
      summary.signals = engine.portfolio(filtered,
        excludedRules: excludedRules,
        stopLoss: stopState,
        correlationMatrix: tuning.correlationEnabled ? corrMatrix : nil,
        bankroll: resolvedSettings.effectiveBankroll,
        thresholds: thresholds)
      summary.finishedAt = Date()
      summary.success = true

      let cornersInPort = summary.signals.filter { $0.market == "CORNERS" }.count
      let cardsInPort = summary.signals.filter { $0.market == "CARDS" }.count
      summary.notes.append("Сырых сигналов: \(signalsOut.count), в портфель: \(summary.signals.count)")
      summary.notes.append("Углы: \(cornersCount) сырых, \(cornersInPort) в портфель · ЖК: \(cardsCount) сырых, \(cardsInPort) в портфель")

      if resolvedSettings.notifyBets && !summary.signals.isEmpty {
        await NotificationService.notify(signals: summary.signals)
      }
    } catch {
      summary.notes.append("Ошибка: \(error.localizedDescription)")
    }

    return summary
  }

  func scanInBackground() async -> Bool {
    let result = await scan(settings: nil)
    return result.success
  }

  private static func loadExcludedRules(minROI: Double, minBets: Int) -> [AutoExcludeRule] {
    guard let container = AppDependencies.shared.container else { return [] }
    let context = ModelContext(container)
    let snap = BacktestService.fetchOrCreate(in: context)
    return AutoExclude.rules(from: snap, minROI: minROI, minBets: minBets)
  }

  private static func loadPosteriorBuckets() -> [PosteriorBucket] {
    guard let container = AppDependencies.shared.container else { return [] }
    let context = ModelContext(container)
    let snap = BacktestService.fetchOrCreate(in: context)
    return snap.decodedPosteriorBuckets()
  }

  private static func loadPosteriorCornersBuckets() -> [PosteriorBucket] {
    guard let container = AppDependencies.shared.container else { return [] }
    let context = ModelContext(container)
    let snap = BacktestService.fetchOrCreate(in: context)
    return snap.decodedPosteriorCornersBuckets()
  }

  private static func loadPosteriorCardsBuckets() -> [PosteriorBucket] {
    guard let container = AppDependencies.shared.container else { return [] }
    let context = ModelContext(container)
    let snap = BacktestService.fetchOrCreate(in: context)
    return snap.decodedPosteriorCardsBuckets()
  }

  private static func parseUpcomingLineups(from info: JSONValue)
    -> (home: [String], away: [String])? {
    let data = info.object?["data"]?.object ?? info.object ?? [:]
    if let obj = data["lineups"]?.object {
      let h = extractIDs(obj["home"]?.array ?? [])
      let a = extractIDs(obj["away"]?.array ?? [])
      if !h.isEmpty || !a.isEmpty { return (h, a) }
    }
    return nil
  }

  private static func extractIDs(_ arr: [JSONValue]) -> [String] {
    var out: [String] = []
    for v in arr {
      guard let o = v.object else { continue }
      if let id = o["id"]?.string, !id.isEmpty { out.append(id); continue }
      if let n = o["id"]?.number { out.append(String(Int(n))); continue }
      if let pid = o["playerId"]?.string, !pid.isEmpty { out.append(pid); continue }
      if let name = o["name"]?.string, !name.isEmpty { out.append(name); continue }
    }
    return out
  }

  private static func isExcluded(_ m: Match) -> Bool {
    let x = "\(m.league) \(m.home) \(m.away)".lowercased()
    let bad = ["friendly", "women", "женщ", "u19 women", "u20 women"]
    return bad.contains(where: x.contains)
  }
}
