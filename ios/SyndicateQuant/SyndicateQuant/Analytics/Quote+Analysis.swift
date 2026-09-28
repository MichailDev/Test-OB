import Foundation

extension Quote {
  var selectionKey: String {
    let s = selection.lowercased()
    if market == "1X2" {
      if s == "1" || s.contains("home") { return "1" }
      if s == "x" || s.contains("draw") { return "X" }
      return "2"
    }
    return s.contains("under") ? "U" : "O"
  }
}
