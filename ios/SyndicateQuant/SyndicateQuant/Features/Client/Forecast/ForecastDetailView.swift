import Foundation
import SwiftUI
import SwiftData

struct SignalDetailView: View {
  let signal: BetSignal
  @EnvironmentObject var settings: AppSettings
  @State private var homeHistory: [TeamRecord] = []
  @State private var awayHistory: [TeamRecord] = []
  @State private var previewLoading = false
  @State private var previewError: String? = nil

  var body: some View {
    List {
      Section("Матч") {
        LabeledContent("Хозяева", value: signal.home)
        LabeledContent("Гости", value: signal.away)
        LabeledContent("Лига", value: signal.league)
        if let s = formatMatchStartLong(signal.startTime) {
          LabeledContent("Начало", value: s)
        }
        LabeledContent("Рынок", value: signal.market)
        LabeledContent("Выбор", value: selectionLine)
      }

      matchPreviewSection

      // [W3c] Data Health
      Section {
        HStack {
          Text("Sample").font(.subheadline)
          Spacer()
          Text(signal.sampleClass).font(.subheadline.bold())
            .foregroundStyle(sampleColor(signal.sampleClass))
        }
        LabeledContent("Матчей хозяев", value: "\(signal.homeSample)")
        LabeledContent("Матчей гостей", value: "\(signal.awaySample)")
        LabeledContent("Букмекеров", value: "\(signal.bookmakers)")
        LabeledContent("DCS", value: String(format: "%.0f", signal.dcs))
        LabeledContent("MS", value: String(format: "%.0f", signal.ms))
        if let mss = signal.mss {
          LabeledContent("MSS", value: String(format: "%.0f", mss))
        }
        LabeledContent("Uncertainty",
                       value: String(format: "%.3f · %@", signal.uncertainty, signal.uncertaintyBand))
        LabeledContent("Market MAD", value: String(format: "%.2f", signal.marketMAD))
        if let src = signal.oddsSource {
          LabeledContent("Источник", value: src)
        }
        if signal.sharpMoney == true {
          LabeledContent("Sharp", value: "да")
        }
        if signal.posteriorWeight != nil {
          LabeledContent("Posterior", value: "применён")
        }
        if signal.playerImpactHome != nil || signal.playerImpactAway != nil {
          LabeledContent("Player impact", value: "применён")
        }
      } header: {
        Text("Data Health (W3c)")
      } footer: {
        Text("Качество входных данных конкретного сигнала. FULL/GOOD — надёжно. USABLE — приемлемо. INS — мало данных, сигнал менее устойчив.")
      }

      if let src = signal.oddsSource {
        Section {
          LabeledContent("Источник", value: src)
          if signal.market == "CORNERS" {
            Text("Edge считается против sharp-линии Pinnacle (bookmakerId=4).")
              .font(.caption2).foregroundStyle(.secondary)
          } else if signal.market == "CARDS" {
            Text("Edge считается против лучшей доступной котировки среди букмекеров.")
              .font(.caption2).foregroundStyle(.secondary)
          }
        } header: {
          Text("Источник котировки")
        }
      }

      if let mss = signal.mss,
         signal.market == "CORNERS" || signal.market == "CARDS" {
        Section {
          HStack {
            Text("MSS").font(.subheadline.bold())
            Spacer()
            Text(String(format: "%.0f", mss))
              .font(.subheadline.monospacedDigit().bold())
              .foregroundStyle(mss >= 70 ? .green : (mss >= 40 ? .primary : .orange))
          }
        } header: {
          Text("Market support (MSS)")
        } footer: {
          Text("Оценка согласованности котировок: чем выше — тем сильнее рынок подтверждает сигнал. Учитывает ширину спреда между книгами и согласие sharp-книг.")
        }
      }

      Section {
        HStack {
          Text("Класс").font(.subheadline)
          Spacer()
          Text(signal.classification)
            .font(.subheadline.bold())
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(classColor.opacity(0.22)).clipShape(Capsule())
        }
        LabeledContent("Модель", value: signal.model)
        LabeledContent("Букмекеров", value: "\(signal.bookmakers)")
        if signal.priceAnomaly {
          Label("Аномальная цена (flag)", systemImage: "exclamationmark.triangle")
            .foregroundStyle(.orange).font(.caption)
        }
      } header: {
        Text("Классификация")
      } footer: {
        Text("S BET — лучший сигнал (EV ≥ 7%, QCS ≥ 85). A BET — хороший. B LEAN — edge есть. C WATCH — минимальный. X NO BET — не проходит фильтр.")
      }

      Section {
        LabeledContent("Odds", value: OddsFormatter.format(signal.odds, as: settings.oddsFormat))
        LabeledContent("Fair odds",
                       value: OddsFormatter.format(signal.fairOdds, as: settings.oddsFormat))
        LabeledContent("P (финальная)",
                       value: String(format: "%.2f%%", signal.probability * 100))
        if let raw = signal.probabilityRaw, raw != signal.probability {
          LabeledContent("P (модель)", value: String(format: "%.2f%%", raw * 100))
        }
        LabeledContent("P (рынок)",
                       value: String(format: "%.2f%%", signal.marketProbability * 100))
        LabeledContent("EV", value: String(format: "%+.2f%%", signal.ev * 100))
        LabeledContent("Robust EV", value: String(format: "%+.2f%%", signal.robustEV * 100))
      } header: {
        Text("Цена и вероятность")
      } footer: {
        Text("EV = p × odds − 1. Robust EV — то же, но с поправкой на неопределённость. Fair odds = 1/p.")
      }

      if let best = signal.bestOdds,
         let avg = signal.avgOdds,
         let worst = signal.worstOdds,
         let bestBook = signal.bestBook,
         let worstBook = signal.worstBook {
        Section("Odds comparison (D4)") {
          LabeledContent("Лучшая",
                         value: "\(OddsFormatter.format(best, as: settings.oddsFormat)) · \(bestBook)")
          LabeledContent("Средняя",
                         value: OddsFormatter.format(avg, as: settings.oddsFormat))
          LabeledContent("Худшая",
                         value: "\(OddsFormatter.format(worst, as: settings.oddsFormat)) · \(worstBook)")
          LabeledContent("Книг", value: "\(signal.bookmakers)")
        }
      }

      if let lm = signal.liveMovement {
        Section("Live movement (D1)") {
          LabeledContent("Средняя цена",
                         value: String(format: "%+.2f%%", lm * 100))
            .foregroundStyle(lm < 0 ? .green : .red)
          if signal.sharpMoney == true, let sm = signal.sharpMovement {
            HStack {
              Text("Sharp money")
              Spacer()
              Text(String(format: "да · %+.2f%%", sm * 100))
                .foregroundStyle(.purple).font(.subheadline.bold())
            }
          }
        }
      }

      if let vote = signal.modelVote {
        Section("Voting (D3)") {
          HStack {
            Text("Согласие моделей")
            Spacer()
            Text("\(vote)/4").font(.subheadline.bold())
              .foregroundStyle(vote >= 3 ? .green : (vote == 2 ? .orange : .red))
          }
        }
      }

      if let w = signal.posteriorWeight {
        Section("Posterior correction (B2)") {
          LabeledContent("Вес w", value: String(format: "%.2f", w))
          if let src = signal.posteriorSource {
            LabeledContent("Бакет", value: src)
          }
        }
      }

      if signal.stopApplied != nil {
        Section("Stop-loss (B5)") {
          if let reason = signal.stopApplied {
            LabeledContent("Применено", value: reason)
          }
          if let before = signal.stakeBeforeStop {
            LabeledContent("Стейк был", value: String(format: "%.3f%%", before * 100))
            LabeledContent("Стейк стал", value: String(format: "%.3f%%", signal.stake * 100))
          }
        }
      }

      if signal.playerImpactHome != nil || signal.playerImpactAway != nil {
        Section("Player impact (B6)") {
          if let hi = signal.playerImpactHome {
            LabeledContent("Дом. λ-множитель", value: String(format: "%.2f", hi))
          }
          if let ai = signal.playerImpactAway {
            LabeledContent("Гост. λ-множитель", value: String(format: "%.2f", ai))
          }
        }
      }

      Section {
        HStack {
          intervalBlock("P10", String(format: "%.1f%%", signal.probabilityLow * 100))
          intervalBlock("P50", String(format: "%.1f%%", signal.probability * 100))
          intervalBlock("P90", String(format: "%.1f%%", signal.probabilityHigh * 100))
        }
        LabeledContent("Uncertainty", value: String(format: "%.3f", signal.uncertainty))
        LabeledContent("Band", value: signal.uncertaintyBand)
        LabeledContent("Market MAD", value: String(format: "%.2f", signal.marketMAD))
      } header: {
        Text("Интервал неопределённости")
      } footer: {
        Text("P10/P50/P90 — вероятностный интервал. Узкий интервал = уверенная модель. Band влияет на размер стейка: LOW ×1.0, MED ×0.75, HIGH ×0.5.")
      }

      Section {
        Text("QCS = 0.30·MES + 0.20·DCS + 0.20·MS + 0.15·TS + 0.15·RS")
          .font(.caption2).foregroundStyle(.secondary)
        scoreRow("DCS", signal.dcs, w: "0.20")
        scoreRow("MS", signal.ms, w: "0.20")
        scoreRow("MES", signal.mes, w: "0.30")
        scoreRow("TS", signal.ts, w: "0.15")
        scoreRow("RS", signal.rs, w: "0.15")
        HStack {
          Text("QCS").font(.subheadline.bold())
          Spacer()
          Text(String(format: "%.1f", signal.qcs))
            .font(.subheadline.monospacedDigit().bold())
        }
      } header: {
        Text("Компоненты QCS")
      } footer: {
        Text("QCS — композитный скор качества сигнала (0–100). Порог для S BET — 85, для A BET — 78.")
      }

      Section("Sample") {
        LabeledContent("Класс", value: signal.sampleClass)
        LabeledContent("Матчей хозяев", value: "\(signal.homeSample)")
        LabeledContent("Матчей гостей", value: "\(signal.awaySample)")
      }

      Section {
        LabeledContent("Full Kelly",
                       value: String(format: "%.2f%%", signal.kellyFraction * 100))
        LabeledContent("Quarter Kelly",
                       value: String(format: "%.2f%%", signal.quarterKelly * 100))
        LabeledContent("Stake cap",
                       value: String(format: "%.2f%%", signal.stakeCap * 100))
        HStack {
          Text("Stake").font(.subheadline.bold())
          Spacer()
          if settings.useMoneyStakes, let money = signal.stakeMoney {
            Text(String(format: "%.0f", money))
              .font(.subheadline.monospacedDigit().bold())
          } else {
            Text(String(format: "%.3f%%", signal.stake * 100))
              .font(.subheadline.monospacedDigit().bold())
          }
        }
      } header: {
        Text("Kelly / Stake")
      } footer: {
        Text("Quarter Kelly — консервативный подход (25% от полной формулы Келли). Stake cap — верхняя граница по классу/рынку.")
      }

      if signal.portfolioCorrelation > 0 {
        Section("Портфель") {
          LabeledContent("Макс. корреляция",
                         value: String(format: "%.2f", signal.portfolioCorrelation))
          LabeledContent("Причина", value: signal.correlationReason)
        }
      }

      Section("Идентификаторы") {
        LabeledContent("Game ID", value: signal.gameID)
        LabeledContent("Signal ID", value: signal.id)
        LabeledContent("Timestamp",
                       value: signal.timestamp.formatted(date: .abbreviated, time: .standard))
      }

      Section { Color.clear.frame(height: 56).listRowBackground(Color.clear) }
    }
    .listStyle(.insetGrouped)
    .navigationTitle("Разбор сигнала")
    .navigationBarTitleDisplayMode(.inline)
    .task { await loadPreview() }
  }

