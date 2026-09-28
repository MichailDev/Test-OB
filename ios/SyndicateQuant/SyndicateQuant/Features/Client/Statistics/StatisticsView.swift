import SwiftUI
import SwiftData

struct StatisticsView: View {
  @Query(sort: \JournalEntry.createdAt, order: .reverse) private var journal: [JournalEntry]
  @State private var filter: BetTierFilter = .all

  private var visible: [JournalEntry] {
    switch filter {
    case .all: return journal
    case .free: return journal.filter { BetTier(classification: $0.classification) == .free }
    case .premium: return journal.filter { BetTier(classification: $0.classification) == .premium }
    }
  }

  var body: some View {
    List {
      Picker("Тип", selection: $filter) {
        ForEach(BetTierFilter.allCases) { Text($0.title).tag($0) }
      }
      .pickerStyle(.segmented)

      let metrics = Metrics.compute(visible)
      Section("Прогнозы") {
        metric("Ставок", "\(metrics.totalEntries)")
        metric("Закрыто", "\(metrics.closedEntries)")
        metric("WIN", "\(metrics.wins)")
        metric("LOSS", "\(metrics.losses)")
        metric("ROI", String(format: "%.2f%%", metrics.roi * 100))
        metric("CLV", String(format: "%+.2f%%", metrics.avgCLV * 100))
        metric("Brier", String(format: "%.4f", metrics.brier))
        metric("LogLoss", String(format: "%.4f", metrics.logLoss))
      }
      Section("По типу") {
        Text("A BET и S BET считаются отдельно по фильтру выше.").font(.caption).foregroundStyle(.secondary)
      }
    }
    .navigationTitle("Статистика")
    .navigationBarTitleDisplayMode(.large)
  }

  private func metric(_ title: String, _ value: String) -> some View {
    HStack { Text(title); Spacer(); Text(value).font(.monospacedDigit()) }
  }
}

enum BetTierFilter: String, CaseIterable, Identifiable {
  case all, free, premium
  var id: String { rawValue }
  var title: String {
    switch self {
    case .all: return "Все"
    case .free: return "A BET"
    case .premium: return "S BET"
    }
  }
}
