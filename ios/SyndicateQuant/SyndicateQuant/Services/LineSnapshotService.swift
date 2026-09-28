import Foundation
import SwiftData

@MainActor
enum LineSnapshotService {
  static func bucket(minutesToStart: Int, maxWindow: Int = 60) -> Int? {
    if minutesToStart <= 0 { return nil }
    if minutesToStart > maxWindow { return nil }
    if minutesToStart > 30 { return 60 }
    if minutesToStart > 15 { return 30 }
    if minutesToStart > 5  { return 15 }
    return 5
  }

  @discardableResult
  static func save(gameID: String, numericID: Int?,
                   market: String, selection: String, line: Double?,
                   startTime: Date?, league: String, home: String, away: String,
                   bucketMinutes: Int, minutesToStart: Int,
                   byBook: [String: Double],
                   in context: ModelContext) -> Bool {
    let sid = "\(gameID)|\(market)|\(selection.lowercased())|\(line.map { String($0) } ?? "na")|\(bucketMinutes)"
    let d = FetchDescriptor<LineSnapshot>(predicate: #Predicate { $0.id == sid })
    if let _ = try? context.fetch(d).first { return false }

    let values = Array(byBook.values)
    guard !values.isEmpty else { return false }
    let avg = values.reduce(0, +) / Double(values.count)
    let best = values.max() ?? avg
    let worst = values.min() ?? avg

    let bookJSON: Data? = {
      let dict = Dictionary(uniqueKeysWithValues: byBook.map { ($0.key, $0.value) })
      return try? JSONEncoder().encode(dict)
    }()

    let snap = LineSnapshot(
      id: sid, gameID: gameID, numericID: numericID,
      market: market, selection: selection, line: line,
      startTime: startTime, league: league, home: home, away: away,
      takenAt: Date(), minutesToStart: minutesToStart, bucketMinutes: bucketMinutes,
      avgOdds: avg, bestOdds: best, worstOdds: worst,
      booksCount: values.count, bookmakerJSON: bookJSON)
    context.insert(snap)
    return true
  }

  static func history(gameID: String, market: String, selection: String,
                      line: Double?, in context: ModelContext) -> [LineSnapshot] {
    let gid = gameID
    let d = FetchDescriptor<LineSnapshot>(
      predicate: #Predicate { $0.gameID == gid })
    let all = (try? context.fetch(d)) ?? []
    let selLower = selection.lowercased()
    return all
      .filter { $0.market == market && $0.selection.lowercased() == selLower }
      .filter { s in
        if let l = line { return s.line == l }
        return s.line == nil
      }
      .sorted { $0.takenAt < $1.takenAt }
  }

  static func totalCount(in context: ModelContext) -> Int {
    (try? context.fetch(FetchDescriptor<LineSnapshot>()))?.count ?? 0
  }
}
