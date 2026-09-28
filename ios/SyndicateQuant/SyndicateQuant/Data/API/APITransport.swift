import Foundation
import Network

actor ResponseCache {
  static let shared = ResponseCache()
  private struct Entry { let json: JSONValue; let expiresAt: Date }
  nonisolated private struct Envelope: Codable { let payload: Data; let expiresAt: Date }
  private var memory: [String: Entry] = [:]
  private let fm = FileManager.default
  private let dir: URL

  private init() {
    let base = (try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
                                             appropriateFor: nil, create: true))
      ?? URL(fileURLWithPath: NSTemporaryDirectory())
    let d = base.appendingPathComponent("SStatsCache", isDirectory: true)
    try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    self.dir = d
    Self.purgeExpiredOnDisk(in: d)
  }

  func get(key: String) -> JSONValue? {
    if let e = memory[key], e.expiresAt > Date() { return e.json }
    let url = fileURL(for: key)
    guard let data = try? Data(contentsOf: url),
          let env = try? JSONDecoder().decode(Envelope.self, from: data),
          env.expiresAt > Date()
    else { try? fm.removeItem(at: url); return nil }
    guard let json = try? JSONValue(data: env.payload) else { return nil }
    memory[key] = Entry(json: json, expiresAt: env.expiresAt)
    return json
  }

  func set(key: String, json: JSONValue, ttl: TimeInterval) {
    let expiresAt = Date().addingTimeInterval(ttl)
    memory[key] = Entry(json: json, expiresAt: expiresAt)
    do {
      let payload = try JSONEncoder().encode(json)
      let env = Envelope(payload: payload, expiresAt: expiresAt)
      let data = try JSONEncoder().encode(env)
      try data.write(to: fileURL(for: key), options: .atomic)
    } catch {}
  }

  func clearAll() {
    memory.removeAll()
    try? fm.removeItem(at: dir)
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
  }

  private func fileURL(for key: String) -> URL {
    dir.appendingPathComponent(ResponseCache.fnv1a(key) + ".json")
  }

  nonisolated static func purgeExpiredOnDisk(in dir: URL) {
    let fm = FileManager.default
    let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
    for f in files {
      guard let data = try? Data(contentsOf: f),
            let env = try? JSONDecoder().decode(Envelope.self, from: data)
      else { try? fm.removeItem(at: f); continue }
      if env.expiresAt <= Date() { try? fm.removeItem(at: f) }
    }
  }

  nonisolated private static func fnv1a(_ s: String) -> String {
    var h: UInt64 = 1469598103934665603
    for b in s.utf8 { h ^= UInt64(b); h &*= 1099511628211 }
    return String(h, radix: 16)
  }
}

actor RateLimiter {
  static let shared = RateLimiter()
  private var lastRequest = Date.distantPast
  private var minInterval: TimeInterval = 1.5

  func acquire() async {
    let now = Date()
    let elapsed = now.timeIntervalSince(lastRequest)
    if elapsed < minInterval {
      let wait = minInterval - elapsed
      try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
    }
    lastRequest = Date()
  }

  func register429(retryAfter: TimeInterval?) {
    let cooldown = max(1.0, retryAfter ?? 30.0)
    minInterval = min(10.0, max(minInterval, cooldown))
    // Keep lastRequest at the moment of the 429. acquire() will wait minInterval
    // once, rather than accidentally adding the cooldown twice.
    lastRequest = Date()
    print("[RateLimit] 429; cooldown=\(cooldown)s")
  }

  func onSuccess() { minInterval = max(1.5, minInterval * 0.95) }
}

actor RequestCoalescer {
  static let shared = RequestCoalescer()
  private var inFlight: [String: Task<JSONValue, Error>] = [:]

  func coalesce(key: String,
                operation: @escaping @Sendable () async throws -> JSONValue
  ) async throws -> JSONValue {
    if let existing = inFlight[key] { return try await existing.value }
    let task = Task { try await operation() }
    inFlight[key] = task
    do {
      let value = try await task.value
      inFlight[key] = nil
      return value
    } catch {
      inFlight[key] = nil
      throw error
    }
  }
}

