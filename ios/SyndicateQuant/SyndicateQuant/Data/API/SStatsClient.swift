import Foundation
import Network

enum MarketID {
  static let matchWinner   = 1
  static let goals         = 5
  static let goalsHome     = 16
  static let goalsAway     = 17
  static let totalCorners  = 45
  static let totalCards    = 80
}

struct RawPrice: Codable, Hashable {
  let name: String
  let value: Double
}

struct RawMarket: Codable, Hashable {
  let marketId: Int
  let marketName: String?
  let odds: [RawPrice]
}

struct BookmakerOdds: Codable, Hashable, Identifiable {
  var id: Int { bookmakerId }
  let bookmakerId: Int
  let bookmakerName: String
  let odds: [RawMarket]
}

enum OddsQuery {
  static func find(marketId: Int,
                   selection: String,
                   line: Double?,
                   in bookmaker: BookmakerOdds) -> Double? {
    guard let market = bookmaker.odds.first(where: { $0.marketId == marketId })
    else { return nil }
    let target = selection.lowercased()
    for p in market.odds {
      let name = p.name.lowercased()
      if !(name == target || name.contains(target) || target.contains(name)) { continue }
      if let need = line {
        guard let got = extractLine(from: p.name) else { continue }
        if abs(got - need) > 0.01 { continue }
      }
      return p.value
    }
    return nil
  }

  static func extractLine(from s: String) -> Double? {
    let regex = try? NSRegularExpression(pattern: "([0-9]+(?:\\.[0-9]+)?)")
    if let m = regex?.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
       let r = Range(m.range(at: 1), in: s) {
      return Double(s[r])
    }
    return nil
  }
}

final class SStatsClient {
  private let baseURL: String
  private let apiKey: String
  private let session: URLSession

  @MainActor
  init(settings: AppSettings) {
    self.baseURL = settings.baseURL
    self.apiKey = settings.apiKey
    let cfg = URLSessionConfiguration.default
    cfg.timeoutIntervalForRequest = 30
    cfg.timeoutIntervalForResource = 60
    cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
    cfg.waitsForConnectivity = false
    cfg.httpAdditionalHeaders = [
      "Accept": "application/json",
      "User-Agent": "SyndicateQuant-iOS/6.0.0 (iPhone; iOS)",
      "Accept-Language": "en-US,en;q=0.9",
    ]
    self.session = URLSession(configuration: cfg)
  }

  // MARK: - Public API

  func listToday(fresh: Bool = false) async throws -> JSONValue {
    try await get("/Games/list", query: [
      "Date": Self.dateString(Date()),
      "TimeZone": "3",
      "Order": "-1",
      "Limit": "1000",
    ], fresh: fresh)
  }

  func listOn(date: Date, upcoming: Bool = false) async throws -> JSONValue {
    var q: [String: String] = [
      "Date": Self.dateString(date),
      "TimeZone": "3",
      "Order": "-1",
      "Limit": "1000",
    ]
    if upcoming { q["Upcoming"] = "true" }
    return try await get("/Games/list", query: q)
  }

  func listGamesRange(
    from: Date, to: Date, limit: Int = 1000, offset: Int = 0
  ) async throws -> JSONValue {
    try await get("/Games/list", query: [
      "From": Self.dateString(from),
      "To": Self.dateString(to),
      "Ended": "true",
      "Offset": String(offset),
      "Limit": String(min(limit, 1000)),
      "TimeZone": "3",
      "Order": "1",
    ])
  }

  func listRange(
    from: Date, to: Date, limit: Int = 1000, offset: Int = 0
  ) async throws -> JSONValue {
    try await listGamesRange(from: from, to: to, limit: limit, offset: offset)
  }

  func listTeam(_ teamID: String, limit: Int = 25) async throws -> JSONValue {
    try await get("/Games/list", query: [
      "Team": teamID,
      "Ended": "true",
      "Limit": String(min(limit, 1000)),
      "Order": "-1",
      "TimeZone": "3",
    ])
  }

  func gameInfo(_ id: String, fresh: Bool = false) async throws -> JSONValue {
    try await get("/Games/\(id)", query: ["TimeZone": "3"], fresh: fresh)
  }

