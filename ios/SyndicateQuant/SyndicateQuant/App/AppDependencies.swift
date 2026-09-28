import Foundation
import SwiftData

@MainActor
final class AppDependencies {
  static let shared = AppDependencies()
  var container: ModelContainer?
  private init() {}
}
