import SwiftUI

struct SettingsView: View {
  @EnvironmentObject private var settings: AppSettings
  @EnvironmentObject private var subscription: SubscriptionService
  @EnvironmentObject private var adminAccess: AdminAccessService
  @State private var showAdmin = false
  @State private var showPurchaseError = false
  @State private var purchaseMessage = ""

  var body: some View {
    Form {
      Section("Приложение") {
        Picker("Коэффициенты", selection: $settings.oddsFormatRaw) {
          ForEach(OddsFormat.allCases) { format in
            Text(format.hint).tag(format.rawValue)
          }
        }
        Picker("Тема", selection: $settings.colorSchemeRaw) {
          Text("Система").tag("system")
          Text("Светлая").tag("light")
          Text("Тёмная").tag("dark")
        }
        Toggle("Уведомления о прогнозах", isOn: $settings.notifyBets)
      }

      Section("Подписка S BET") {
        HStack {
          Text("Статус")
          Spacer()
          Text(subscription.status.label)
            .foregroundStyle(subscription.isSubscribed ? .green : .secondary)
        }

        if let product = subscription.product {
          LabeledContent("План", value: product.displayName.isEmpty ? "S BET" : product.displayName)
          LabeledContent("Цена", value: product.displayPrice)
          Button("Подключить S BET") {
            Task { await purchase() }
          }
          .disabled(subscription.isSubscribed)
        } else if subscription.isConfigured {
          Text("Продукт S BET не найден в StoreKit.")
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
          Text("Product ID подписки пока не настроен в Info.plist.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        if !subscription.isSubscribed {
          Button("Восстановить покупки") {
            Task { await restore() }
          }
        }

        if subscription.isSubscribed {
          Text("S BET разблокирован через подтверждённое entitlement Apple.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        if let error = subscription.lastError, !error.isEmpty {
          Text(error).font(.caption2).foregroundStyle(.secondary)
        }
      }

      Section("Администратор") {
        HStack {
          Text("Статус")
          Spacer()
          Text(adminAccess.status.label)
            .foregroundStyle(adminAccess.isAuthorized ? .green : .secondary)
        }

        Button(adminAccess.isAuthorized ? "Открыть Admin" : "Вход администратора") {
          showAdmin = true
        }

        if adminAccess.isAuthorized {
          Button("Выйти из Admin", role: .destructive) {
            adminAccess.signOut()
          }
        }
      }
    }
    .navigationTitle("Настройки")
    .navigationBarTitleDisplayMode(.large)
    .task {
      await subscription.refreshEntitlement()
      await adminAccess.refreshAuthorization()
    }
    .sheet(isPresented: $showAdmin) {
      AdminLoginSheet(
        access: adminAccess,
        isAuthorized: adminAccess.isAuthorized
      )
    }
    .alert("S BET", isPresented: $showPurchaseError) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(purchaseMessage)
    }
  }

  private func purchase() async {
    let result = await subscription.purchaseSBet()
    switch result {
    case .purchased:
      return
    case .cancelled:
      return
    case .pending:
      purchaseMessage = "Покупка ожидает подтверждения App Store."
      showPurchaseError = true
    case .unavailable:
      purchaseMessage = "S BET пока не настроен для этого build."
      showPurchaseError = true
    case .notEntitled:
      purchaseMessage = "Entitlement S BET не найден."
      showPurchaseError = true
    case .failed(let message):
      purchaseMessage = message
      showPurchaseError = true
    }
  }

  private func restore() async {
    let result = await subscription.restorePurchases()
    if case .restored = result { return }
    purchaseMessage = "Активная подписка S BET не найдена."
    if case .failed(let message) = result { purchaseMessage = message }
    showPurchaseError = true
  }
}

private struct AdminLoginSheet: View {
  @Environment(\.dismiss) private var dismiss
  @ObservedObject var access: AdminAccessService
  let isAuthorized: Bool
  @State private var token = ""
  @State private var busy = false

  var body: some View {
    NavigationStack {
      Form {
        Section("Server-backed доступ") {
          LabeledContent("Endpoint", value: access.adminBaseURL?.absoluteString ?? "не настроен")
          SecureField("Admin token", text: $token)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

          Text("Токен хранится только в Keychain после подтверждения роли admin сервером. Секрет администратора не вшит в IPA.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        if let error = access.lastError {
          Text(error).font(.caption).foregroundStyle(.red)
        }
      }
      .navigationTitle("Admin")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Закрыть") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(isAuthorized ? "Проверить" : "Войти") {
            Task { await signIn() }
          }
          .disabled(busy || (!isAuthorized && token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
        }
      }
      .task {
        if isAuthorized { await access.refreshAuthorization() }
      }
    }
  }

  private func signIn() async {
    guard !busy else { return }
    busy = true
    defer { busy = false }

    if isAuthorized {
      await access.refreshAuthorization()
    } else {
      _ = await access.signIn(token: token)
    }

    if access.isAuthorized {
      dismiss()
    }
  }
}
