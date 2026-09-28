import Foundation
import SwiftData

@MainActor
enum HistoricalMarketCacheService {
  @discardableResult
  static func upsert(from match: Match, in context: ModelContext) -> HistoricalMarketCache? {
    guard let nid = match.numericID else { return nil }
    let gid = match.id
    let d = FetchDescriptor<HistoricalMarketCache>(
      predicate: #Predicate { $0.gameID == gid })
    if let existing = try? context.fetch(d).first {
      existing.numericID = nid
      existing.start = match.start
      existing.league = match.league
      existing.homeID = match.homeID
      existing.awayID = match.awayID
      existing.home = match.home
      existing.away = match.away
      existing.updatedAt = Date()
      return existing
    }
    let row = HistoricalMarketCache(
      gameID: match.id, numericID: nid, start: match.start,
      league: match.league, homeID: match.homeID, awayID: match.awayID,
      home: match.home, away: match.away)
    context.insert(row)
    return row
  }

  static func markEnriched(gameID: String, oddsData: Data,
                           hasCorners: Bool, hasCards: Bool,
                           in context: ModelContext) {
    let gid = gameID
    let d = FetchDescriptor<HistoricalMarketCache>(
      predicate: #Predicate { $0.gameID == gid })
    guard let row = try? context.fetch(d).first else { return }
    row.oddsJSON = oddsData
    row.hasCorners = hasCorners
    row.hasCards = hasCards
    row.cornersChecked = true
    row.cardsChecked = true
    row.enriched = hasCorners || hasCards
    row.failedAttempts = 0
    row.lastError = nil
    row.updatedAt = Date()
  }

  static func markFailed(gameID: String, error: String, in context: ModelContext) {
    let gid = gameID
    let d = FetchDescriptor<HistoricalMarketCache>(
      predicate: #Predicate { $0.gameID == gid })
    guard let row = try? context.fetch(d).first else { return }
    row.failedAttempts += 1
    row.lastError = error
    row.updatedAt = Date()
  }

  static func progress(in context: ModelContext) -> (enriched: Int, total: Int) {
    let all = (try? context.fetch(FetchDescriptor<HistoricalMarketCache>())) ?? []
    let enriched = all.reduce(0) { $0 + (($1.cornersChecked && $1.cardsChecked) ? 1 : 0) }
    return (enriched, all.count)
  }

  static func candidates(limit: Int, in context: ModelContext) -> [HistoricalMarketCache] {
    let all = (try? context.fetch(FetchDescriptor<HistoricalMarketCache>())) ?? []
    let filtered = all
      .filter { !($0.cornersChecked && $0.cardsChecked) && $0.failedAttempts < 3 }
      .sorted { ($0.start ?? .distantPast) > ($1.start ?? .distantPast) }
    return Array(filtered.prefix(limit))
  }
}
