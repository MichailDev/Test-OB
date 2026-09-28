import Foundation

struct TeamRecord: Hashable, Codable {
  var id: String
  var date: Date?
  var gf: Double?
  var ga: Double?
  var corners: Double?
  var oppCorners: Double?
  var cards: Double?
  var oppCards: Double?
  var fouls: Double?
  var oppFouls: Double?
  var shots: Double?
  var sot: Double?
  var possession: Double?
  var xg: Double?
  var oppXg: Double?
  var referee: String?
  var isHome: Bool = true
  var players: [PlayerRow] = []
  var reds: Double? = nil
  var oppReds: Double? = nil

  var cardsPlusReds: Double? {
    guard cards != nil || reds != nil else { return nil }
    return (cards ?? 0) + (reds ?? 0)
  }
  var oppCardsPlusReds: Double? {
    guard oppCards != nil || oppReds != nil else { return nil }
    return (oppCards ?? 0) + (oppReds ?? 0)
  }
}

struct PlayerRow: Hashable, Codable {
  var id: String; var name: String
  var minutes: Double; var xg: Double; var xa: Double
  var goals: Double; var assists: Double
  var shots: Double; var sot: Double; var starts: Int
}

struct RefProfile {
  var n: Int; var cards: Double?; var fouls: Double?
  var confidence: Double; var rsi: Double
}

struct SharpGuard {
  var score: Double = 0; var movement: Double = 0
  var sharpMovement: Double = 0; var disagreement: Double = 0
  var sharpClose: Double?; var sharpOpen: Double?
}

struct MatchModel {
  var lh: Double; var la: Double
  var baseLH: Double; var baseLA: Double
  var baseMatrix: Matrix2D; var playerMatrix: Matrix2D; var matrix: Matrix2D
  var ensembleMatrix: Matrix2D
  var outcomes: (home: Double, draw: Double, away: Double)
  var components: [Double]
  var playerHome: PlayerAssembly; var playerAway: PlayerAssembly
  var ensembleWeights: (dc: Double, biv: Double, nb: Double) = (0, 0, 0)
  var ensembleAvgXG: Double? = nil
  var outcomesDC: (home: Double, draw: Double, away: Double) = (0, 0, 0)
  var outcomesBIV: (home: Double, draw: Double, away: Double) = (0, 0, 0)
  var outcomesNB: (home: Double, draw: Double, away: Double) = (0, 0, 0)
}

struct PlayerAssembly {
  var factor: Double; var baseline: Double
  var playersUsed: Int; var top: [PlayerAgg]
}

struct PlayerAgg: Hashable, Codable {
  var id: String; var name: String = ""
  var minutes = 0.0; var xg = 0.0; var xa = 0.0
  var goals = 0.0; var assists = 0.0
  var shots = 0.0; var sot = 0.0; var games = 0
}
