import SwiftUI
import SwiftData

@main
struct OverBetApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @StateObject private var settings = AppSettings()

  private let container = PersistenceController.shared.container

  var body: some Scene {
    WindowGroup {
      RootView()
        .environmentObject(settings)
        .environmentObject(SubscriptionService.shared)
        .environmentObject(AdminAccessService.shared)
    }
    .modelContainer(container)
  }
}
