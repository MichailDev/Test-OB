import Foundation
import Combine
import StoreKit

@MainActor
final class SubscriptionService: ObservableObject {
  static let shared = SubscriptionService()

  enum Status: Equatable {
    case notConfigured
    case loading
    case active
    case inactive
    case unavailable
    case notEntitled
    case failed(String)

    var label: String {
      switch self {
      case .notConfigured: return "Не настроена"
      case .loading: return "Проверка…"
      case .active: return "Активна"
      case .inactive: return "Не активна"
      case .unavailable: return "Недоступна"
      case .notEntitled: return "Не активна"
      case .failed(let message): return message
      }
    }
  }

  enum PurchaseOutcome: Equatable {
    case purchased
    case restored
    case cancelled
    case pending
    case unavailable
    case notEntitled
    case failed(String)
  }

  @Published private(set) var isSubscribed = false
  @Published private(set) var status: Status = .notConfigured
  @Published private(set) var product: Product?
  @Published private(set) var lastError: String?

  private var updatesTask: Task<Void, Never>? = nil

  private init() {
    updatesTask = Task { [weak self] in
      await self?.listenForTransactions()
    }
  }

  deinit {
    updatesTask?.cancel()
  }

  var configuredProductIDs: [String] {
    if let values = Bundle.main.object(forInfoDictionaryKey: "SBetSubscriptionProductIDs") as? [String] {
      let cleaned = values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
      if !cleaned.isEmpty { return Array(Set(cleaned)).sorted() }
    }

    if let env = ProcessInfo.processInfo.environment["OVERBET_S_BET_PRODUCT_IDS"] {
      return Array(Set(env.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
    }

    return []
  }

  var isConfigured: Bool { !configuredProductIDs.isEmpty }

  func refreshEntitlement() async {
    status = .loading
    lastError = nil

    let ids = configuredProductIDs
    guard !ids.isEmpty else {
      isSubscribed = false
      product = nil
      status = .notConfigured
      return
    }

    do {
      let products = try await Product.products(for: ids)
      product = products.first(where: { ids.contains($0.id) })

      var entitled = false
      for await result in Transaction.currentEntitlements {
        guard case .verified(let transaction) = result else { continue }
        if ids.contains(transaction.productID) {
          entitled = true
          break
        }
      }

      isSubscribed = entitled
      status = entitled ? .active : .inactive
    } catch {
      isSubscribed = false
      product = nil
      lastError = error.localizedDescription
      status = .failed("Ошибка StoreKit")
    }
  }

  func purchaseSBet() async -> PurchaseOutcome {
    await refreshEntitlement()
    guard let product else {
      return isConfigured ? .failed(lastError ?? "Продукт S BET недоступен") : .unavailable
    }

    do {
      let result = try await product.purchase()
      switch result {
      case .success(let verification):
        guard case .verified(let transaction) = verification else {
          let message = "Транзакция не прошла проверку Apple"
          lastError = message
          return .failed(message)
        }
        await transaction.finish()
        await refreshEntitlement()
        return isSubscribed ? .purchased : .failed("Покупка подтверждена, но доступ не обновился")
      case .userCancelled:
        return .cancelled
      case .pending:
        return .pending
      @unknown default:
        return .failed("Неизвестный результат покупки")
      }
    } catch {
      lastError = error.localizedDescription
      return .failed(error.localizedDescription)
    }
  }

  func restorePurchases() async -> PurchaseOutcome {
    guard isConfigured else { return .unavailable }
    do {
      try await AppStore.sync()
      await refreshEntitlement()
      return isSubscribed ? .restored : .notEntitled
    } catch {
      lastError = error.localizedDescription
      return .failed(error.localizedDescription)
    }
  }

  private func listenForTransactions() async {
    for await result in Transaction.updates {
      guard !Task.isCancelled else { return }
      guard case .verified(let transaction) = result else { continue }
      guard configuredProductIDs.contains(transaction.productID) else { continue }
      await transaction.finish()
      await refreshEntitlement()
    }
  }
}

