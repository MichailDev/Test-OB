import SwiftUI

struct SettingsView: View {
  @EnvironmentObject private var settings: AppSettings
  @EnvironmentObject private var subscription: SubscriptionService
  @EnvironmentObject private var adminAccess: AdminAccessService
  @State private var showAdmin = false

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

      Section("Подписка") {
        HStack {
          Text("S BET")
          Spacer()
          Text(subscription.isSubscribed ? "Активна" : "Не активна")
            .foregroundStyle(subscription.isSubscribed ? .green : .secondary)
        }
        if !subscription.isSubscribed {
          Button("Управление подпиской") { }
        }
      }

      if adminAccess.isAuthorized {
        Section("Администратор") {
          Button("Открыть Admin") { showAdmin = true }
        }
      }
    }
    .navigationTitle("Настройки")
    .navigationBarTitleDisplayMode(.large)
    .sheet(isPresented: $showAdmin) { AdminConsoleView() }
  }
}