  func glicko(_ id: String) async throws -> JSONValue {
    try await get("/Games/glicko/\(id)", query: [:])
  }

  func fullOdds(gameId: Int, fresh: Bool = false) async throws -> [BookmakerOdds] {
    let json = try await get("/Odds/\(gameId)", query: [:], fresh: fresh)
    return Self.parseBookmakers(from: json)
  }

  static func parseBookmakers(from json: JSONValue) -> [BookmakerOdds] {
    let arr = json.object?["data"]?.array ?? json.array ?? []
    var out: [BookmakerOdds] = []
    for bv in arr {
      guard let b = bv.object,
            let bid = b["bookmakerId"]?.number,
            let bname = b["bookmakerName"]?.string,
            let markets = b["odds"]?.array
      else { continue }
      var rawMarkets: [RawMarket] = []
      for mv in markets {
        guard let m = mv.object,
              let mid = m["marketId"]?.number,
              let prices = m["odds"]?.array
        else { continue }
        let mname = m["marketName"]?.string
        var rawPrices: [RawPrice] = []
        for pv in prices {
          guard let p = pv.object,
                let name = p["name"]?.string,
                let value = p["value"]?.number
          else { continue }
          rawPrices.append(RawPrice(name: name, value: value))
        }
        rawMarkets.append(RawMarket(marketId: Int(mid),
                                     marketName: mname,
                                     odds: rawPrices))
      }
      out.append(BookmakerOdds(bookmakerId: Int(bid),
                                bookmakerName: bname,
                                odds: rawMarkets))
    }
    return out
  }

  static func bestPrice(marketId: Int,
                        selection: String,
                        line: Double?,
                        across books: [BookmakerOdds]) -> (value: Double, bookmaker: String)? {
    var best: (value: Double, bookmaker: String)? = nil
    for b in books {
      if let v = OddsQuery.find(marketId: marketId,
                                 selection: selection,
                                 line: line,
                                 in: b),
         v > 1 {
        if best == nil || v > best!.value {
          best = (v, b.bookmakerName)
        }
      }
    }
    return best
  }

  static func sharpPrice(marketId: Int,
                         selection: String,
                         line: Double?,
                         bookmakerId: Int,
                         across books: [BookmakerOdds]) -> (value: Double, bookmaker: String)? {
    guard let b = books.first(where: { $0.bookmakerId == bookmakerId }),
          let v = OddsQuery.find(marketId: marketId,
                                  selection: selection,
                                  line: line,
                                  in: b),
          v > 1
    else { return nil }
    return (v, b.bookmakerName)
  }

  static let pinnacleBookmakerId = 4

  func oddsLive(numericID: Int) async throws -> JSONValue? {
    try await odds(numericID: numericID, fresh: true)
  }

  func odds(numericID: Int, fresh: Bool = false) async throws -> JSONValue {
    try await get("/Games/\(numericID)", query: ["TimeZone": "3"], fresh: fresh)
  }

  // MARK: - Team history

  func fetchTeamHistory(teamID: String, count: Int = 15) async -> [TeamRecord] {
    do {
      let list = try await listTeam(teamID, limit: max(count * 3, 30))
      var rows = recordsFromList(list, targetID: teamID)
      if rows.count < min(6, count) {
        let ids = matches(from: list).prefix(count).map { $0.id }
        for id in ids {
          if let r = try? await gameInfo(id),
             let x = QuantEngine().teamRecord(from: r, targetID: teamID) {
            rows.append(x)
          }
        }
      }
      var unique = [String: TeamRecord]()
      for r in rows { unique[r.id] = r }
      return Array(unique.values)
        .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        .prefix(count).map { $0 }
    } catch { return [] }
  }

  func fetchTeamHistoryEnriched(teamID: String, count: Int = 5) async -> [TeamRecord] {
    do {
      let list = try await listTeam(teamID, limit: max(count * 2, 15))
      let ids = matches(from: list).prefix(count).map { $0.id }
      let engine = QuantEngine()
      var out: [TeamRecord] = []
      var seen = Set<String>()
      for id in ids {
        guard !seen.contains(id) else { continue }
        seen.insert(id)
        if let payload = try? await gameInfo(id),
           let rec = engine.teamRecord(from: payload, targetID: teamID) {
          out.append(rec)
        }
        try? await Task.sleep(for: .milliseconds(300))
      }
      return out.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    } catch { return [] }
  }

