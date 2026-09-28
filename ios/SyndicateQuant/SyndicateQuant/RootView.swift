import SwiftUI

struct RootView: View {
  var body: some View {
    TabView {
      NavigationStack { ForecastView() }
        .tabItem { Label("Прогноз", systemImage: "sparkles") }
      NavigationStack { StatisticsView() }
        .tabItem { Label("Статистика", systemImage: "chart.bar.xaxis") }
      NavigationStack { JournalView() }
        .tabItem { Label("Журнал", systemImage: "list.bullet.rectangle") }
      NavigationStack { SettingsView() }
        .tabItem { Label("Настройки", systemImage: "gearshape") }
    }
  }
}
