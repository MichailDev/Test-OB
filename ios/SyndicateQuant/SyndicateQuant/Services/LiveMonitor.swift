import Foundation
import SwiftData

@MainActor
final class LiveMonitor: ObservableObject {
  static let shared = LiveMonitor()
  @Published private(set) var snapshots: [String: OddsSnapshot] = [:]
  private var previous: [String: OddsSnapshot] = [:]
  @Published private(set) var movements: [LineMovement] = []
  @Published private(set) var isRunning: Bool = false
  @Published private(set) var lastTick: Date?
  @Published private(set) var lastError: String?
  @Published private(set) var preMatchSnapshotsSaved: Int = 0

  private var observed: [String: ObservedGame] = [:]
  private var task: Task<Void, Never>?
  private var cycleCounter: Int = 0
  private var cachedContext: ModelContext?

  private let fullOddsEveryNCycles = 5

  private init() {}

  func observe(gameID: String, numericID: Int?,
               startTime: Date? = nil,
               league: String = "",
               home: String = "",
               away: String = "") {
    observed[gameID] = ObservedGame(
      numericID: numericID, startTime: startTime,
      league: league, home: home, away: away)
  }

  func clearObserved() {
    observed.removeAll(); snapshots.removeAll()
    previous.removeAll(); movements.removeAll()
    preMatchSnapshotsSaved = 0
    cycleCounter = 0
  }

  func previousSnapshotForDebug(matchID: String) -> OddsSnapshot? { return previous[matchID] }

  func start(settings: AppSettings) {
    guard settings.liveMonitorEnabled else { return }
    guard !isRunning else { return }
    isRunning = true
    lastError = nil
    let interval = max(30, min(300, settings.liveMonitorIntervalSec))
    task = Task { [weak self] in
      await self?.tick(settings: settings)
      while !Task.isCancelled {
        let ns = UInt64(interval) * 1_000_000_000
        try? await Task.sleep(nanoseconds: ns)
        if Task.isCancelled { break }
        await self?.tick(settings: settings)
      }
    }
  }

  func stop() { task?.cancel(); task = nil; isRunning = false }

  private func tick(settings: AppSettings) async {
    let key = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty else { lastError = "API key не задан"; return }

    let client = SStatsClient(settings: settings)
    var newSnapshots: [String: OddsSnapshot] = [:]
    var newMovements: [LineMovement] = []

    cycleCounter += 1
    let doFullFetch = (cycleCounter % fullOddsEveryNCycles == 0)
    let now = Date()

    for (gameID, obs) in observed {
      guard let nid = obs.numericID else { continue }

      let parsed: [String: [String: Double]]
      if doFullFetch {
        guard let books = try? await client.fullOdds(gameId: nid, fresh: true),
              !books.isEmpty else { continue }
        parsed = Self.parseFullBooksToDict(books)
      } else {
        guard let raw = try? await client.odds(numericID: nid, fresh: true) else { continue }
        parsed = Self.parseOddsByBook(raw)
      }
      guard !parsed.isEmpty else { continue }

      let snap = OddsSnapshot(gameID: gameID, numericID: nid,
                              takenAt: now, byKey: parsed)

      if let prev = previous[gameID] {
        for (k, _) in parsed {
          let parts = k.split(separator: "|").map(String.init)
          let market = parts.first ?? ""
          let selection = parts.count > 1 ? parts[1] : ""
          let line: Double? = parts.count > 2 ? Double(parts[2]) : nil
          guard let prevAvg = prev.avg(forKey: k),
                let curAvg = snap.avg(forKey: k),
                prevAvg > 1, curAvg > 1 else { continue }
          let delta = (curAvg - prevAvg) / prevAvg
          let moving = snap.booksMoving(forKey: k, vs: prev, threshold: 0.01)
          let isSharp = moving.count >= 3 && abs(delta) > 0.02
          newMovements.append(LineMovement(
            key: k, market: market, selection: selection, line: line,
            previousAvg: prevAvg, currentAvg: curAvg,
            delta: delta, booksAgreeing: moving.count, isSharp: isSharp))
        }
      }

      if settings.preMatchHistoryEnabled,
         let startTime = obs.startTime,
         startTime > now {
        let minutes = Int(startTime.timeIntervalSince(now) / 60.0)
        if let bucket = LineSnapshotService.bucket(
            minutesToStart: minutes,
            maxWindow: settings.preMatchCaptureWindowMin),
           let ctx = persistContext() {
          for (k, byBook) in parsed {
            let parts = k.split(separator: "|").map(String.init)
            guard parts.count >= 2 else { continue }
            let market = parts[0]
            let selection = parts[1]
            let line: Double? = parts.count > 2 ? Double(parts[2]) : nil
            let didSave = LineSnapshotService.save(
              gameID: gameID, numericID: nid,
              market: market, selection: selection, line: line,
              startTime: startTime, league: obs.league,
              home: obs.home, away: obs.away,
              bucketMinutes: bucket, minutesToStart: minutes,
              byBook: byBook, in: ctx)
            if didSave { preMatchSnapshotsSaved += 1 }
          }
          try? ctx.save()
        }
      }

      previous[gameID] = snap
      newSnapshots[gameID] = snap
    }

    self.snapshots = newSnapshots
    self.movements = newMovements.sorted { abs($0.delta) > abs($1.delta) }
    self.lastTick = Date()
    self.lastError = newSnapshots.isEmpty
      ? (observed.isEmpty ? "Нет активных матчей" : "Не удалось получить котировки") : nil
  }

