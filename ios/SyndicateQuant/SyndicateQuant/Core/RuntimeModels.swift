import Foundation
import SwiftUI

enum OddsFormat: String, CaseIterable, Identifiable {
  case eu, us, uk
  var id: String { rawValue }
  var label: String {
    switch self { case .eu: return "EU"; case .us: return "US"; case .uk: return "UK" }
  }
  var hint: String {
    switch self {
    case .eu: return "Десятичные · 2.10"
    case .us: return "Американские · +110 / −150"
    case .uk: return "Дробные · 11/10"
    }
  }
}

enum AppColorScheme: String, CaseIterable, Identifiable {
  case system, light, dark
  var id: String { rawValue }
  var label: String {
    switch self { case .system: return "Система"; case .light: return "Светлая"; case .dark: return "Тёмная" }
  }
  var toColorScheme: SwiftUI.ColorScheme? {
    switch self { case .system: return nil; case .light: return .light; case .dark: return .dark }
  }
}

enum OddsFormatter {
  static func format(_ value: Double, as format: OddsFormat) -> String {
    guard value > 1.0 else { return "—" }
    switch format {
    case .eu: return String(format: "%.2f", value)
    case .us:
      if value >= 2.0 { return String(format: "+%d", Int(round((value - 1) * 100))) }
      else { return String(format: "−%d", Int(round(100 / (value - 1)))) }
    case .uk:
      let frac = fractional(value)
      return "\(frac.0)/\(frac.1)"
    }
  }
  private static func fractional(_ value: Double) -> (Int, Int) {
    let net = value - 1.0
    guard net > 0 else { return (0, 1) }
    var bestNum = 1; var bestDen = 1
    var bestErr = Double.greatestFiniteMagnitude
    for den in 1...20 {
      let num = Int(round(net * Double(den)))
      if num < 1 { continue }
      let approx = Double(num) / Double(den)
      let err = abs(approx - net)
      if err < bestErr { bestErr = err; bestNum = num; bestDen = den }
    }
    return (bestNum, bestDen)
  }
}

struct SignalIDWrapper: Identifiable { let id: String }

struct OddsSnapshot: Hashable {
  let gameID: String; let numericID: Int?; let takenAt: Date
  let byKey: [String: [String: Double]]
  func avg(forKey k: String) -> Double? {
    guard let map = byKey[k], !map.isEmpty else { return nil }
    let values = Array(map.values)
    return values.reduce(0, +) / Double(values.count)
  }
  func median(forKey k: String) -> Double? {
    guard let map = byKey[k], !map.isEmpty else { return nil }
    return QuantMath.median(Array(map.values))
  }
  func booksMoving(forKey k: String, vs previous: OddsSnapshot, threshold: Double)
    -> (count: Int, direction: Int, avgDelta: Double) {
    guard let cur = byKey[k], let prev = previous.byKey[k] else { return (0, 0, 0) }
    var up = 0; var down = 0; var deltaSum = 0.0; var n = 0
    for (book, c) in cur {
      guard let p = prev[book], p > 1, c > 1 else { continue }
      let d = (c - p) / p
      if d > threshold { up += 1 } else if d < -threshold { down += 1 }
      deltaSum += d; n += 1
    }
    if up > down { return (up, +1, n > 0 ? deltaSum / Double(n) : 0) }
    else if down > up { return (down, -1, n > 0 ? deltaSum / Double(n) : 0) }
    return (0, 0, 0)
  }
}

struct LineMovement: Identifiable, Hashable {
  var id: String { key }
  let key: String; let market: String; let selection: String; let line: Double?
  let previousAvg: Double; let currentAvg: Double; let delta: Double
  let booksAgreeing: Int; let isSharp: Bool
  var direction: String { delta > 0 ? "▲" : (delta < 0 ? "▼" : "·") }
}

struct ObservedGame {
  var numericID: Int?
  var startTime: Date?
  var league: String
  var home: String
  var away: String
}