final class NetworkMonitor: @unchecked Sendable {
  static let shared = NetworkMonitor()
  private let monitor = NWPathMonitor()
  private let queue = DispatchQueue(label: "com.syndicatequant.netmon")
  private let lock = NSLock()
  private var _isOnline = true

  var isOnline: Bool { lock.lock(); defer { lock.unlock() }; return _isOnline }

  private init() {
    monitor.pathUpdateHandler = { [weak self] path in
      guard let self else { return }
      self.lock.lock()
      self._isOnline = (path.status == .satisfied)
      self.lock.unlock()
    }
    monitor.start(queue: queue)
  }
}

enum APIError: LocalizedError {
  case invalidURL, invalidResponse, rateLimited, missingAPIKey
  case server(String)
  var errorDescription: String? {
    switch self {
    case .invalidURL: return "Некорректный URL"
    case .invalidResponse: return "Некорректный ответ SStats"
    case .rateLimited: return "SStats: превышен лимит запросов"
    case .missingAPIKey: return "Укажи SStats API key в настройках"
    case .server(let s): return s
    }
  }
}

enum JSONValue: Codable, Hashable {
  case object([String: JSONValue])
  case array([JSONValue])
  case string(String)
  case number(Double)
  case bool(Bool)
  case null
  init(data: Data) throws { self = try JSONDecoder().decode(JSONValue.self, from: data) }
  init(from decoder: Decoder) throws {
    if let c = try? decoder.container(keyedBy: AnyCodingKey.self) {
      var o = [String: JSONValue]()
      for k in c.allKeys { o[k.stringValue] = try c.decode(JSONValue.self, forKey: k) }
      self = .object(o); return
    }
    if var c = try? decoder.unkeyedContainer() {
      var a = [JSONValue]()
      while !c.isAtEnd { a.append(try c.decode(JSONValue.self)) }
      self = .array(a); return
    }
    let c = try decoder.singleValueContainer()
    if c.decodeNil() { self = .null }
    else if let b = try? c.decode(Bool.self) { self = .bool(b) }
    else if let n = try? c.decode(Double.self) { self = .number(n) }
    else { self = .string(try c.decode(String.self)) }
  }
  func encode(to encoder: Encoder) throws {
    var c = encoder.singleValueContainer()
    switch self {
    case .object(let v): try c.encode(v)
    case .array(let v): try c.encode(v)
    case .string(let v): try c.encode(v)
    case .number(let v): try c.encode(v)
    case .bool(let v): try c.encode(v)
    case .null: try c.encodeNil()
    }
  }
  var string: String? { if case .string(let v) = self { return v }; return nil }
  var number: Double? { if case .number(let v) = self { return v }; return nil }
  var object: [String: JSONValue]? { if case .object(let v) = self { return v }; return nil }
  var array: [JSONValue]? { if case .array(let v) = self { return v }; return nil }
  var bool: Bool? { if case .bool(let v) = self { return v }; return nil }
  func allObjects() -> [[String: JSONValue]] {
    var out = [[String: JSONValue]]()
    if let o = object {
      out.append(o)
      for v in o.values { out += v.allObjects() }
    }
    if let a = array { for v in a { out += v.allObjects() } }
    return out
  }
  func firstNumber(keys: Set<String>) -> Double? {
    if let o = object {
      for (k, v) in o {
        if keys.contains(k.lowercased()), let n = v.number { return n }
        if let n = v.firstNumber(keys: keys) { return n }
      }
    }
    if let a = array { for v in a { if let n = v.firstNumber(keys: keys) { return n } } }
    return nil
  }
}

struct AnyCodingKey: CodingKey {
  let stringValue: String
  init?(stringValue: String) { self.stringValue = stringValue }
  let intValue: Int? = nil
  init?(intValue: Int) { return nil }
}
