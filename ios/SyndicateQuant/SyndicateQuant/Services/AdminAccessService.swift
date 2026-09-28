import Foundation
import Combine

@MainActor
final class AdminAccessService: ObservableObject {
  static let shared = AdminAccessService()

  @Published private(set) var isAuthorized = false

  private init() {}

  func refreshAuthorization() async {
    // W1 intentionally grants no implicit admin access. The final version
    // uses server-backed authorization; no secret is hard-coded in the IPA.
    isAuthorized = false
  }
}
