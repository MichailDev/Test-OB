import Foundation

enum LeaguePool {
  static let pool: [(id: Int, name: String)] = [
    (39, "Premier League"),
    (78, "Bundesliga"),
    (140, "La Liga"),
    (135, "Serie A"),
    (61, "Ligue 1"),
    (235, "RPL"),
    (2, "Champions League"),
    (3, "Europa League"),
    (94, "Liga Portugal"),
    (88, "Eredivisie"),
    (144, "Pro League"),
  ]
  static func id(for name: String) -> Int? { pool.first(where: { $0.name == name })?.id }
  static func name(for id: Int) -> String? { pool.first(where: { $0.id == id })?.name }
}

struct LeagueBaseline: Identifiable, Hashable {
  let id: Int
  let name: String
  let homeLambda: Double
  let awayLambda: Double
  let homeAdvantage: Double
  let rho: Double
  let sampleSize: Int
}

enum LeagueBaselines {
  static let all: [LeagueBaseline] = [
    LeagueBaseline(id: 39,  name: "Premier League",   homeLambda: 1.55, awayLambda: 1.20, homeAdvantage: 0.22, rho: -0.08, sampleSize: 0),
    LeagueBaseline(id: 78,  name: "Bundesliga",       homeLambda: 1.68, awayLambda: 1.28, homeAdvantage: 0.18, rho: -0.06, sampleSize: 0),
    LeagueBaseline(id: 140, name: "La Liga",          homeLambda: 1.45, awayLambda: 1.10, homeAdvantage: 0.24, rho: -0.09, sampleSize: 0),
    LeagueBaseline(id: 135, name: "Serie A",          homeLambda: 1.48, awayLambda: 1.15, homeAdvantage: 0.21, rho: -0.07, sampleSize: 0),
    LeagueBaseline(id: 61,  name: "Ligue 1",          homeLambda: 1.42, awayLambda: 1.12, homeAdvantage: 0.20, rho: -0.08, sampleSize: 0),
    LeagueBaseline(id: 235, name: "RPL",              homeLambda: 1.35, awayLambda: 1.05, homeAdvantage: 0.25, rho: -0.10, sampleSize: 0),
    LeagueBaseline(id: 2,   name: "Champions League", homeLambda: 1.55, awayLambda: 1.25, homeAdvantage: 0.20, rho: -0.08, sampleSize: 0),
    LeagueBaseline(id: 3,   name: "Europa League",    homeLambda: 1.50, awayLambda: 1.20, homeAdvantage: 0.20, rho: -0.08, sampleSize: 0),
    LeagueBaseline(id: 94,  name: "Liga Portugal",    homeLambda: 1.40, awayLambda: 1.05, homeAdvantage: 0.23, rho: -0.09, sampleSize: 0),
    LeagueBaseline(id: 88,  name: "Eredivisie",       homeLambda: 1.70, awayLambda: 1.30, homeAdvantage: 0.16, rho: -0.05, sampleSize: 0),
    LeagueBaseline(id: 144, name: "Pro League",       homeLambda: 1.55, awayLambda: 1.20, homeAdvantage: 0.20, rho: -0.08, sampleSize: 0),
  ]
  static func baseline(for name: String) -> LeagueBaseline? {
    all.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
  }
}
