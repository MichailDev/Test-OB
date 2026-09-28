import Foundation

enum BetTier: String, Codable, CaseIterable {
  case free = "A BET"
  case premium = "S BET"
  case none = "NO BET"

  init(classification: String) {
    switch classification.uppercased() {
    case "S BET": self = .premium
    case "A BET": self = .free
    default: self = .none
    }
  }

  var isBet: Bool { self != .none }
}