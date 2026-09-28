import Foundation

let matchStartFormatter: DateFormatter = {
  let f = DateFormatter()
  f.dateFormat = "dd.MM · HH:mm"
  f.timeZone = .current
  return f
}()

func formatMatchStart(_ date: Date?) -> String? {
  guard let date else { return nil }
  return matchStartFormatter.string(from: date)
}

func formatMatchStartLong(_ date: Date?) -> String? {
  guard let date else { return nil }
  let f = DateFormatter()
  f.dateStyle = .medium
  f.timeStyle = .short
  f.timeZone = .current
  return f.string(from: date)
}
