import SwiftData

@MainActor
final class PersistenceController {
  static let shared = PersistenceController()

  let container: ModelContainer

  private init() {
    let schema = Schema(versionedSchema: AppSchemaV4.self)
    let configuration = ModelConfiguration(
      schema: schema,
      isStoredInMemoryOnly: false
    )

    do {
      container = try ModelContainer(
        for: schema,
        migrationPlan: AppMigrationPlan.self,
        configurations: [configuration]
      )
      AppDependencies.shared.container = container
    } catch {
      fatalError("Persistent store initialization failed: \(error)")
    }
  }
}
