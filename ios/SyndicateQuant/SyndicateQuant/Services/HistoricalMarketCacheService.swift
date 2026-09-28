import Foundation

struct HistoricalMarketCacheRecord: Codable, Hashable, Identifiable {
  let gameID: String
  var numericID: Int
  var start: Date?
  var league: String
  var homeID: String?
  var awayID: String?
  var home: String
  var away: String
  var oddsJSON: Data?
  var enriched: Bool
  var hasCorners: Bool
  var hasCards: Bool
  var cornersChecked: Bool
  var cardsChecked: Bool
  var failedAttempts: Int
  var lastError: String?
  var updatedAt: Date

  var id: String { gameID }

  init(gameID: String, numericID: Int, start: Date?, league: String,
       homeID: String?, awayID: String?, home: String, away: String,
       oddsJSON: Data? = nil, enriched: Bool = false,
       hasCorners: Bool = false, hasCards: Bool = false,
       cornersChecked: Bool = false, cardsChecked: Bool = false,
       failedAttempts: Int = 0, lastError: String? = nil,
       updatedAt: Date = Date()) {
    self.gameID = gameID
    self.numericID = numericID
    self.start = start
    self.league = league
    self.homeID = homeID
    self.awayID = awayID
    self.home = home
    self.away = away
    self.oddsJSON = oddsJSON
    self.enriched = enriched
    self.hasCorners = hasCorners
    self.hasCards = hasCards
    self.cornersChecked = cornersChecked
    self.cardsChecked = cardsChecked
    self.failedAttempts = failedAttempts
    self.lastError = lastError
    self.updatedAt = updatedAt
  }
}

private struct HistoricalMarketCacheEnvelope: Codable {
  let formatVersion: Int
  let updatedAt: Date
  let records: [HistoricalMarketCacheRecord]
}

enum HistoricalMarketCacheDiskStore {
  static let formatVersion = 1

  static var directoryURL: URL {
    let fm = FileManager.default
    let base = (try? fm.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )) ?? URL(fileURLWithPath: NSTemporaryDirectory())

    var directory = base.appendingPathComponent("HistoricalMarketCache", isDirectory: true)
    try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try? directory.setResourceValues(values)
    return directory
  }

  static var fileURL: URL {
    directoryURL.appendingPathComponent("cache-v1.json")
  }

  static func load() -> [String: HistoricalMarketCacheRecord] {
    guard let data = try? Data(contentsOf: fileURL),
          let envelope = try? JSONDecoder().decode(
            HistoricalMarketCacheEnvelope.self, from: data),
          envelope.formatVersion == formatVersion else {
      return [:]
    }
    return Dictionary(uniqueKeysWithValues: envelope.records.map { ($0.gameID, $0) })
  }

  static func writeAll(_ records: [HistoricalMarketCacheRecord]) throws {
    let fm = FileManager.default
    try fm.createDirectory(at: directoryURL, withIntermediateDirectories: true)

    let envelope = HistoricalMarketCacheEnvelope(
      formatVersion: formatVersion,
      updatedAt: Date(),
      records: records.sorted {
        ($0.start ?? .distantPast) > ($1.start ?? .distantPast)
      }
    )

    let data = try JSONEncoder().encode(envelope)
    try data.write(to: fileURL, options: .atomic)
  }

  static func mergeAndPersist(_ records: [HistoricalMarketCacheRecord]) throws {
    guard !records.isEmpty else { return }
    var merged = load()
    for record in records {
      merged[record.gameID] = record
    }
    try writeAll(Array(merged.values))
  }
}

@MainActor
final class HistoricalMarketCacheDiskState {
  static let shared = HistoricalMarketCacheDiskState()

  private var records: [String: HistoricalMarketCacheRecord]
  private var pendingWrites = 0

  private init() {
    records = HistoricalMarketCacheDiskStore.load()
  }

  private func persist() {
    do {
      try HistoricalMarketCacheDiskStore.writeAll(Array(records.values))
      pendingWrites = 0
    } catch {
      print("[HistoricalCache] persist failed: \(error.localizedDescription)")
    }
  }

