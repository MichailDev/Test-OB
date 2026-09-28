import Foundation
import SwiftData

@MainActor
enum TeamRatingService {
  static let initialRating = 1500.0
  static let homeAdvantage = 60.0
  static let kBase = 32.0
  static let kDecayAfter = 30
  static let kMin = 20.0
  static let minMatchesForUse = 3

  static func expectedHome(home: Double, away: Double) -> Double {
    let diff = (home + homeAdvantage) - away
    return 1.0 / (1.0 + pow(10.0, -diff / 400.0))
  }
  static func kFactor(matches: Int) -> Double {
    if matches >= kDecayAfter { return kMin }
    let t = Double(matches) / Double(kDecayAfter)
    return kBase + (kMin - kBase) * t
  }
  @discardableResult
  static func update(context: ModelContext,
                     homeTeamID: String, homeName: String,
                     awayTeamID: String, awayName: String,
                     homeGoals: Double, awayGoals: Double)
    -> (deltaHome: Double, deltaAway: Double)? {
    guard !homeTeamID.isEmpty, !awayTeamID.isEmpty,
          homeTeamID != awayTeamID else { return nil }
    let h = fetchOrCreate(context, teamID: homeTeamID, name: homeName)
    let a = fetchOrCreate(context, teamID: awayTeamID, name: awayName)
    let expectedHome = expectedHome(home: h.rating, away: a.rating)
    let outcomeHome: Double
    if homeGoals > awayGoals { outcomeHome = 1.0 }
    else if homeGoals == awayGoals { outcomeHome = 0.5 }
    else { outcomeHome = 0.0 }
    let outcomeAway = 1.0 - outcomeHome
    let deltaH = kFactor(matches: h.matches) * (outcomeHome - expectedHome)
    let deltaA = kFactor(matches: a.matches) * (outcomeAway - (1 - expectedHome))
    h.rating += deltaH; h.matches += 1; h.lastDelta = deltaH; h.updatedAt = Date()
    a.rating += deltaA; a.matches += 1; a.lastDelta = deltaA; a.updatedAt = Date()
    try? context.save()
    return (deltaH, deltaA)
  }
  static func fetchOrCreate(_ context: ModelContext,
                            teamID: String, name: String) -> TeamRating {
    let d = FetchDescriptor<TeamRating>(predicate: #Predicate { $0.teamID == teamID })
    if let existing = try? context.fetch(d).first {
      if !name.isEmpty, existing.name != name { existing.name = name }
      return existing
    }
    let r = TeamRating(teamID: teamID, name: name)
    context.insert(r)
    return r
  }
  static func usableRating(for teamID: String, context: ModelContext) -> Double? {
    let d = FetchDescriptor<TeamRating>(predicate: #Predicate { $0.teamID == teamID })
    guard let r = try? context.fetch(d).first,
          r.matches >= minMatchesForUse else { return nil }
    return r.rating
  }
}
