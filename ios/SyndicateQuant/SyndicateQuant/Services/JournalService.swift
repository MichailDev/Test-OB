import Foundation
import SwiftData

enum JournalService {
  @MainActor
  static func settleOpenEntries(context: ModelContext, client: SStatsClient)
    async -> (closed: Int, failed: Int) {
    let descriptor = FetchDescriptor<JournalEntry>()
    guard let all = try? context.fetch(descriptor) else { return (0, 0) }
    let open = all.filter { $0.status == "OPEN" }
    var closed = 0; var failed = 0

    for entry in open {
      guard let info = try? await client.gameInfo(entry.gameID, fresh: true) else {
        failed += 1; continue
      }
      let data = info.object?["data"]?.object ?? info.object ?? [:]
      let game = data["game"]?.object ?? data
      let stats = data["statistics"]?.object ?? game["statistics"]?.object ?? [:]

      guard let result = resolveResult(entry: entry, game: game, stats: stats)
      else { continue }

      entry.result = result
      entry.profit = computeProfit(result: result, odds: entry.odds, stake: entry.stake)

      if entry.market == "CORNERS" || entry.market == "CARDS" {
        if let nid = Int(entry.gameID),
           let books = try? await client.fullOdds(gameId: nid, fresh: true),
           let closing = findClosingInBookmakers(entry: entry, books: books),
           closing > 1 {
          entry.closingOdds = closing
          entry.clv = entry.odds / closing - 1
          if let openOdds = entry.openingOdds, openOdds > 1 {
            entry.movement = openOdds / closing - 1
          }
        }
      } else {
        if let closingOdds = extractClosingOdds(data: data, entry: entry),
           closingOdds > 1 {
          entry.closingOdds = closingOdds
          entry.clv = entry.odds / closingOdds - 1
          if let openOdds = entry.openingOdds, openOdds > 1 {
            entry.movement = openOdds / closingOdds - 1
          }
        }
      }

      entry.status = "CLOSED"
      closed += 1

      if entry.market == "1X2" || entry.market == "GOALS" {
        if let hFT = number(game, ["homeFTResult", "homeResult"]),
           let aFT = number(game, ["awayFTResult", "awayResult"]) {
          let ids = extractTeamIDs(from: game)
          if let hID = ids.home, let aID = ids.away {
            TeamRatingService.update(context: context,
              homeTeamID: hID, homeName: entry.home,
              awayTeamID: aID, awayName: entry.away,
              homeGoals: hFT, awayGoals: aFT)
          }
        }
      }
      try? await Task.sleep(for: .milliseconds(300))
    }
    try? context.save()
    return (closed, failed)
  }

  private static func resolveResult(entry: JournalEntry,
                                    game: [String: JSONValue],
                                    stats: [String: JSONValue]) -> String? {
    switch entry.market {
    case "1X2", "GOALS":
      guard let h = number(game, ["homeFTResult", "homeResult"]),
            let a = number(game, ["awayFTResult", "awayResult"]) else { return nil }
      return evaluateResult(entry: entry, home: h, away: a)
    case "CORNERS":
      guard let hc = number(stats, ["cornerKicksHome"]),
            let ac = number(stats, ["cornerKicksAway"]) else { return nil }
      return evaluateResult(entry: entry, home: hc, away: ac)
    case "CARDS":
      guard let hy = number(stats, ["yellowCardsHome"]),
            let ay = number(stats, ["yellowCardsAway"]) else { return nil }
      let hr = number(stats, ["redCardsHome"]) ?? 0
      let ar = number(stats, ["redCardsAway"]) ?? 0
      return evaluateResult(entry: entry, home: hy + hr, away: ay + ar)
    default:
      return nil
    }
  }

  private static func evaluateResult(entry: JournalEntry,
                                     home: Double, away: Double) -> String {
    let sel = entry.selection.lowercased()
    if entry.market == "1X2" {
      let win: Bool
      if sel.contains("home") || sel == "1" { win = home > away }
      else if sel.contains("draw") || sel == "x" { win = home == away }
      else { win = away > home }
      return win ? "WIN" : "LOSS"
    }
    if entry.market == "GOALS" || entry.market == "CORNERS" || entry.market == "CARDS" {
      guard let line = entry.line else { return "VOID" }
      let total = home + away
      let isOver = sel.contains("over") || sel.hasPrefix("o")
      if abs(line.rounded() - line) < 0.001, Double(Int(line)) == total {
        return "PUSH"
      }
      let hit = isOver ? total > line : total < line
      return hit ? "WIN" : "LOSS"
    }
    return "VOID"
  }