  private func markDirty(immediate: Bool = false) {
    pendingWrites += 1
    if immediate || pendingWrites >= 25 {
      persist()
    }
  }

  @discardableResult
  func upsert(from match: Match) -> HistoricalMarketCacheRecord? {
    guard let nid = match.numericID else { return nil }

    var row = records[match.id] ?? HistoricalMarketCacheRecord(
      gameID: match.id,
      numericID: nid,
      start: match.start,
      league: match.league,
      homeID: match.homeID,
      awayID: match.awayID,
      home: match.home,
      away: match.away
    )

    row.numericID = nid
    row.start = match.start
    row.league = match.league
    row.homeID = match.homeID
    row.awayID = match.awayID
    row.home = match.home
    row.away = match.away
    row.updatedAt = Date()

    records[match.id] = row
    markDirty()
    return row
  }

  func markEnriched(gameID: String, oddsData: Data,
                    hasCorners: Bool, hasCards: Bool) {
    guard var row = records[gameID] else { return }
    row.oddsJSON = oddsData
    row.hasCorners = hasCorners
    row.hasCards = hasCards
    row.cornersChecked = true
    row.cardsChecked = true
    row.enriched = row.cornersChecked && row.cardsChecked
    row.failedAttempts = 0
    row.lastError = nil
    row.updatedAt = Date()
    records[gameID] = row
    markDirty(immediate: true)
  }

  func markFailed(gameID: String, error: String) {
    guard var row = records[gameID] else { return }
    row.failedAttempts += 1
    row.lastError = error
    row.updatedAt = Date()
    records[gameID] = row
    markDirty(immediate: true)
  }

  func record(gameID: String) -> HistoricalMarketCacheRecord? {
    records[gameID]
  }

  func progress() -> (enriched: Int, total: Int) {
    let enriched = records.values.reduce(into: 0) { result, row in
      if row.cornersChecked && row.cardsChecked {
        result += 1
      }
    }
    return (enriched, records.count)
  }

  func candidates(limit: Int) -> [HistoricalMarketCacheRecord] {
    let filtered = records.values
      .filter { !($0.cornersChecked && $0.cardsChecked) }
      .filter { $0.failedAttempts < 3 }
      .sorted { ($0.start ?? .distantPast) > ($1.start ?? .distantPast) }

    return Array(filtered.prefix(max(0, limit)))
  }

  func purgeCompleted(olderThan cutoff: Date) {
    records = records.filter { _, row in
      !(row.cornersChecked && row.cardsChecked && row.updatedAt < cutoff)
    }
    persist()
  }

  func flush() {
    guard pendingWrites > 0 else { return }
    persist()
  }
}

@MainActor
enum HistoricalMarketCacheService {
  @discardableResult
  static func upsert(from match: Match) -> HistoricalMarketCacheRecord? {
    HistoricalMarketCacheDiskState.shared.upsert(from: match)
  }

  static func markEnriched(gameID: String, oddsData: Data,
                           hasCorners: Bool, hasCards: Bool) {
    HistoricalMarketCacheDiskState.shared.markEnriched(
      gameID: gameID,
      oddsData: oddsData,
      hasCorners: hasCorners,
      hasCards: hasCards
    )
  }

  static func markFailed(gameID: String, error: String) {
    HistoricalMarketCacheDiskState.shared.markFailed(gameID: gameID, error: error)
  }

  static func progress() -> (enriched: Int, total: Int) {
    HistoricalMarketCacheDiskState.shared.progress()
  }

  static func candidates(limit: Int) -> [HistoricalMarketCacheRecord] {
    HistoricalMarketCacheDiskState.shared.candidates(limit: limit)
  }

  static func record(gameID: String) -> HistoricalMarketCacheRecord? {
    HistoricalMarketCacheDiskState.shared.record(gameID: gameID)
  }

  static func flush() {
    HistoricalMarketCacheDiskState.shared.flush()
  }
}
