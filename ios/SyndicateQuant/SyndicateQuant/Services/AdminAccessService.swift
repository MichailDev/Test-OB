import Foundation
import Combine

@MainActor
final class AdminAccessService: ObservableObject {
  static let shared = AdminAccessService()

  enum Status: Equatable {
    case notConfigured
    case signedOut
    case checking
    case authorized(expiresAt: Date?)
    case denied
    case failed(String)

    var label: String {
      switch self {
      case .notConfigured: return "Сервер не настроен"
      case .signedOut: return "Не выполнен вход"
      case .checking: return "Проверка…"
      case .authorized(let expiresAt):
        if let expiresAt {
          return "Доступ до \(expiresAt.formatted(date: .numeric, time: .shortened))"
        }
        return "Доступ разрешён"
      case .denied: return "Доступ запрещён"
      case .failed(let message): return message
      }
    }
  }

  @Published private(set) var isAuthorized = false
  @Published private(set) var status: Status = .signedOut
  @Published private(set) var lastError: String?

  private let tokenKey = "overbet_admin_bearer"
  private let session: URLSession

  private init(session: URLSession = .shared) {
    self.session = session
    if adminBaseURL == nil {
      status = .notConfigured
    } else if KeychainStore.shared.get(tokenKey)?.isEmpty == false {
      status = .checking
    }
  }

  var adminBaseURL: URL? {
    let raw = (Bundle.main.object(forInfoDictionaryKey: "AdminAPIBaseURL") as? String ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !raw.isEmpty,
          let url = URL(string: raw.hasSuffix("/") ? String(raw.dropLast()) : raw),
          url.scheme?.lowercased() == "https",
          url.host != nil else {
      return nil
    }
    return url
  }

  var isConfigured: Bool { adminBaseURL != nil }
  var hasStoredCredentials: Bool { !(KeychainStore.shared.get(tokenKey) ?? "").isEmpty }

  func refreshAuthorization() async {
    guard let baseURL = adminBaseURL else {
      isAuthorized = false
      status = .notConfigured
      return
    }

    guard let token = storedToken() else {
      isAuthorized = false
      status = .signedOut
      return
    }

    status = .checking
    lastError = nil

    do {
      let result = try await requestMe(baseURL: baseURL, token: token)
      apply(result)
    } catch AdminAccessError.unauthorized {
      clearCredentials()
      isAuthorized = false
      status = .denied
      lastError = "Сервер не подтвердил роль admin"
    } catch {
      isAuthorized = false
      status = .failed(error.localizedDescription)
      lastError = error.localizedDescription
    }
  }

  func signIn(token: String) async -> Bool {
    guard let baseURL = adminBaseURL else {
      isAuthorized = false
      status = .notConfigured
      return false
    }

    let cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleaned.isEmpty else {
      lastError = "Токен не задан"
      status = .signedOut
      return false
    }

    status = .checking
    lastError = nil

    do {
      let result = try await requestMe(baseURL: baseURL, token: cleaned)
      guard result.authorized || result.role?.lowercased() == "admin" else {
        throw AdminAccessError.unauthorized
      }
      KeychainStore.shared.set(cleaned, for: tokenKey)
      apply(result)
      return true
    } catch AdminAccessError.unauthorized {
      clearCredentials()
      isAuthorized = false
      status = .denied
      lastError = "Сервер не подтвердил роль admin"
      return false
    } catch {
      isAuthorized = false
      status = .failed(error.localizedDescription)
      lastError = error.localizedDescription
      return false
    }
  }

  func signOut() {
    clearCredentials()
    isAuthorized = false
    lastError = nil
    status = isConfigured ? .signedOut : .notConfigured
  }

  private func storedToken() -> String? {
    let value = KeychainStore.shared.get(tokenKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return value.isEmpty ? nil : value
  }

  private func clearCredentials() {
    KeychainStore.shared.delete(tokenKey)
  }

  private func apply(_ response: AdminMeResponse) {
    guard response.authorized || response.role?.lowercased() == "admin" else {
      clearCredentials()
      isAuthorized = false
      status = .denied
      return
    }
    isAuthorized = true
    status = .authorized(expiresAt: response.expiresAt)
  }

  private func requestMe(baseURL: URL, token: String) async throws -> AdminMeResponse {
    let url = baseURL.appendingPathComponent("v1/admin/me")

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.timeoutInterval = 15
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("OverBet-iOS/6.2.0", forHTTPHeaderField: "User-Agent")

    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw AdminAccessError.invalidResponse
    }

    guard (200..<300).contains(http.statusCode) else {
      if http.statusCode == 401 || http.statusCode == 403 {
        throw AdminAccessError.unauthorized
      }
      throw AdminAccessError.server("HTTP \(http.statusCode)")
    }

    do {
      return try JSONDecoder.admin.decode(AdminMeResponse.self, from: data)
    } catch {
      throw AdminAccessError.invalidResponse
    }
  }
}

private struct AdminMeResponse: Decodable {
  let authorized: Bool
  let role: String?
  let expiresAt: Date?

  enum CodingKeys: String, CodingKey {
    case authorized
    case role
    case expiresAt
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    authorized = try c.decodeIfPresent(Bool.self, forKey: .authorized) ?? false
    role = try c.decodeIfPresent(String.self, forKey: .role)
    expiresAt = (try? c.decode(Date.self, forKey: .expiresAt))
      ?? (try? c.decode(String.self, forKey: .expiresAt)).flatMap { ISO8601DateFormatter().date(from: $0) }
  }
}

private enum AdminAccessError: LocalizedError {
  case invalidURL
  case invalidResponse
  case unauthorized
  case server(String)

  var errorDescription: String? {
    switch self {
    case .invalidURL: return "Некорректный Admin API URL"
    case .invalidResponse: return "Некорректный ответ Admin API"
    case .unauthorized: return "Admin API отклонил доступ"
    case .server(let message): return "Admin API: \(message)"
    }
  }
}

private extension JSONDecoder {
  static var admin: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}