  private static func computeProfit(result: String, odds: Double, stake: Double) -> Double {
    switch result {
    case "WIN": return stake * (odds - 1)
    case "LOSS": return -stake
    case "PUSH": return 0
    default: return 0
    }
  }

  private static func extractClosingOdds(data: [String: JSONValue],
                                         entry: JournalEntry) -> Double? {
    guard let oddsArr = data["odds"]?.array else { return nil }
    let targetMarket = entry.market
    let targetSelection = entry.selection.lowercased()
    let targetLine = entry.line

    for mv in oddsArr {
      guard let m = mv.object else { continue }
      let marketId = m["marketId"]?.number.map { Int($0) }
      let marketName = (m["marketName"]?.string ?? "").lowercased()
      let normalized = normalizeMarketByIDAndName(marketId, marketName)
      guard normalized == targetMarket else { continue }
      guard let prices = m["odds"]?.array else { continue }

      for pv in prices {
        guard let p = pv.object,
              let selName = p["name"]?.string?.lowercased(),
              let value = number(p, ["value", "odds", "price"]),
              value > 1
        else { continue }
        if let line = targetLine {
          if !containsLine(selName, line: line) { continue }
        }
        if targetMarket == "1X2" {
          if !selName.contains(targetSelection) { continue }
        } else {
          let isOver = targetSelection.contains("over") || targetSelection.hasPrefix("o")
          let isUnder = targetSelection.contains("under") || targetSelection.hasPrefix("u")
          if isOver && !(selName.contains("over") || selName.hasPrefix("o")) { continue }
          if isUnder && !(selName.contains("under") || selName.hasPrefix("u")) { continue }
        }
        return value
      }
    }
    return nil
  }

  private static func findClosingInBookmakers(entry: JournalEntry,
                                              books: [BookmakerOdds]) -> Double? {
    let marketId: Int
    switch entry.market {
    case "CORNERS": marketId = MarketID.totalCorners
    case "CARDS":   marketId = MarketID.totalCards
    default: return nil
    }
    return SStatsClient.bestPrice(marketId: marketId,
                                  selection: entry.selection,
                                  line: entry.line,
                                  across: books)?.value
  }

  private static func normalizeMarketByIDAndName(_ id: Int?, _ name: String) -> String {
    if let id {
      switch id {
      case MarketID.matchWinner:    return "1X2"
      case MarketID.goals,
           MarketID.goalsHome,
           MarketID.goalsAway:      return "GOALS"
      case MarketID.totalCorners:   return "CORNERS"
      case MarketID.totalCards:     return "CARDS"
      default:                      return ""
      }
    }
    let n = name.lowercased()
    if n.contains("corner") { return "CORNERS" }
    if n.contains("card") || n.contains("yellow") { return "CARDS" }
    if n.contains("goal") || n.contains("total")
        || n.contains("over") || n.contains("under") { return "GOALS" }
    if n.contains("1x2") || n.contains("winner") { return "1X2" }
    return ""
  }

  private static func extractTeamIDs(from game: [String: JSONValue])
    -> (home: String?, away: String?) {
    func extract(_ side: String) -> String? {
      if let t = game[side + "Team"]?.object {
        if let n = t["id"]?.number { return String(Int(n)) }
        if let s = t["id"]?.string, !s.isEmpty { return s }
      }
      if let s = game[side + "TeamId"]?.string, !s.isEmpty { return s }
      if let n = game[side + "TeamId"]?.number { return String(Int(n)) }
      return nil
    }
    return (extract("home"), extract("away"))
  }

  private static func containsLine(_ s: String, line: Double) -> Bool {
    let formats = [String(format: "%.1f", line), String(format: "%.2f", line)]
    for f in formats { if s.contains(f) { return true } }
    if abs(line.rounded() - line) < 0.001 {
      if s.contains("\(Int(line))") { return true }
    }
    return false
  }

  private static func number(_ o: [String: JSONValue], _ keys: [String]) -> Double? {
    for k in keys { if let n = o[k]?.number { return n } }
    return nil
  }
}