  func fetchH2H(homeID: String, awayID: String,
                homeName: String, awayName: String,
                count: Int = 3) async -> [TeamRecord] {
    let engine = QuantEngine()
    let target = max(count, 5)

    if let list = try? await listTeam(homeID, limit: target * 4) {
      let items = matches(from: list)
      let h2hGames = items.filter { m in
        (m.homeID == awayID && m.awayID == homeID) ||
        (m.homeID == homeID && m.awayID == awayID)
      }.prefix(target)
      var out: [TeamRecord] = []
      for m in h2hGames {
        if let payload = try? await gameInfo(m.id),
           let rec = engine.teamRecord(from: payload, targetID: homeID) {
          out.append(rec)
        }
        try? await Task.sleep(for: .milliseconds(300))
      }
      if !out.isEmpty {
        return out.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
      }
    }

    if let list = try? await listTeam(awayID, limit: target * 4) {
      let items = matches(from: list)
      let h2hGames = items.filter { m in
        (m.homeID == awayID && m.awayID == homeID) ||
        (m.homeID == homeID && m.awayID == awayID)
      }.prefix(target)
      var out: [TeamRecord] = []
      for m in h2hGames {
        if let payload = try? await gameInfo(m.id),
           let rec = engine.teamRecord(from: payload, targetID: awayID) {
          out.append(rec)
        }
        try? await Task.sleep(for: .milliseconds(300))
      }
      if !out.isEmpty {
        return out.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
      }
    }
    return []
  }

  // MARK: - Cache policy

  private static func ttl(for path: String) -> TimeInterval {
    if path.hasPrefix("/Games/list") { return 15 * 60 }
    if path.hasPrefix("/Games/glicko") { return 6 * 3600 }
    if path.hasPrefix("/Odds/") { return 30 * 60 }
    if path.hasPrefix("/Games/") { return 30 * 60 }
    return 5 * 60
  }

  private static func makeCacheKey(path: String, query: [String: String]) -> String {
    let q = query
      .filter { $0.key.lowercased() != "apikey" }
      .sorted { $0.key < $1.key }
      .map { "\($0.key)=\($0.value)" }
      .joined(separator: "&")
    return path + "?" + q
  }

  // MARK: - Networking core

  private func get(
    _ path: String, query: [String: String], attempt: Int = 0, fresh: Bool = false
  ) async throws -> JSONValue {
    let cacheKey = Self.makeCacheKey(path: path, query: query)
    let coalesceKey = fresh ? cacheKey + "|fresh" : cacheKey
    if !fresh, let cached = await ResponseCache.shared.get(key: cacheKey) { return cached }
    if !NetworkMonitor.shared.isOnline {
      throw APIError.server("Нет соединения с интернетом")
    }

    let baseURL = self.baseURL
    let apiKey = self.apiKey
    let session = self.session
    let ttlValue = Self.ttl(for: path)

    return try await RequestCoalescer.shared.coalesce(key: coalesceKey) {
      await RateLimiter.shared.acquire()
      let json = try await Self.performGet(
        path: path, query: query, attempt: attempt,
        baseURL: baseURL, apiKey: apiKey, session: session)
      if !fresh {
        await ResponseCache.shared.set(key: cacheKey, json: json, ttl: ttlValue)
      }
      return json
    }
  }

