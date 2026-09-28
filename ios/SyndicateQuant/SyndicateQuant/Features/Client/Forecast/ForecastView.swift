import SwiftUI
import SwiftData

struct ForecastView: View {
  @EnvironmentObject private var settings: AppSettings
  @EnvironmentObject private var subscription: SubscriptionService
  @Environment(\.modelContext) private var context
  @State private var signals: [BetSignal] = []
  @State private var status = "Готов"
  @State private var busy = false

  private var paidCount: Int { signals.filter { BetTier(classification: $0.classification) == .premium }.count }
  private var freeCount: Int { signals.filter { BetTier(classification: $0.classification) == .free }.count }

  var body: some View {
    List {
      Section {
        HStack {
          Text(status).font(.subheadline)
          Spacer()
          if busy { ProgressView().scaleEffect(0.9) }
        }
        HStack {
          Label("\(freeCount) A BET", systemImage: "lock.open")
          Spacer()
          Label("\(paidCount) S BET", systemImage: "lock")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        Button { Task { await refresh() } } label: {
          Label("Обновить", systemImage: "arrow.clockwise")
        }
        .disabled(busy)
      } footer: {
        Text("Анализируются все доступные матчи дня, кроме товарищеских и женских соревнований. Количество прогнозов не ограничивается — проходят только сигналы, выдержавшие quality gates.")
      }

      if signals.isEmpty {
        Section {
          ContentUnavailableView("Нет подтверждённых ставок", systemImage: "checkmark.shield",
            description: Text("NO DATA → NO NUMBER → NO EDGE → NO BET"))
        }
      } else {
        ForEach(signals) { signal in
          let tier = BetTier(classification: signal.classification)
          if tier == .premium && !subscription.isSubscribed {
            Section {
              HStack {
                VStack(alignment: .leading, spacing: 4) {
                  Text("\(signal.home) — \(signal.away)").font(.headline)
                  Text("S BET · доступ по подписке").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "lock.fill")
              }
            }
          } else {
            NavigationLink {
              SignalDetailView(signal: signal).onAppear { addToJournal(signal) }
            } label: {
              SignalCard(signal: signal, oddsFormat: settings.oddsFormat)
            }
          }
        }
      }
    }
    .listStyle(.insetGrouped)
    .navigationTitle("Прогноз")
    .navigationBarTitleDisplayMode(.large)
    .refreshable { await refresh() }
    .task { await refresh() }
  }

  private func refresh() async {
    guard !busy else { return }
    busy = true
    defer { busy = false }
    let summary = await ScanCoordinator.shared.scan(settings: settings, selectedLeague: "Все")
    signals = summary.signals
    status = summary.success ? "Обновлено · \(signals.count) сигналов" : (summary.notes.first ?? "Ошибка")
    if !subscription.isSubscribed { await subscription.refreshEntitlement() }
  }

  private func addToJournal(_ signal: BetSignal) {
    let d = FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.id == signal.id })
    if (try? context.fetch(d).first) == nil {
      context.insert(JournalEntry(signal: signal))
      try? context.save()
    }
  }
}
