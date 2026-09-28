import Foundation
import Combine

@MainActor
final class SubscriptionService: ObservableObject {
  static let shared = SubscriptionService()

  @Published private(set) var isSubscribed = false

  private init() {}

  func refreshEntitlement() async {
    // StoreKit 2 integration is isolated here. Product IDs are configured
    // in the commercial subscription wave rather than invented in the engine.
  }
}