  private func persistContext() -> ModelContext? {
    if let c = cachedContext { return c }
    guard let container = AppDependencies.shared.container else { return nil }
    let c = ModelContext(container)
    cachedContext = c
    return c
  }

  static func parseFullBooksToDict(_ books: [BookmakerOdds]) -> [String: [String: Double]] {
    var out: [String: [String: Double]] = [:]
    for b in books {
      for m in b.odds {
        let market: String
        switch m.marketId {
        case MarketID.goals, MarketID.goalsHome, MarketID.goalsAway:
          market = "GOALS"
        case MarketID.totalCorners:
          market = "CORNERS"
        case MarketID.totalCards:
          market = "CARDS"
        default:
          continue
        }
        for p in m.odds {
          let line = OddsQuery.extractLine(from: p.name)
          let key = "\(market)|\(p.name.lowercased())|\(line.map { String($0) } ?? "")"
          var byBook = out[key] ?? [:]
          let bidStr = String(b.bookmakerId)
          byBook[bidStr] = max(byBook[bidStr] ?? 0, p.value)
          out[key] = byBook
        }
      }
    }
    return out
  }

  static func parseOddsByBook(_ json: JSONValue) -> [String: [String: Double]] {
    var out: [String: [String: Double]] = [:]
    let data = json.object?["data"]?.object ?? json.object ?? [:]
    let game = data["game"]?.object ?? data
    let items: [JSONValue] = {
      if let arr = game["odds"]?.array { return arr }
      if let arr = data["odds"]?.array { return arr }
      if let arr = json.array { return arr }
      return []
    }()

    for mv in items {
      guard let m = mv.object else { continue }
      let marketId = m["marketId"]?.number.map { Int($0) }
      let marketName = (m["marketName"]?.string ?? "").lowercased()
      guard let prices = m["odds"]?.array else { continue }
      for pv in prices {
        guard let p = pv.object else { continue }
        guard let value = numberFrom(p, ["value", "odds", "price"]),
              value > 1, value < 1000 else { continue }
        let selName = (p["name"]?.string ?? "")
        let market = normalizeLiveMarket(marketId, marketName, selName)
        guard !market.isEmpty else { continue }
        let line = extractLineFrom(selName) ?? extractLineFrom(marketName)
        let book = "sstats"
        let key = "\(market)|\(selName.lowercased())|\(line.map { String($0) } ?? "")"
        var byBook = out[key] ?? [:]
        byBook[book] = max(byBook[book] ?? 0, value)
        out[key] = byBook
      }
    }
    return out
  }

