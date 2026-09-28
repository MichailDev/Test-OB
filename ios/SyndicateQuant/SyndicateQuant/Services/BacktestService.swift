import Foundation
import SwiftData

@MainActor
final class BacktestService {
  static let shared = BacktestService()
  private init() {}

  static let yearsBack = 2
  static let monthsPerYear = 12
  static let gamesPerRequest = 1000
  static let maxPagesPerMonth = 20
  static let oddsFetchCap = 1500
  static let cornersCardsFetchCap = 1500

  private var isBuilding = false

  struct Checkpoint: Codable {
    var jobID: String?
    var fromDate: Double
    var toDate: Double
    var cursor: Double
    var matches: [Match]
    var histories: [String: [TeamRecord]]
    var matchesCount: Int?
    var historiesCount: Int?
  }

  static var checkpointURL: URL {
    let fm = FileManager.default
    let docs = (try? fm.url(for: .documentDirectory, in: .userDomainMask,
                            appropriateFor: nil, create: true))
      ?? URL(fileURLWithPath: NSTemporaryDirectory())
    return docs.appendingPathComponent("build_checkpoint.json")
  }

  static func hasCheckpoint() -> Bool {
    FileManager.default.fileExists(atPath: checkpointURL.path)
  }

  static func loadCheckpoint() -> Checkpoint? {
    guard let data = try? Data(contentsOf: checkpointURL),
          let cp = try? JSONDecoder().decode(Checkpoint.self, from: data)
    else { return nil }
    return cp
  }

  static func saveCheckpoint(jobID: String,
                             cursor: Date, fromDate: Date, toDate: Date,
                             matches: [Match],
                             histories: [String: [TeamRecord]]) {
    let cp = Checkpoint(
      jobID: jobID,
      fromDate: fromDate.timeIntervalSince1970,
      toDate: toDate.timeIntervalSince1970,
      cursor: cursor.timeIntervalSince1970,
      matches: matches,
      histories: histories,
      matchesCount: matches.count,
      historiesCount: histories.count)
    if let data = try? JSONEncoder().encode(cp) {
      try? data.write(to: checkpointURL, options: .atomic)
    }
  }

  static func clearCheckpoint() {
    try? FileManager.default.removeItem(at: checkpointURL)
  }