  private func sampleColor(_ s: String) -> Color {
    switch s {
    case "FULL":   return .green
    case "GOOD":   return .blue
    case "USABLE": return .yellow
    default:       return .orange
    }
  }

  @ViewBuilder
  private var matchPreviewSection: some View {
    Section {
      if previewLoading && homeHistory.isEmpty && awayHistory.isEmpty {
        HStack {
          ProgressView().scaleEffect(0.8)
          Text("Загружаю последние 5 матчей…")
            .font(.caption).foregroundStyle(.secondary)
        }
      } else if let err = previewError {
        Text(err).font(.caption).foregroundStyle(.secondary)
      } else {
        marketFormBlock(title: signal.home, records: homeHistory,
                        accent: .blue, market: signal.market)
        marketFormBlock(title: signal.away, records: awayHistory,
                        accent: .purple, market: signal.market)
        Text(marketHintLine)
          .font(.caption2).foregroundStyle(.tertiary)
      }
    } header: {
      Text("Форма (последние 5 матчей)")
    }
  }

  private var marketHintLine: String {
    switch signal.market {
    case "CORNERS":
      return "В бейдже — свои углы · углы соперника в каждом матче. avg справа — средний тотал за 5 матчей."
    case "CARDS":
      return "В бейдже — свои ЖК · ЖК соперника в каждом матче. avg справа — средний тотал за 5 матчей."
    default:
      return "Показан счёт каждого матча и результат (В/Н/П)."
    }
  }