  private static func performGet(
    path: String, query: [String: String], attempt: Int,
    baseURL: String, apiKey: String, session: URLSession
  ) async throws -> JSONValue {
    guard var c = URLComponents(string: baseURL + path) else {
      throw APIError.invalidURL
    }
    var items = query.map { URLQueryItem(name: $0.key, value: $0.value) }
    if !apiKey.isEmpty {
      items.append(URLQueryItem(name: "apikey", value: apiKey))
    }
    c.queryItems = items
    guard let url = c.url else { throw APIError.invalidURL }

    var req = URLRequest(url: url)
    req.httpMethod = "GET"
    req.timeoutInterval = 30

    do {
      let (data, response) = try await session.data(for: req)
      guard let http = response as? HTTPURLResponse else {
        throw APIError.invalidResponse
      }

      if http.statusCode == 429 {
        let retryAfter = http.value(forHTTPHeaderField: "Retry-After")
          .flatMap { TimeInterval($0) }
        await RateLimiter.shared.register429(retryAfter: retryAfter)
        if attempt < 3 {
          let wait = retryAfter ?? min(60, 2.0 * pow(2, Double(attempt)))
          try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
          return try await performGet(
            path: path, query: query, attempt: attempt + 1,
            baseURL: baseURL, apiKey: apiKey, session: session)
        }
        throw APIError.rateLimited
      }

      guard (200..<300).contains(http.statusCode) else {
        let body = String(data: data, encoding: .utf8) ?? ""
        throw APIError.server("SStats HTTP \(http.statusCode): \(body.prefix(200))")
      }

      await RateLimiter.shared.onSuccess()
      return try JSONValue(data: data)
    } catch let urlErr as URLError {
      print("[SStats] URLError code=\(urlErr.code.rawValue) url=\(url.absoluteString)")
      let retriable: Set<URLError.Code> = [
        .networkConnectionLost, .cannotConnectToHost, .cannotFindHost,
      ]
      if retriable.contains(urlErr.code) && attempt < 2 {
        try? await Task.sleep(nanoseconds: UInt64(500 * (attempt + 1)) * 1_000_000)
        return try await performGet(
          path: path, query: query, attempt: attempt + 1,
          baseURL: baseURL, apiKey: apiKey, session: session)
      }
      throw APIError.server("Сеть: \(urlErr.code.rawValue) — \(urlErr.localizedDescription)")
    } catch {
      print("[SStats] Error: \(error) url=\(url.absoluteString)")
      throw error
    }
  }

  // MARK: - Helpers

  private func matches(from json: JSONValue) -> [Match] {
    QuantEngine().matches(from: json)
  }

  private func recordsFromList(_ json: JSONValue, targetID: String) -> [TeamRecord] {
    var out: [TeamRecord] = []
    let items: [JSONValue] =
      json.object?["data"]?.array ?? json.allObjects().map { .object($0) }
    for item in items {
      guard let o = item.object else { continue }
      let homeID = teamID(o, "home")
      let awayID = teamID(o, "away")
      guard homeID == targetID || awayID == targetID else { continue }
      let home = homeID == targetID
      let pref = home ? "home" : "away"
      let opp = home ? "away" : "home"
      let stats = o["statistics"]?.object ?? o
      // [W1-#5] Добавлены reds/oppReds для модели CARDS.
      let rec = TeamRecord(
        id: string(o, ["id", "Id", "gameId", "game_id", "eventId", "flashId"]) ?? UUID().uuidString,
        date: date(o),
        gf: number(o, [pref + "FTResult", pref + "Result", pref + "Score", pref + "Goals"]),
        ga: number(o, [opp + "FTResult", opp + "Result", opp + "Score", opp + "Goals"]),
        corners: number(stats, ["cornerKicks" + (home ? "Home" : "Away"),
                                pref + "Corners", "corners"]),
        oppCorners: number(stats, ["cornerKicks" + (home ? "Away" : "Home"), opp + "Corners"]),
        cards: number(stats, ["yellowCards" + (home ? "Home" : "Away"),
                              pref + "Cards", "cards"]),
        oppCards: number(stats, ["yellowCards" + (home ? "Away" : "Home"), opp + "Cards"]),
        fouls: number(stats, ["fouls" + (home ? "Home" : "Away"), pref + "Fouls", "fouls"]),
        oppFouls: number(stats, ["fouls" + (home ? "Away" : "Home"), opp + "Fouls"]),
        shots: number(stats, ["totalShots" + (home ? "Home" : "Away"), "shots"]),
        sot: number(stats, ["shotsOnGoal" + (home ? "Home" : "Away"), "sot"]),
        possession: number(stats, ["ballPossession" + (home ? "Home" : "Away"), "possession"]),
        xg: number(stats, ["expectedGoals" + (home ? "Home" : "Away"), "xg"]),
        oppXg: number(stats, ["expectedGoals" + (home ? "Away" : "Home"), "opp_xg"]),
        referee: string(o, ["refereeName", "referee"]),
        isHome: home,
        players: parsePlayers(o: o, stats: stats, side: pref),
        reds: number(stats, ["redCards" + (home ? "Home" : "Away"),
                             pref + "Reds", "reds"]),
        oppReds: number(stats, ["redCards" + (home ? "Away" : "Home"),
                                opp + "Reds"]))
      if rec.gf != nil || rec.ga != nil { out.append(rec) }
    }
    return out
  }