  func buildFullBase(
    progress: @MainActor @escaping (Double, String) -> Void
  ) async -> Bool {
    if isBuilding { progress(0, "Уже выполняется"); return false }
    isBuilding = true
    defer { isBuilding = false }

    guard let container = AppDependencies.shared.container else {
      progress(0, "Нет контейнера"); return false
    }
    let context = ModelContext(container)
    let snapshot = Self.fetchOrCreate(in: context)

    let settings = AppSettings()
    let key = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty else {
      snapshot.buildStatus = "failed"
      snapshot.lastError = "API key не задан"
      try? context.save()
      progress(0, "API key не задан")
      return false
    }

    let client = SStatsClient(settings: settings)
    let engine = QuantEngine()
    let backtester = WalkForwardBacktester()
    let cal = Calendar(identifier: .gregorian)

    let toDate = Date()
    guard let fromDate = cal.date(byAdding: .year, value: -Self.yearsBack, to: toDate) else {
      snapshot.buildStatus = "failed"
      snapshot.lastError = "Не могу построить дату"
      try? context.save()
      return false
    }

    var cursor: Date = fromDate
    var allMatches: [Match] = []
    var allHistories: [String: [TeamRecord]] = [:]
    var resumed = false
    var jobID: String = snapshot.buildJobID ?? UUID().uuidString

    if snapshot.buildStatus == "building",
       let cp = Self.loadCheckpoint(),
       let cpJobID = cp.jobID,
       cpJobID == jobID {
      cursor = Date(timeIntervalSince1970: cp.cursor)
      allMatches = cp.matches
      allHistories = cp.histories
      resumed = true
      snapshot.buildMatchesCount = allMatches.count
      snapshot.buildCursorTimestamp = cp.cursor
      try? context.save()
      progress(0, "Продолжаю сбор с \(Self.shortDay(cursor)) · матчей: \(allMatches.count)")
    } else {
      Self.clearCheckpoint()
    }

    if !resumed {
      Self.clearCheckpoint()
      jobID = UUID().uuidString
      snapshot.buildStatus = "building"
      snapshot.buildProgress = 0
      snapshot.lastError = nil
      snapshot.builtAt = nil
      snapshot.fromDate = fromDate
      snapshot.toDate = toDate
      snapshot.totalMatches = 0
      snapshot.totalBets = 0
      snapshot.enrichmentProgress = 0
      snapshot.enrichmentTotal = 0
      snapshot.buildCursorTimestamp = fromDate.timeIntervalSince1970
      snapshot.buildMatchesCount = 0
      snapshot.buildJobID = jobID
      try? context.save()
    }

    var seenIDs = Set(allMatches.map { $0.id })
    var monthIndex = max(0, cal.dateComponents([.month], from: fromDate, to: cursor).month ?? 0)
    let totalMonths = Self.yearsBack * Self.monthsPerYear

    // ── Фаза 1: сбор матчей по месяцам
    while cursor < toDate {
      guard let nextMonth = cal.date(byAdding: .month, value: 1, to: cursor) else { break }
      let periodEnd = min(nextMonth, toDate)
      let monthProgress = Double(monthIndex) / Double(totalMonths) * 0.55
      progress(monthProgress,
               "Сбор \(monthIndex + 1)/\(totalMonths) · матчей: \(allMatches.count)")

      var monthItems: [JSONValue] = []
      var pageOffset = 0
      var pageCount = 0

      while pageCount < Self.maxPagesPerMonth {
        do {
          let r = try await client.listGamesRange(
            from: cursor, to: periodEnd,
            limit: Self.gamesPerRequest, offset: pageOffset)
          let items = r.object?["data"]?.array ?? []
          if items.isEmpty { break }
          monthItems.append(contentsOf: items)
          pageOffset += Self.gamesPerRequest
          pageCount += 1
          if items.count < Self.gamesPerRequest { break }
          try? await Task.sleep(for: .milliseconds(700))
        } catch {
          print("[BT] month \(monthIndex) page \(pageCount) error: \(error.localizedDescription)")
          break
        }
      }

      if !monthItems.isEmpty {
        let json = JSONValue.object(["data": .array(monthItems)])
        let monthMatches = engine.matches(from: json)
          .filter { !Self.isExcluded($0) }
          .filter { Self.isInPool($0.league) }
          .filter { $0.homeFT != nil && $0.awayFT != nil }
          .filter { m in
            if seenIDs.contains(m.id) { return false }
            seenIDs.insert(m.id); return true
          }
        allMatches.append(contentsOf: monthMatches)
        let records = engine.allRecords(from: json)
        for (k, v) in records { allHistories[k, default: []].append(contentsOf: v) }
      }

      cursor = nextMonth
      monthIndex += 1

      Self.saveCheckpoint(jobID: jobID,
                          cursor: cursor, fromDate: fromDate, toDate: toDate,
                          matches: allMatches, histories: allHistories)
      snapshot.buildCursorTimestamp = cursor.timeIntervalSince1970
      snapshot.buildMatchesCount = allMatches.count
      snapshot.buildProgress = monthProgress
      try? context.save()
    }

    for (k, v) in allHistories {
      allHistories[k] = v.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
    }

    for m in allMatches {
      _ = HistoricalMarketCacheService.upsert(from: m, in: context)
    }
    try? context.save()
    let cacheSeed = HistoricalMarketCacheService.progress(in: context)
    snapshot.historicalCacheCount = cacheSeed.total
    snapshot.enrichmentTotal = cacheSeed.total
    snapshot.enrichmentProgress = cacheSeed.enriched
    try? context.save()

    // ── Фаза 2: Odds+stats (resume-safe)
    progress(0.55, "Матчей собрано: \(allMatches.count). Дотягиваю odds и statistics…")

    var allMatchesMut = allMatches
    let needOddsIdx: [Int] = allMatchesMut.enumerated()
      .filter { $0.element.oddsJSON?.array?.isEmpty != false }
      .map { $0.offset }
    let cap = min(needOddsIdx.count, Self.oddsFetchCap)

    for (i, idx) in needOddsIdx.prefix(cap).enumerated() {
      var mm = allMatchesMut[idx]
      if let nid = mm.numericID {
        if let o = try? await client.odds(numericID: nid) {
          let data = o.object?["data"]?.object ?? o.object ?? [:]
          let game = data["game"]?.object ?? data
          let stats = data["statistics"]?.object ?? game["statistics"]?.object ?? [:]
          mm.oddsJSON = game["odds"] ?? data["odds"]
          Self.fillCornersCards(into: &mm, from: stats)
          Self.replaceHistoryRecords(&allHistories, engine: engine,
                                     payload: o, match: mm)
        }
        allMatchesMut[idx] = mm
      }
      if i % 20 == 0 {
        let p = 0.55 + (Double(i) / Double(max(cap, 1))) * 0.10
        progress(p, "Odds+stats \(i + 1)/\(cap)")
        Self.saveCheckpoint(jobID: jobID,
                            cursor: cursor, fromDate: fromDate, toDate: toDate,
                            matches: allMatchesMut, histories: allHistories)
      }
      try? await Task.sleep(for: .milliseconds(400))
    }
    Self.saveCheckpoint(jobID: jobID,
                        cursor: cursor, fromDate: fromDate, toDate: toDate,
                        matches: allMatchesMut, histories: allHistories)

    // ── Фаза 3: Corners/Cards (resume-safe)
    let needCC: [Int] = allMatchesMut.enumerated().compactMap { (idx, m) -> Int? in
      guard m.numericID != nil else { return nil }
      let gid = m.id
      let d = FetchDescriptor<HistoricalMarketCache>(
        predicate: #Predicate { $0.gameID == gid })
      guard let row = try? context.fetch(d).first else { return idx }
      if row.cornersChecked && row.cardsChecked { return nil }
      if row.failedAttempts >= 3 { return nil }
      return idx
    }.sorted { a, b in
      let sa = allMatchesMut[a].start ?? .distantPast
      let sb = allMatchesMut[b].start ?? .distantPast
      return sa > sb
    }
    let ccCount = min(needCC.count, Self.cornersCardsFetchCap)

    progress(0.65, "Дотягиваю углы/ЖК (\(ccCount) матчей)…")

    for (i, idx) in needCC.prefix(ccCount).enumerated() {
      var mm = allMatchesMut[idx]
      if let nid = mm.numericID {
        do {
          let books = try await client.fullOdds(gameId: nid)
          guard !books.isEmpty else {
            HistoricalMarketCacheService.markFailed(gameID: mm.id, error: "Пустой ответ /Odds", in: context)
            continue
          }
          let extra = Self.oddsJSONFromBookmakers(books)
          var merged: [JSONValue] = mm.oddsJSON?.array ?? []
          merged.append(contentsOf: extra)
          mm.oddsJSON = .array(merged)
          allMatchesMut[idx] = mm

          let encoded = (try? JSONEncoder().encode(extra)) ?? Data()
          let hasC = extra.contains { $0.object?["marketId"]?.number == Double(MarketID.totalCorners) }
          let hasK = extra.contains { $0.object?["marketId"]?.number == Double(MarketID.totalCards) }
          if hasC || hasK {
            HistoricalMarketCacheService.markEnriched(gameID: mm.id, oddsData: encoded, hasCorners: hasC, hasCards: hasK, in: context)
          } else {
            HistoricalMarketCacheService.markFailed(gameID: mm.id, error: "Нет market 45/80 в /Odds", in: context)
          }
        } catch {
          HistoricalMarketCacheService.markFailed(gameID: mm.id, error: error.localizedDescription, in: context)
        }
      }
      if i % 25 == 0 {
        let p = 0.65 + (Double(i) / Double(max(ccCount, 1))) * 0.15
        progress(p, "Corners/Cards \(i + 1)/\(ccCount)")
        try? context.save()
        Self.saveCheckpoint(jobID: jobID,
                            cursor: cursor, fromDate: fromDate, toDate: toDate,
                            matches: allMatchesMut, histories: allHistories)
      }
      try? await Task.sleep(for: .milliseconds(400))
    }

    try? context.save()
    Self.saveCheckpoint(jobID: jobID,
                        cursor: cursor, fromDate: fromDate, toDate: toDate,
                        matches: allMatchesMut, histories: allHistories)

    let cacheAfter = HistoricalMarketCacheService.progress(in: context)
    snapshot.historicalCacheCount = cacheAfter.total
    snapshot.enrichmentTotal = cacheAfter.total
    snapshot.enrichmentProgress = cacheAfter.enriched
    try? context.save()

    var prepared: [Match] = allMatchesMut.filter { ($0.oddsJSON?.array?.isEmpty == false) }
    prepared.sort { ($0.start ?? .distantPast) < ($1.start ?? .distantPast) }

    guard !prepared.isEmpty else {
      snapshot.buildStatus = "failed"
      snapshot.lastError = "Нет матчей с odds (матчей: \(allMatchesMut.count), историй: \(allHistories.count))"
      try? context.save()
      progress(0, "Нет матчей с odds (собрано: \(allMatchesMut.count))")
      return false
    }

    let totalPrepared = prepared.count
    let trainEnd = max(1, Int(Double(totalPrepared) * 0.60))
    let valEnd = max(trainEnd + 1, Int(Double(totalPrepared) * 0.80))

    let trainMatches = Array(prepared[0..<trainEnd])
    let valMatches = Array(prepared[trainEnd..<min(valEnd, totalPrepared)])
    let holdoutMatches = Array(prepared[min(valEnd, totalPrepared)..<totalPrepared])

    progress(0.83, "Walk-forward train \(trainMatches.count) / val \(valMatches.count) / holdout \(holdoutMatches.count)…")
    let trainReport = backtester.run(matches: trainMatches, histories: allHistories)
    let valReport = backtester.run(matches: valMatches, histories: allHistories)
    let holdoutReport = backtester.run(matches: holdoutMatches, histories: allHistories)
    let report = backtester.run(matches: trainMatches + valMatches, histories: allHistories)

    progress(0.90, "Сравнение моделей (E5)…")
    let comparisons = MultiModelBacktester().run(
      matches: trainMatches + valMatches, histories: allHistories)

    progress(0.95, "Сохраняю снапшот…")

    snapshot.builtAt = Date()
    snapshot.fromDate = fromDate
    snapshot.toDate = toDate
    snapshot.totalMatches = report.matches
    snapshot.totalBets = report.bets
    snapshot.avgROI = report.roi
    snapshot.avgCLV = report.avgCLV
    snapshot.brier = report.brier
    snapshot.logLoss = report.logLoss
    snapshot.sharpe = report.sharpe
    snapshot.sortino = report.sortino
    snapshot.profitFactor = report.profitFactor

    snapshot.enrichmentTotal = prepared.count
    snapshot.enrichmentProgress = min(prepared.count, ccCount)

    let encoder = JSONEncoder()
    snapshot.trainReportJSON = try? encoder.encode(Self.walkForwardDelta(trainReport))
    snapshot.validationReportJSON = try? encoder.encode(Self.walkForwardDelta(valReport))
    snapshot.holdoutReportJSON = try? encoder.encode(Self.walkForwardDelta(holdoutReport))
    snapshot.walkForwardMode = "602020"

    snapshot.perLeagueJSON = try? encoder.encode(
      report.perLeague.mapValues { Self.toStored($0) })
    snapshot.perMarketJSON = try? encoder.encode(
      report.perMarket.mapValues { Self.toStored($0) })
    snapshot.perLeagueMarketJSON = try? encoder.encode(
      Self.leagueMarketSegment(report: report, matches: prepared))
    snapshot.evBucketsJSON = try? encoder.encode(
      report.byEVBucket.mapValues { Self.toStored($0) })
    snapshot.oddsBucketsJSON = try? encoder.encode(
      report.byOddsBand.mapValues { Self.toStored($0) })
    snapshot.classificationJSON = try? encoder.encode(
      report.byClassification.mapValues { Self.toStored($0) })
    snapshot.posteriorJSON = try? encoder.encode(
      Self.buildPosteriorBuckets(from: report.betRecords))
    snapshot.posteriorCornersJSON = try? encoder.encode(
      Self.buildPosteriorBuckets(from: report.betRecords.filter {
        $0.market == "CORNERS"
      }))
    snapshot.posteriorCardsJSON = try? encoder.encode(
      Self.buildPosteriorBuckets(from: report.betRecords.filter {
        $0.market == "CARDS"
      }))
    snapshot.modelComparisonJSON = try? encoder.encode(comparisons)

    let journalDescriptor = FetchDescriptor<JournalEntry>()
    let journal = (try? context.fetch(journalDescriptor)) ?? []
    let cfg = TuningService.fetchOrCreate(in: context)
    let oosReport = OOSBuilder.build(from: journal, windowDays: cfg.oosWindowDays)
    snapshot.oosValidationJSON = try? encoder.encode(oosReport)

    snapshot.buildStatus = "ready"
    snapshot.buildProgress = 1.0
    snapshot.lastError = nil
    snapshot.buildCursorTimestamp = 0
    snapshot.buildMatchesCount = 0
    snapshot.buildJobID = nil
    try? context.save()

    Self.clearCheckpoint()

    progress(1.0, "Готово: \(report.matches) матчей, \(report.bets) ставок")
    return true
  }

  func continueEnrichmentInBackground(
    chunkSize: Int = 30,
    progress: @MainActor @escaping (Int, Int, String) -> Void = { _,_,_ in }
  ) async {
    guard let container = AppDependencies.shared.container else { return }
    let context = ModelContext(container)
    let snapshot = Self.fetchOrCreate(in: context)

    let settings = AppSettings()
    let key = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty else { return }

    let client = SStatsClient(settings: settings)

    let (enrichedBefore, total) = HistoricalMarketCacheService.progress(in: context)
    snapshot.enrichmentProgress = enrichedBefore
    snapshot.enrichmentTotal = total
    snapshot.historicalCacheCount = total
    try? context.save()

    guard total > 0 else {
      progress(0, 0, "Кэш пуст — сначала соберите базу (Авто → Собрать базу)")
      return
    }
    if enrichedBefore >= total {
      progress(total, total, "Все \(total) матчей обогащены")
      return
    }

    let candidates = HistoricalMarketCacheService.candidates(limit: chunkSize, in: context)
    guard !candidates.isEmpty else {
      progress(enrichedBefore, total, "Нет кандидатов (failedAttempts ≥ 3?)")
      return
    }

    var newlyEnriched = 0
    for (i, row) in candidates.enumerated() {
      do {
        let books = try await client.fullOdds(gameId: row.numericID)
        if books.isEmpty {
          HistoricalMarketCacheService.markFailed(
            gameID: row.gameID, error: "Пустой ответ /Odds", in: context)
          continue
        }
        let markets = Self.oddsJSONFromBookmakers(books)
        if markets.isEmpty {
          HistoricalMarketCacheService.markFailed(
            gameID: row.gameID, error: "Нет market 45/80", in: context)
          continue
        }
        let data = try JSONEncoder().encode(markets)
        let hasC = markets.contains { $0.object?["marketId"]?.number == Double(MarketID.totalCorners) }
        let hasK = markets.contains { $0.object?["marketId"]?.number == Double(MarketID.totalCards) }
        HistoricalMarketCacheService.markEnriched(
          gameID: row.gameID, oddsData: data,
          hasCorners: hasC, hasCards: hasK, in: context)
        newlyEnriched += 1
      } catch {
        HistoricalMarketCacheService.markFailed(
          gameID: row.gameID, error: error.localizedDescription, in: context)
      }
      try? context.save()

      if i % 5 == 0 {
        let (e, t) = HistoricalMarketCacheService.progress(in: context)
        progress(e, t, "Обогащено \(e)/\(t)")
      }
      try? await Task.sleep(for: .milliseconds(400))
    }

    let (finalE, finalT) = HistoricalMarketCacheService.progress(in: context)
    snapshot.enrichmentProgress = finalE
    snapshot.enrichmentTotal = finalT
    snapshot.historicalCacheCount = finalT
    snapshot.builtAt = Date()
    try? context.save()

    progress(finalE, finalT,
             "Обогащено \(finalE)/\(finalT) (+\(newlyEnriched) за проход)")
  }

  private static func fillCornersCards(into mm: inout Match,
                                       from stats: [String: JSONValue]) {
    if let v = stats["cornerKicksHome"]?.number { mm.homeCorners = Int(v) }
    if let v = stats["cornerKicksAway"]?.number { mm.awayCorners = Int(v) }
    if let v = stats["yellowCardsHome"]?.number { mm.homeYellows = Int(v) }
    if let v = stats["yellowCardsAway"]?.number { mm.awayYellows = Int(v) }
    if let v = stats["redCardsHome"]?.number { mm.homeReds = Int(v) }
    if let v = stats["redCardsAway"]?.number { mm.awayReds = Int(v) }
  }

  private static func replaceHistoryRecords(
    _ history: inout [String: [TeamRecord]],
    engine: QuantEngine,
    payload: JSONValue,
    match: Match
  ) {
    if let hID = match.homeID,
       let rec = engine.teamRecord(from: payload, targetID: hID) {
      var arr = history[hID] ?? []
      if let i = arr.firstIndex(where: { $0.id == rec.id }) { arr[i] = rec }
      else { arr.append(rec) }
      history[hID] = arr
    }
    if let aID = match.awayID,
       let rec = engine.teamRecord(from: payload, targetID: aID) {
      var arr = history[aID] ?? []
      if let i = arr.firstIndex(where: { $0.id == rec.id }) { arr[i] = rec }
      else { arr.append(rec) }
      history[aID] = arr
    }
  }

  static func oddsJSONFromBookmakers(_ books: [BookmakerOdds]) -> [JSONValue] {
    var out: [JSONValue] = []
    if let pin = books.first(where: { $0.bookmakerId == SStatsClient.pinnacleBookmakerId }),
       let market = pin.odds.first(where: { $0.marketId == MarketID.totalCorners }) {
      let prices = market.odds.map { p in JSONValue.object([
        "name": .string(p.name), "value": .number(p.value),
        "bookmaker": .string(pin.bookmakerName), "bookmakerId": .number(Double(pin.bookmakerId))
      ]) }
      out.append(.object([
        "marketId": .number(Double(MarketID.totalCorners)),
        "marketName": .string(market.marketName ?? "Corners Over Under"),
        "bookmaker": .string(pin.bookmakerName),
        "bookmakerId": .number(Double(pin.bookmakerId)),
        "odds": .array(prices)
      ]))
    }
    for b in books {
      guard let market = b.odds.first(where: { $0.marketId == MarketID.totalCards }), !market.odds.isEmpty else { continue }
      let prices = market.odds.map { p in JSONValue.object([
        "name": .string(p.name), "value": .number(p.value),
        "bookmaker": .string(b.bookmakerName), "bookmakerId": .number(Double(b.bookmakerId))
      ]) }
      out.append(.object([
        "marketId": .number(Double(MarketID.totalCards)),
        "marketName": .string(market.marketName ?? "Cards Over/Under"),
        "bookmaker": .string(b.bookmakerName),
        "bookmakerId": .number(Double(b.bookmakerId)),
        "odds": .array(prices)
      ]))
    }
    return out
  }

  private static func leagueMarketSegment(
    report: WalkForwardReport,
    matches: [Match]
  ) -> [String: StoredSegmentStats] {
    var out: [String: StoredSegmentStats] = [:]
    for (key, s) in report.perLeagueMarket {
      out[key] = toStored(s)
    }
    return out
  }

  static func walkForwardDelta(_ r: WalkForwardReport) -> WalkForwardDelta {
    WalkForwardDelta(
      matches: r.matches, bets: r.bets,
      wins: r.wins, losses: r.losses, pushes: r.pushes,
      roi: r.roi, sharpe: r.sharpe, sortino: r.sortino,
      profitFactor: r.profitFactor,
      brier: r.brier, logLoss: r.logLoss, avgCLV: r.avgCLV,
      hitRate: r.hitRate)
  }

  func updateIncremental() async -> Bool {
    guard !isBuilding else { return false }
    isBuilding = true
    defer { isBuilding = false }

    guard let container = AppDependencies.shared.container else { return false }
    let context = ModelContext(container)
    let snapshot = Self.fetchOrCreate(in: context)

    guard snapshot.buildStatus == "ready", let lastTo = snapshot.toDate else {
      print("[BT] updateIncremental: снапшот ещё не готов")
      return false
    }

    let settings = AppSettings()
    let key = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty else { return false }

    let client = SStatsClient(settings: settings)
    let engine = QuantEngine()
    let backtester = WalkForwardBacktester()

    let fromDate = lastTo
    let toDate = Date()

    var monthItems: [JSONValue] = []
    var pageOffset = 0
    var pageCount = 0
    while pageCount < Self.maxPagesPerMonth {
      do {
        let r = try await client.listGamesRange(
          from: fromDate, to: toDate,
          limit: Self.gamesPerRequest, offset: pageOffset)
        let items = r.object?["data"]?.array ?? []
        if items.isEmpty { break }
        monthItems.append(contentsOf: items)
        pageOffset += Self.gamesPerRequest
        pageCount += 1
        if items.count < Self.gamesPerRequest { break }
        try? await Task.sleep(for: .milliseconds(700))
      } catch { break }
    }

    guard !monthItems.isEmpty else {
      snapshot.toDate = toDate
      try? context.save()
      return true
    }

    let json = JSONValue.object(["data": .array(monthItems)])
    let newMatches = engine.matches(from: json)
      .filter { !Self.isExcluded($0) }
      .filter { Self.isInPool($0.league) }
      .filter { $0.homeFT != nil && $0.awayFT != nil }

    var prepared: [Match] = []
    for m in newMatches {
      var mm = m
      if mm.numericID != nil { _ = HistoricalMarketCacheService.upsert(from: mm, in: context) }
      if let nid = mm.numericID, let o = try? await client.odds(numericID: nid, fresh: true) {
        let data = o.object?["data"]?.object ?? o.object ?? [:]
        let game = data["game"]?.object ?? data
        let stats = data["statistics"]?.object ?? game["statistics"]?.object ?? [:]
        mm.oddsJSON = game["odds"] ?? data["odds"]
        Self.fillCornersCards(into: &mm, from: stats)
      }
      if let nid = mm.numericID {
        do {
          let books = try await client.fullOdds(gameId: nid)
          guard !books.isEmpty else {
            HistoricalMarketCacheService.markFailed(gameID: mm.id, error: "Пустой ответ /Odds", in: context); continue
          }
          let extra = Self.oddsJSONFromBookmakers(books)
          mm.oddsJSON = .array((mm.oddsJSON?.array ?? []) + extra)
          let encoded = (try? JSONEncoder().encode(extra)) ?? Data()
          let hasC = extra.contains { $0.object?["marketId"]?.number == Double(MarketID.totalCorners) }
          let hasK = extra.contains { $0.object?["marketId"]?.number == Double(MarketID.totalCards) }
          if hasC || hasK {
            HistoricalMarketCacheService.markEnriched(gameID: mm.id, oddsData: encoded, hasCorners: hasC, hasCards: hasK, in: context)
          } else {
            HistoricalMarketCacheService.markFailed(gameID: mm.id, error: "Нет market 45/80 в /Odds", in: context)
          }
        } catch {
          HistoricalMarketCacheService.markFailed(gameID: mm.id, error: error.localizedDescription, in: context)
        }
      }
      if mm.oddsJSON?.array?.isEmpty == false { prepared.append(mm) }
      try? await Task.sleep(for: .milliseconds(400))
    }

    guard !prepared.isEmpty else {
      snapshot.toDate = toDate
      try? context.save()
      return true
    }

    let records = engine.allRecords(from: json)
    var sortedRecords = records
    for (k, v) in sortedRecords {
      sortedRecords[k] = v.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
    }

    let delta = backtester.run(matches: prepared, histories: sortedRecords)
    let encoder = JSONEncoder()

    let newLeagues = Self.mergeSegmentDict(
      snapshot.decodedLeagueStats(), delta.perLeague.mapValues { Self.toStored($0) })
    let newMarkets = Self.mergeSegmentDict(
      snapshot.decodedMarketStats(), delta.perMarket.mapValues { Self.toStored($0) })
    let newLeagueMarket = Self.mergeSegmentDict(
      snapshot.decodedLeagueMarketStats(),
      delta.perLeagueMarket.mapValues { Self.toStored($0) })
    let newEV = Self.mergeSegmentDict(
      snapshot.decodedEVBuckets(), delta.byEVBucket.mapValues { Self.toStored($0) })
    let newOdds = Self.mergeSegmentDict(
      snapshot.decodedOddsBuckets(), delta.byOddsBand.mapValues { Self.toStored($0) })
    let newClass = Self.mergeSegmentDict(
      snapshot.decodedClassification(), delta.byClassification.mapValues { Self.toStored($0) })

    snapshot.perLeagueJSON = try? encoder.encode(newLeagues)
    snapshot.perMarketJSON = try? encoder.encode(newMarkets)
    snapshot.perLeagueMarketJSON = try? encoder.encode(newLeagueMarket)
    snapshot.evBucketsJSON = try? encoder.encode(newEV)
    snapshot.oddsBucketsJSON = try? encoder.encode(newOdds)
    snapshot.classificationJSON = try? encoder.encode(newClass)

    let oldPosterior = snapshot.decodedPosteriorBuckets()
    let newPosterior = Self.mergePosterior(
      old: oldPosterior,
      delta: Self.buildPosteriorBuckets(from: delta.betRecords))
    snapshot.posteriorJSON = try? encoder.encode(newPosterior)

    let oldCornersP = snapshot.decodedPosteriorCornersBuckets()
    let newCornersP = Self.mergePosterior(
      old: oldCornersP,
      delta: Self.buildPosteriorBuckets(from: delta.betRecords.filter {
        $0.market == "CORNERS"
      }))
    snapshot.posteriorCornersJSON = try? encoder.encode(newCornersP)

    let oldCardsP = snapshot.decodedPosteriorCardsBuckets()
    let newCardsP = Self.mergePosterior(
      old: oldCardsP,
      delta: Self.buildPosteriorBuckets(from: delta.betRecords.filter {
        $0.market == "CARDS"
      }))
    snapshot.posteriorCardsJSON = try? encoder.encode(newCardsP)

    let journalDescriptor = FetchDescriptor<JournalEntry>()
    let journal = (try? context.fetch(journalDescriptor)) ?? []
    let cfg = TuningService.fetchOrCreate(in: context)
    let oosReport = OOSBuilder.build(from: journal, windowDays: cfg.oosWindowDays)
    snapshot.oosValidationJSON = try? encoder.encode(oosReport)

    snapshot.totalMatches += delta.matches
    snapshot.totalBets += delta.bets
    snapshot.toDate = toDate
    snapshot.builtAt = Date()
    try? context.save()

    return true
  }

  static func fetchOrCreate(in context: ModelContext) -> BacktestSnapshot {
    let d = FetchDescriptor<BacktestSnapshot>()
    if let existing = try? context.fetch(d).first { return existing }
    let snap = BacktestSnapshot()
    context.insert(snap); try? context.save()
    return snap
  }

  static func toStored(_ s: SegmentStats) -> StoredSegmentStats {
    StoredSegmentStats(bets: s.bets, wins: s.wins, losses: s.losses,
                       pushes: s.pushes, profit: s.profit, staked: s.staked,
                       avgOdds: s.avgOdds)
  }

  static func mergeSegmentDict(
    _ old: [String: StoredSegmentStats],
    _ delta: [String: StoredSegmentStats]
  ) -> [String: StoredSegmentStats] {
    var result = old
    for (k, v) in delta {
      if let existing = result[k] { result[k] = merge(existing, v) }
      else { result[k] = v }
    }
    return result
  }

  static func merge(_ a: StoredSegmentStats, _ b: StoredSegmentStats) -> StoredSegmentStats {
    let nb = a.bets + b.bets
    let nw = a.wins + b.wins
    let nl = a.losses + b.losses
    let np = a.pushes + b.pushes
    let npr = a.profit + b.profit
    let ns = a.staked + b.staked
    let oddsSum = a.avgOdds * Double(a.bets) + b.avgOdds * Double(b.bets)
    let navg = nb > 0 ? oddsSum / Double(nb) : 0
    return StoredSegmentStats(bets: nb, wins: nw, losses: nl, pushes: np,
                              profit: npr, staked: ns, avgOdds: navg)
  }

  static func buildPosteriorBuckets(from bets: [BetRecord]) -> [PosteriorBucket] {
    var buckets: [PosteriorBucket] = []
    for i in 0..<10 {
      let lo = Double(i) / 10.0
      let hi = Double(i + 1) / 10.0
      let inBucket = bets.filter { b in
        let idx = min(9, max(0, Int(b.probability * 10.0)))
        return idx == i
      }
      let n = inBucket.count
      let hitRate = n > 0 ? inBucket.reduce(0.0) { $0 + $1.actual } / Double(n) : 0
      buckets.append(PosteriorBucket(probabilityLow: lo, probabilityHigh: hi,
                                     n: n, factHitRate: hitRate))
    }
    return buckets
  }

  static func mergePosterior(old: [PosteriorBucket],
                             delta: [PosteriorBucket]) -> [PosteriorBucket] {
    var out: [PosteriorBucket] = []
    for i in 0..<max(old.count, delta.count) {
      let o = i < old.count ? old[i] : PosteriorBucket(
        probabilityLow: Double(i) / 10.0, probabilityHigh: Double(i + 1) / 10.0,
        n: 0, factHitRate: 0)
      let d = i < delta.count ? delta[i] : PosteriorBucket(
        probabilityLow: Double(i) / 10.0, probabilityHigh: Double(i + 1) / 10.0,
        n: 0, factHitRate: 0)
      let nN = o.n + d.n
      let ws = o.factHitRate * Double(o.n) + d.factHitRate * Double(d.n)
      let nh = nN > 0 ? ws / Double(nN) : 0
      out.append(PosteriorBucket(probabilityLow: o.probabilityLow,
                                 probabilityHigh: o.probabilityHigh,
                                 n: nN, factHitRate: nh))
    }
    return out
  }

  private static func isExcluded(_ m: Match) -> Bool {
    let x = "\(m.league) \(m.home) \(m.away)".lowercased()
    let bad = ["friendly", "women", "женщ", "u19 women", "u20 women"]
    return bad.contains(where: x.contains)
  }

  private static func isInPool(_ league: String) -> Bool {
    LeaguePool.pool.contains { lg in
      league.localizedCaseInsensitiveContains(lg.name)
    }
  }

  private static func shortDay(_ d: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: d)
  }
}
