import SwiftUI
import SwiftData

struct JournalView: View {
  @EnvironmentObject private var settings: AppSettings
  @Environment(\.modelContext) private var context
  @Query(sort: \JournalEntry.createdAt, order: .reverse) private var journal: [JournalEntry]
  @State private var busy = false
  @State private var status = ""

  var body: some View {
    List {
      Section {
        Button { Task { await settle() } } label: {
          Label("Обновить результаты", systemImage: "checkmark.circle")
        }
        .disabled(busy)
        if !status.isEmpty { Text(status).font(.caption).foregroundStyle(.secondary) }
      } header: { Text("Settlement") }

      if journal.isEmpty {
        Section { ContentUnavailableView("Журнал пуст", systemImage: "tray") }
      } else {
        Section("Ставки") {
          ForEach(journal) { entry in
            NavigationLink { JournalEntryDetailView(entry: entry) } label: {
              VStack(alignment: .leading, spacing: 4) {
                HStack {
                  Text("\(entry.classification) · \(entry.market)").font(.caption).bold()
                  Spacer()
                  Text(entry.result ?? "OPEN").font(.caption).monospacedDigit()
                }
                Text("\(entry.home) — \(entry.away)").font(.headline)
                HStack {
                  Text(formatMatchStart(entry.matchStart) ?? formatMatchStart(entry.createdAt) ?? "—")
                  Spacer()
                  Text(String(format: "%.2f", entry.odds))
                }.font(.caption).foregroundStyle(.secondary)
              }
            }
            .swipeActions(edge: .trailing) {
              Button(role: .destructive) { context.delete(entry); try? context.save() } label: {
                Label("Удалить", systemImage: "trash")
              }
            }
          }
        }
      }
    }
    .listStyle(.insetGrouped)
    .navigationTitle("Журнал")
    .navigationBarTitleDisplayMode(.large)
  }

  private func settle() async {
    guard !busy else { return }
    busy = true
    defer { busy = false }
    guard !settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      status = "API key не задан"
      return
    }
    status = "Обновляю…"
    let result = await JournalService.settleOpenEntries(context: context, client: SStatsClient(settings: settings))
    status = "Закрыто \(result.closed), ошибок \(result.failed)"
  }
}
