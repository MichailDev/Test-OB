import SwiftData

@MainActor
final class PersistenceController {
  static let shared = PersistenceController()

  let container: ModelContainer

  private init() {
    let schema = Schema(AppSchema.models)
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
    do {
      container = try ModelContainer(for: schema, configurations: [configuration])
    } catch {
      fatalError("Persistent store initialization failed: \(error)")
    }
  }
}