  private static func normalizeLiveMarket(_ id: Int?, _ name: String, _ sel: String) -> String {
    if let id {
      switch id {
      case MarketID.matchWinner: return "1X2"
      case MarketID.goals,
           MarketID.goalsHome,
           MarketID.goalsAway: return "GOALS"
      case MarketID.totalCorners: return "CORNERS"
      case MarketID.totalCards: return "CARDS"
      default: break
      }
    }
    let s = (name + " " + sel).lowercased()
    if s.contains("corner") { return "CORNERS" }
    if s.contains("card") || s.contains("yellow") { return "CARDS" }
    if s.contains("goal") || s.contains("total")
        || s.contains("over") || s.contains("under") { return "GOALS" }
    if s.contains("1x2") || s.contains("winner")
        || s.contains("home") || s.contains("draw") || s.contains("away") { return "1X2" }
    return ""
  }

  private static func extractLineFrom(_ s: String) -> Double? {
    let regex = try? NSRegularExpression(pattern: "([0-9]+(?:\\.[0-9]+)?)")
    if let m = regex?.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
       let r = Range(m.range(at: 1), in: s) { return Double(s[r]) }
    return nil
  }

  private static func numberFrom(_ o: [String: JSONValue], _ keys: [String]) -> Double? {
    for k in keys { if let n = o[k]?.number { return n } }
    return nil
  }

  // [W2b] Market regime. Принимает словарь [gameID: OddsSnapshot].
  static func classifyRegime(snapshots: [String: OddsSnapshot],
                             movements: [LineMovement]) -> MarketRegimeReport {
    guard !snapshots.isEmpty else {
      return MarketRegimeReport(
        regime: .unknown, avgBooksPerMarket: 0, avgSpreadPct: 0,
        sharpMovements: 0, totalMovements: 0,
        note: "Нет активных котировок — запустите live-монитор")
    }

    var spreads: [Double] = []
    var bookCounts: [Int] = []
    for snap in snapshots.values {
      for (_, byBook) in snap.byKey {
        bookCounts.append(byBook.count)
        if byBook.count >= 2 {
          let vals = Array(byBook.values)
          let mn = vals.min() ?? 1
          let mx = vals.max() ?? 1
          if mn > 1 { spreads.append((mx - mn) / mn) }
        }
      }
    }
    let avgSpread = spreads.isEmpty ? 0 : spreads.reduce(0, +) / Double(spreads.count)
    let avgBooks = bookCounts.isEmpty
      ? 0 : Double(bookCounts.reduce(0, +)) / Double(bookCounts.count)

    let total = movements.count
    let sharp = movements.filter { $0.isSharp }.count
    let bigMovers = movements.filter { abs($0.delta) > 0.02 }.count

    let regime: MarketRegime
    let note: String
    if total == 0 {
      regime = .normal
      note = "Движений пока нет — базовый цикл"
    } else if sharp >= 3 && total >= 3 {
      regime = .lineDislocation
      note = "\(sharp) sharp-движений на \(total) — резкий переезд линий в 3+ книгах"
    } else if avgBooks > 0 && avgBooks < 4 {
      regime = .lowLiquidity
      note = String(format: "Средне %.1f книг/рынок — тонкий рынок, котировки менее надёжны", avgBooks)
    } else if bigMovers >= 5 || avgSpread > 0.10 {
      regime = .highVolatility
      note = String(format: "%d крупных движений, средний спред %.1f%% — рынок волатильный",
                    bigMovers, avgSpread * 100)
    } else {
      regime = .normal
      note = "Штатный режим рынка"
    }
    return MarketRegimeReport(
      regime: regime,
      avgBooksPerMarket: avgBooks,
      avgSpreadPct: avgSpread,
      sharpMovements: sharp,
      totalMovements: total,
      note: note)
  }
}