  @ViewBuilder
  private func marketFormBlock(title: String, records: [TeamRecord],
                               accent: Color, market: String) -> some View {
    let last5 = Array(records.prefix(5))
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(title).font(.subheadline.bold()).foregroundStyle(accent)
        Spacer()
        if !last5.isEmpty {
          Text(summaryFor(market: market, records: last5))
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
      }
      if last5.isEmpty {
        Text("Нет данных").font(.caption2).foregroundStyle(.secondary)
      } else {
        HStack(spacing: 6) {
          ForEach(Array(last5.enumerated()), id: \.offset) { (_, r) in
            formBadge(r, market: market)
          }
          Spacer()
        }
      }
    }
    .padding(.vertical, 2)
  }

  private func summaryFor(market: String, records: [TeamRecord]) -> String {
    switch market {
    case "CORNERS":
      let vals = records.compactMap { r -> Double? in
        guard let c = r.corners, let oc = r.oppCorners else { return nil }
        return c + oc
      }
      guard !vals.isEmpty else { return "avg —" }
      let avg = vals.reduce(0, +) / Double(vals.count)
      return String(format: "avg %.1f", avg)
    case "CARDS":
      let vals = records.compactMap { r -> Double? in
        guard let c = r.cardsPlusReds, let oc = r.oppCardsPlusReds else { return nil }
        return c + oc
      }
      guard !vals.isEmpty else { return "avg —" }
      let avg = vals.reduce(0, +) / Double(vals.count)
      return String(format: "avg %.1f", avg)
    default:
      var w = 0, d = 0, l = 0
      for r in records {
        guard let gf = r.gf, let ga = r.ga else { continue }
        if gf > ga { w += 1 } else if gf == ga { d += 1 } else { l += 1 }
      }
      return "\(w)В · \(d)Н · \(l)П"
    }
  }

  @ViewBuilder
  private func formBadge(_ r: TeamRecord, market: String) -> some View {
    switch market {
    case "CORNERS":
      let own = r.corners.map { String(format: "%.0f", $0) } ?? "—"
      let opp = r.oppCorners.map { String(format: "%.0f", $0) } ?? "—"
      VStack(spacing: 1) {
        Text("\(own)·\(opp)").font(.caption2.bold())
        Text("угл").font(.caption2).opacity(0.6)
        Text(r.isHome ? "Д" : "Г").font(.caption2).opacity(0.6)
      }
      .frame(width: 46, height: 46)
      .background(Color.blue.opacity(0.20))
      .clipShape(RoundedRectangle(cornerRadius: 6))

    case "CARDS":
      let own = r.cardsPlusReds.map { String(format: "%.0f", $0) } ?? "—"
      let opp = r.oppCardsPlusReds.map { String(format: "%.0f", $0) } ?? "—"
      VStack(spacing: 1) {
        Text("\(own)·\(opp)").font(.caption2.bold())
        Text("ЖК").font(.caption2).opacity(0.6)
        Text(r.isHome ? "Д" : "Г").font(.caption2).opacity(0.6)
      }
      .frame(width: 46, height: 46)
      .background(Color.orange.opacity(0.20))
      .clipShape(RoundedRectangle(cornerRadius: 6))

    default:
      let gf = r.gf ?? 0
      let ga = r.ga ?? 0
      let (resultChar, color): (String, Color) = {
        if gf > ga { return ("В", .green) }
        if gf == ga { return ("Н", .orange) }
        return ("П", .red)
      }()
      VStack(spacing: 1) {
        Text(resultChar).font(.caption2.bold())
        Text("\(Int(gf)):\(Int(ga))").font(.caption2.monospacedDigit())
        Text(r.isHome ? "Д" : "Г").font(.caption2).opacity(0.6)
      }
      .frame(width: 38, height: 46)
      .background(color.opacity(0.20))
      .clipShape(RoundedRectangle(cornerRadius: 6))
    }
  }

  private func loadPreview() async {
    if previewLoading { return }
    previewLoading = true
    previewError = nil
    defer { previewLoading = false }
    guard !settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { previewError = "Нет API key"; return }

    let client = SStatsClient(settings: settings)
    do {
      let info = try await client.gameInfo(signal.gameID)
      guard let data = info.object?["data"]?.object,
            let game = data["game"]?.object
      else { previewError = "Нет данных матча"; return }

      func extractID(_ side: String) -> String? {
        if let s = game[side + "TeamId"]?.string, !s.isEmpty { return s }
        if let s = game[side + "TeamID"]?.string, !s.isEmpty { return s }
        if let n = game[side + "TeamId"]?.number { return String(Int(n)) }
        if let t = game[side + "Team"]?.object {
          if let s = t["id"]?.string, !s.isEmpty { return s }
          if let n = t["id"]?.number { return String(Int(n)) }
        }
        return nil
      }

      guard let hID = extractID("home"), let aID = extractID("away") else {
        previewError = "Не удалось определить команды"; return
      }

      async let hFetch = client.fetchTeamHistoryEnriched(teamID: hID, count: 5)
      async let aFetch = client.fetchTeamHistoryEnriched(teamID: aID, count: 5)
      let (h, a) = await (hFetch, aFetch)
      homeHistory = h; awayHistory = a
      if h.isEmpty && a.isEmpty {
        previewError = "Нет данных по последним матчам"
      }
    } catch {
      previewError = "Ошибка загрузки: \(error.localizedDescription)"
    }
  }

  private var selectionLine: String {
    if let line = signal.line { return "\(signal.selection) \(line)" }
    return signal.selection
  }

  private var classColor: Color {
    switch signal.classification {
    case "S BET": return .green
    case "A BET": return .blue
    case "B LEAN": return .yellow
    case "C WATCH": return .orange
    default: return .gray
    }
  }

  private func intervalBlock(_ label: String, _ value: String) -> some View {
    VStack(spacing: 2) {
      Text(label).font(.caption2).foregroundStyle(.secondary)
      Text(value).font(.subheadline.monospacedDigit())
    }.frame(maxWidth: .infinity)
  }

  private func scoreRow(_ name: String, _ value: Double, w: String) -> some View {
    HStack {
      Text(name).font(.subheadline)
      Text("· w=\(w)").font(.caption2).foregroundStyle(.secondary)
      Spacer()
      Text(String(format: "%.1f", value)).font(.subheadline.monospacedDigit())
    }
  }
}
