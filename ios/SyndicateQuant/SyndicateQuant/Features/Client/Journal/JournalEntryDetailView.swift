import Foundation
import SwiftUI
import SwiftData

struct JournalEntryDetailView: View {
  let entry: JournalEntry
  @EnvironmentObject var settings: AppSettings

  var body: some View {
    List {
      Section("Матч") {
        LabeledContent("Хозяева", value: entry.home)
        LabeledContent("Гости", value: entry.away)
        LabeledContent("Лига", value: entry.league)
        if let s = formatMatchStartLong(entry.matchStart) {
          LabeledContent("Начало", value: s)
        }
        LabeledContent("Рынок", value: entry.market)
        LabeledContent("Выбор", value: selectionLine)
      }
      Section("Статус") {
        LabeledContent("Класс", value: entry.classification)
        LabeledContent("Статус", value: entry.status)
        if let r = entry.result { LabeledContent("Результат", value: r) }
        if let p = entry.profit {
          if let sm = entry.stakeMoney, entry.stake > 0 {
            let money = p / entry.stake * sm
            LabeledContent("P/L", value: String(format: "%+.0f", money))
              .foregroundStyle(p >= 0 ? .green : .red)
          } else {
            LabeledContent("P/L", value: String(format: "%+.3f", p))
              .foregroundStyle(p >= 0 ? .green : .red)
          }
        }
        if let clv = entry.clv {
          LabeledContent("CLV", value: String(format: "%+.2f%%", clv * 100))
            .foregroundStyle(clv > 0 ? .green : .red)
        }
        if let mv = entry.movement {
          LabeledContent("Движение линии", value: String(format: "%+.2f%%", mv * 100))
            .foregroundStyle(mv > 0 ? .green : .red)
        }
      }
      Section("Коэффициенты") {
        LabeledContent("Odds",
                       value: OddsFormatter.format(entry.odds, as: settings.oddsFormat))
        if let open = entry.openingOdds {
          LabeledContent("Открытие",
                         value: OddsFormatter.format(open, as: settings.oddsFormat))
        }
        if let close = entry.closingOdds {
          LabeledContent("Закрытие",
                         value: OddsFormatter.format(close, as: settings.oddsFormat))
        }
      }
      Section("Модель") {
        LabeledContent("P", value: String(format: "%.2f%%", entry.probability * 100))
        LabeledContent("EV", value: String(format: "%+.2f%%", entry.ev * 100))
        LabeledContent("Robust EV", value: String(format: "%+.2f%%", entry.robustEV * 100))
        LabeledContent("QCS", value: String(format: "%.1f", entry.qcs))
        LabeledContent("DCS", value: String(format: "%.1f", entry.dcs))
        LabeledContent("Stake", value: String(format: "%.3f%%", entry.stake * 100))
      }
      Section("Идентификаторы") {
        LabeledContent("Game ID", value: entry.gameID)
        LabeledContent("Signal ID", value: entry.id)
        LabeledContent("Создан",
                       value: entry.createdAt.formatted(date: .abbreviated, time: .standard))
      }
      Section { Color.clear.frame(height: 56).listRowBackground(Color.clear) }
    }
    .listStyle(.insetGrouped)
    .navigationTitle("Разбор записи")
    .navigationBarTitleDisplayMode(.inline)
  }

  private var selectionLine: String {
    if let line = entry.line { return "\(entry.selection) \(line)" }
    return entry.selection
  }
}