  private func parsePlayers(
    o: [String: JSONValue], stats: [String: JSONValue], side: String
  ) -> [PlayerRow] {
    let candidates: [JSONValue?] = [
      o[side + "Players"], o[side + "Lineup"],
      o["players_" + side], o["lineup_" + side],
      o["players"], o["lineups"],
      stats[side + "Players"], stats["players"],
    ]
    for v in candidates {
      guard let arr = v?.array, !arr.isEmpty else { continue }
      let rows = arr.compactMap { parsePlayer($0, side: side) }
      if !rows.isEmpty { return rows }
    }
    return []
  }

  private func parsePlayer(_ v: JSONValue, side: String) -> PlayerRow? {
    guard let o = v.object else { return nil }
    if let team = string(o, ["side", "team", "teamSide"])?.lowercased() {
      if team.contains("home") && side == "away" { return nil }
      if team.contains("away") && side == "home" { return nil }
    }
    let id = string(o, ["id", "Id", "playerId", "player_id", "uid", "flashId"]) ?? ""
    let name = string(o, ["name", "Name", "playerName", "shortName"]) ?? ""
    guard !id.isEmpty || !name.isEmpty else { return nil }
    let resolvedID = id.isEmpty ? name : id
    return PlayerRow(
      id: resolvedID, name: name,
      minutes: number(o, ["minutes", "min", "played", "minutesPlayed"]) ?? 0,
      xg: number(o, ["xg", "expectedGoals", "xG"]) ?? 0,
      xa: number(o, ["xa", "expectedAssists", "xA"]) ?? 0,
      goals: number(o, ["goals", "g", "scored"]) ?? 0,
      assists: number(o, ["assists", "a"]) ?? 0,
      shots: number(o, ["shots", "totalShots", "shotsTotal"]) ?? 0,
      sot: number(o, ["sot", "shotsOnGoal", "shotsOnTarget"]) ?? 0,
      starts: Int(number(o, ["starts", "isStarter", "started"]) ?? 0))
  }

  private func teamID(_ o: [String: JSONValue], _ side: String) -> String? {
    if let x = o[side + "Team"]?.object {
      if let n = x["id"]?.number { return String(Int(n)) }
      if let s = string(x, ["id", "teamid", "team_id", "flashid"]), !s.isEmpty { return s }
    }
    if let s = string(o, [side + "TeamId", side + "Id"]), !s.isEmpty { return s }
    if let n = o[side + "TeamId"]?.number { return String(Int(n)) }
    return nil
  }

  private func string(_ o: [String: JSONValue], _ keys: [String]) -> String? {
    for k in keys { if let s = o[k]?.string { return s } }
    return nil
  }

  private func number(_ o: [String: JSONValue], _ keys: [String]) -> Double? {
    for k in keys { if let n = o[k]?.number { return n } }
    return nil
  }

  private func date(_ o: [String: JSONValue]) -> Date? {
    if let s = string(o, ["date", "Date", "dateUtc", "startTime", "StartTime", "datetime"]) {
      let f = ISO8601DateFormatter()
      if let d = f.date(from: s) { return d }
      f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      if let d = f.date(from: s) { return d }
      if let t = Double(s) {
        return Date(timeIntervalSince1970: t > 1e11 ? t / 1000 : t)
      }
    }
    return nil
  }

  private static func dateString(_ date: Date) -> String {
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .gregorian)
    f.dateFormat = "yyyy-MM-dd"
    f.timeZone = TimeZone(secondsFromGMT: 3 * 3600)
    return f.string(from: date)
  }
}
