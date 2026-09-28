import Foundation
import SwiftUI
import SwiftData
import Charts

struct AdminConsoleView: View {
  @EnvironmentObject var settings: AppSettings
  @EnvironmentObject var adminAccess: AdminAccessService
  @ObservedObject private var liveMonitor = LiveMonitor.shared
  @Environment(\.modelContext) private var context
  @Query(sort: \JournalEntry.createdAt, order: .reverse) private var journal: [JournalEntry]
  @Query private var snapshots: [BacktestSnapshot]
  @Query(sort: \TeamRating.rating, order: .reverse) private var teamRatings: [TeamRating]
  @Query private var tuningConfigs: [TuningConfig]
  @Query(sort: \TuningEvent.createdAt, order: .reverse) private var tuningEvents: [TuningEvent]

  @State private var signals: [BetSignal] = []
  @State private var status = "Готов"
  @State private var busy = false
  @State private var lastRefresh: Date?
  @State private var diagnostics: [String] = []
  @State private var selectedLeague: String = "Все"

  @State private var apiReachable: String = "—"
  @State private var apiKeyState: String = "—"
  @State private var lastSettleStatus: String = "—"
  @State private var btProgressText = ""
  @State private var selectedTab: Int = 0
  @State private var selfTestResults: [QuantMathSelfTest.Check] = []

  private var currentSnapshot: BacktestSnapshot? { snapshots.first }
  private var tuningConfig: TuningConfig? { tuningConfigs.first }
  private var correlationMatrix: CorrelationMatrix {
    CorrelationBuilder.build(from: journal)
  }

  var body: some View {
    Group {
      if adminAccess.isAuthorized {
        TabView(selection: $selectedTab) {
          NavigationStack { autoView }
            .tabItem { Label("Model Lab", systemImage: "function") }.tag(0)
          NavigationStack { diagnosticsView }
            .tabItem { Label("Data Health", systemImage: "checkmark.shield") }.tag(1)
          NavigationStack { settingsView }
            .tabItem { Label("Controls", systemImage: "slider.horizontal.3") }.tag(2)
        }
      } else {
        ContentUnavailableView(
          "Admin закрыт",
          systemImage: "lock.shield",
          description: Text("Доступ выдаётся только сервером после проверки роли admin.")
        )
        .overlay(alignment: .bottom) {
          Button("Проверить доступ") {
            Task { await adminAccess.refreshAuthorization() }
          }
          .buttonStyle(.borderedProminent)
          .padding(.bottom, 24)
        }
      }
    }
    .tint(.blue)
    .preferredColorScheme(settings.colorScheme.toColorScheme)
    .task {
      await adminAccess.refreshAuthorization()
      guard adminAccess.isAuthorized else { return }
      _ = BacktestService.fetchOrCreate(in: context)
      _ = TuningService.fetchOrCreate(in: context)
      if currentSnapshot?.buildStatus == "building",
         BacktestService.hasCheckpoint() {
        await runFullBuild()
      }
    }
  }

  // MARK: - CLV-first

  @ViewBuilder
  private var clvFirstSection: some View {
    let rep = Metrics.clvReport(journal)
    Section {
      HStack {
        Text("Вердикт").font(.subheadline)
        Spacer()
        Text(rep.verdict).font(.subheadline.bold())
          .foregroundStyle(clvVerdictColor(rep.verdict))
      }
      Text(rep.note).font(.caption).foregroundStyle(.secondary)

      if rep.totalWithCLV == 0 {
        Text("Пока нет записей с CLV. Запустите settle после тура.")
          .font(.caption2).foregroundStyle(.secondary)
      } else {
        HStack(spacing: 14) {
          miniBlock("+CLV", "\(rep.positiveCount)")
          miniBlock("±0", "\(rep.neutralCount)")
          miniBlock("−CLV", "\(rep.negativeCount)")
          miniBlock("Доля +", String(format: "%.0f%%", rep.positiveRate * 100))
        }
        HStack(spacing: 14) {
          miniBlock("avg CLV", String(format: "%+.2f%%", rep.avgCLV * 100))
          miniBlock("median", String(format: "%+.2f%%", rep.medianCLV * 100))
          miniBlock("P/L +CLV", String(format: "%+.3f", rep.pnlPositive))
            .foregroundStyle(rep.pnlPositive >= 0 ? .green : .red)
          miniBlock("P/L −CLV", String(format: "%+.3f", rep.pnlNegative))
            .foregroundStyle(rep.pnlNegative >= 0 ? .green : .red)
        }
        if !rep.byMarket.isEmpty {
          Text("По рынкам:").font(.caption2).foregroundStyle(.secondary)
          ForEach(rep.byMarket.keys.sorted(), id: \.self) { mk in
            if let m = rep.byMarket[mk] {
              HStack {
                Text(mk).font(.caption.monospacedDigit())
                Spacer()
                Text(String(format: "n=%d · +%.0f%% · avg %+.2f%%",
                            m.count, m.positiveRate * 100, m.avgCLV * 100))
                  .font(.caption2.monospacedDigit())
                  .foregroundStyle(m.avgCLV > 0 ? .green : .red)
              }
            }
          }
        }
        Text("Порог «+CLV» = +0.5%, «−CLV» = −0.5%.")
          .font(.caption2).foregroundStyle(.tertiary)
      }
    } header: {
      Text("CLV-first")
    } footer: {
      Text("CLV-first — отдельно измеряем, берут ли сигналы систематически лучшую цену, чем закрытие. STRONG/OK = edge до рынка подтверждён. NEGATIVE = цена хуже закрытия, стратегия под вопросом.")
    }
  }

  private func clvVerdictColor(_ v: String) -> Color {
    switch v {
    case "STRONG":   return .green
    case "OK":       return .blue
    case "WEAK":     return .yellow
    case "MIXED":    return .orange
    case "NEGATIVE": return .red
    default:         return .gray
    }
  }

  @ViewBuilder
  private var equitySection: some View {
    let curve = Metrics.equityCurve(journal, bankroll: settings.effectiveBankroll)
    let bands = Metrics.bollingerBands(curve, window: 20, sigmaMultiplier: 2.0)
    let breakouts = bands.filter { $0.isBreakout }
    let lastBand = bands.last

    Section {
      if curve.count < 2 {
        Text("Нужно минимум 2 закрытые записи")
          .font(.caption).foregroundStyle(.secondary)
      } else {
        Chart {
          ForEach(bands) { p in
            if let u = p.upper {
              LineMark(x: .value("Дата", p.date), y: .value("Upper", u))
                .foregroundStyle(.gray.opacity(0.45))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            if let l = p.lower {
              LineMark(x: .value("Дата", p.date), y: .value("Lower", l))
                .foregroundStyle(.gray.opacity(0.45))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            if let m = p.ma {
              LineMark(x: .value("Дата", p.date), y: .value("MA", m))
                .foregroundStyle(.purple.opacity(0.65))
                .lineStyle(StrokeStyle(lineWidth: 1))
            }
          }
          ForEach(curve) { p in
            AreaMark(x: .value("Дата", p.date),
                     y: .value("P/L", p.cumulativeProfit))
              .foregroundStyle(.blue.opacity(0.15))
            LineMark(x: .value("Дата", p.date),
                     y: .value("P/L", p.cumulativeProfit))
              .foregroundStyle(.blue)
          }
          ForEach(breakouts) { p in
            PointMark(x: .value("Дата", p.date),
                      y: .value("P/L", p.value))
              .foregroundStyle(p.value > (p.upper ?? .infinity) ? .green : .red)
              .symbolSize(55)
          }
        }
        .frame(height: 200)

        HStack {
          Text("Точек: \(curve.count)")
          Spacer()
          if let last = curve.last {
            if settings.useMoneyStakes {
              Text(String(format: "Итог: %+.0f", last.cumulativeProfit))
                .foregroundStyle(last.cumulativeProfit >= 0 ? .green : .red)
            } else {
              Text(String(format: "Итог: %+.3f", last.cumulativeProfit))
                .foregroundStyle(last.cumulativeProfit >= 0 ? .green : .red)
            }
          }
        }
        .font(.caption)

        if let lb = lastBand, let ma = lb.ma, let u = lb.upper, let l = lb.lower {
          HStack(spacing: 14) {
            miniBlock("MA(20)", String(format: "%+.3f", ma))
            miniBlock("Upper", String(format: "%+.3f", u))
            miniBlock("Lower", String(format: "%+.3f", l))
            miniBlock("Breakouts", "\(breakouts.count)")
          }
          .padding(.vertical, 2)

          let risk = BollingerRisk.evaluate(bands, window: 20)
          HStack(spacing: 8) {
            Text("Risk").font(.caption2).foregroundStyle(.secondary)
            Text(risk.state.rawValue).font(.caption.bold())
              .foregroundStyle(bollingerRiskColor(risk.state))
            Spacer()
            if let w = risk.width, let aw = risk.avgWidth {
              Text(String(format: "w %.3f / avg %.3f", w, aw))
                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            Text(String(format: "BO %d/%d",
                        risk.recentBreakouts, risk.window))
              .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
          }
          Text(risk.note).font(.caption2).foregroundStyle(.tertiary)
        } else {
          Text("Полосы Боллинджера появятся после 20 закрытых записей.")
            .font(.caption2).foregroundStyle(.secondary)
        }
      }
    } header: {
      Text("Equity curve")
    } footer: {
      Text("Накопленный P/L. Синяя — факт. Фиолетовая MA(20) — скользящее среднее. Серые пунктиры — MA ± 2σ (полосы Боллинджера). Точки — breakout. BollingerRisk — диагностика волатильности P/L (не влияет на размер стейка).")
    }
  }

  private func journalStatsView() -> some View {
    let m = Metrics.compute(journal)
    return VStack(alignment: .leading, spacing: 8) {
      HStack {
        statBlock("Всего", "\(m.totalEntries)")
        statBlock("Closed", "\(m.closedEntries)")
        statBlock("Pending", "\(m.pending)")
      }
      HStack {
        statBlock("W/L/P", "\(m.wins)/\(m.losses)/\(m.pushes)")
        statBlock("Hit", String(format: "%.1f%%", m.hitRate * 100))
        statBlock("ROI", String(format: "%+.2f%%", m.roi * 100))
      }
      HStack {
        statBlock("CLV ср.", String(format: "%+.2f%%", m.avgCLV * 100))
        statBlock("Brier", String(format: "%.3f", m.brier))
        statBlock("LogLoss", String(format: "%.3f", m.logLoss))
      }
    }
    .padding(.vertical, 2)
  }

  private func calibrationView() -> some View {
    let m = Metrics.compute(journal)
    if m.calibration.isEmpty {
      return AnyView(Text("Недостаточно закрытых записей для калибровки")
        .font(.caption).foregroundStyle(.secondary))
    }
    return AnyView(
      VStack(alignment: .leading, spacing: 4) {
        ForEach(m.calibration) { b in
          HStack {
            Text(String(format: "P=%.0f%%", b.midpoint * 100))
              .font(.caption.monospacedDigit()).frame(width: 60, alignment: .leading)
            Text(String(format: "act %.0f%%", b.actual * 100))
              .font(.caption.monospacedDigit())
              .foregroundStyle(abs(b.predicted - b.actual) < 0.08 ? .green : .orange)
            Spacer()
            Text("n=\(b.count)").font(.caption2).foregroundStyle(.secondary)
          }
        }
        Text("CalErr: \(String(format: "%.3f", Metrics.calibrationError(m)))")
          .font(.caption).foregroundStyle(.secondary)
      }
    )
  }

  private func journalRow(_ e: JournalEntry) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text("\(e.home) — \(e.away)").font(.headline)
        Spacer()
        Text(e.classification).font(.caption.bold())
          .padding(.horizontal, 8).padding(.vertical, 3)
          .background(.thinMaterial).clipShape(Capsule())
      }
      if let s = formatMatchStart(e.matchStart) {
        HStack(spacing: 4) {
          Image(systemName: "clock")
          Text(s)
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
      }
      Text("\(e.league) · \(e.market) · \(e.selection)\(e.line.map { " \($0)" } ?? "")")
        .font(.subheadline).foregroundStyle(.secondary)
      HStack(spacing: 12) {
        miniBlock("Odds", OddsFormatter.format(e.odds, as: settings.oddsFormat))
        miniBlock("P", String(format: "%.0f%%", e.probability * 100))
        miniBlock("EV", String(format: "%+.1f%%", e.ev * 100))
        miniBlock("QCS", String(format: "%.0f", e.qcs))
        miniBlock("Stake", String(format: "%.2f%%", e.stake * 100))
      }
      HStack(spacing: 12) {
        statusBadge(e.status)
        if let r = e.result { resultBadge(r) }
        if let clv = e.clv {
          Text("CLV \(String(format: "%+.2f%%", clv * 100))")
            .font(.caption2.monospacedDigit())
            .foregroundStyle(clv > 0 ? .green : .red)
        }
        if let mv = e.movement {
          Text("Δ \(String(format: "%+.2f%%", mv * 100))")
            .font(.caption2.monospacedDigit())
            .foregroundStyle(mv > 0 ? .green : .red)
        }
        if let p = e.profit {
          let label: String = {
            if let sm = e.stakeMoney, e.stake > 0 {
              let money = p / e.stake * sm
              return String(format: "P/L %+.0f", money)
            }
            return String(format: "P/L %+.3f", p)
          }()
          Text(label)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(p >= 0 ? .green : .red)
        }
      }
    }
    .padding(.vertical, 2)
  }

  private func statusBadge(_ status: String) -> some View {
    Text(status).font(.caption2.bold())
      .padding(.horizontal, 6).padding(.vertical, 2)
      .background(status == "CLOSED" ? Color.gray.opacity(0.3) : Color.blue.opacity(0.25))
      .clipShape(Capsule())
  }

  private func resultBadge(_ r: String) -> some View {
    let color: Color
    switch r {
    case "WIN": color = .green
    case "LOSS": color = .red
    case "PUSH": color = .orange
    default: color = .gray
    }
    return Text(r).font(.caption2.bold())
      .padding(.horizontal, 6).padding(.vertical, 2)
      .background(color.opacity(0.25)).clipShape(Capsule())
  }

  private func statBlock(_ label: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label).font(.caption2).foregroundStyle(.secondary)
      Text(value).font(.subheadline.monospacedDigit())
    }.frame(maxWidth: .infinity, alignment: .leading)
  }

  private func miniBlock(_ n: String, _ v: String) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(n).font(.caption2).foregroundStyle(.secondary)
      Text(v).font(.caption.monospacedDigit())
    }
  }

  private func bollingerRiskColor(_ s: BollingerRisk.State) -> Color {
    switch s {
    case .normal:    return .green
    case .expanding: return .yellow
    case .high:      return .orange
    case .risk:      return .red
    }
  }

  private func marketRegimeColor(_ r: MarketRegime) -> Color {
    switch r {
    case .normal:          return .green
    case .highVolatility:  return .orange
    case .lowLiquidity:    return .yellow
    case .lineDislocation: return .red
    case .unknown:         return .gray
    }
  }

  private func oosMarketColor(_ roi: Double, threshold: Double) -> Color {
    if roi < threshold { return .red }
    if roi < 0 { return .orange }
    return .green
  }

  // MARK: - Авто

  private var autoView: some View {
    List {
      Section {
        Text("Backtest Service").font(.headline)
        Text("Все механизмы автотюнинга, обучения и диагностики. Здесь собирается база за 2 года, обогащаются котировки углов/ЖК, настраиваются пороги, и ведутся отчёты OOS + walk-forward.")
          .font(.caption).foregroundStyle(.secondary)
      }

      selfTuningLinkSection
      enrichmentSection
      liveMonitorSection
      leagueMarketHeatmapSection
      modelComparisonSection
      walkForwardSection
      oosValidationSection

      volatilitySection
      correlationSection
      playerImpactSection

      if let snap = currentSnapshot {
        Section {
          LabeledContent("Состояние", value: snap.buildStatus)
          ProgressView(value: snap.buildProgress)
          LabeledContent("Прогресс",
                         value: String(format: "%.1f%%", snap.buildProgress * 100))
          if let f = snap.fromDate, let t = snap.toDate {
            LabeledContent("Период",
                           value: "\(Self.shortDate(f)) – \(Self.shortDate(t))")
          }
          if let b = snap.builtAt {
            LabeledContent("Собран",
                           value: b.formatted(date: .abbreviated, time: .shortened))
          }
          LabeledContent("Матчей", value: "\(snap.totalMatches)")
          LabeledContent("Ставок", value: "\(snap.totalBets)")
          if snap.totalBets > 0 {
            LabeledContent("avgROI", value: String(format: "%+.2f%%", snap.avgROI * 100))
            LabeledContent("Sharpe", value: String(format: "%.2f", snap.sharpe))
            LabeledContent("Sortino", value: String(format: "%.2f", snap.sortino))
            LabeledContent("Profit Factor", value: String(format: "%.2f", snap.profitFactor))
            LabeledContent("Brier", value: String(format: "%.3f", snap.brier))
            LabeledContent("avgCLV", value: String(format: "%+.2f%%", snap.avgCLV * 100))
          }
          if let err = snap.lastError {
            Text(err).font(.caption).foregroundStyle(.red)
          }
        } header: {
          Text("Статус снапшота")
        } footer: {
          Text("Снапшот — агрегат по всей собранной базе: средний ROI, Sharpe, Sortino, Profit Factor, Brier, avgCLV. Обновляется после каждого пересбора или докачки.")
        }
      }

      Section {
        let snap = currentSnapshot
        let isResumable = (snap?.buildStatus == "building"
                           && (snap?.buildMatchesCount ?? 0) > 0)
        Button { Task { await runFullBuild() } } label: {
          if isResumable {
            Label("Продолжить сбор · \(snap?.buildMatchesCount ?? 0) матчей",
                  systemImage: "arrow.clockwise.circle")
          } else {
            Label("Собрать базу (2 года × 11 лиг)", systemImage: "arrow.down.circle")
          }
        }
        .disabled(busy)

        Button { Task { await runIncremental() } } label: {
          Label("Докачать за неделю", systemImage: "arrow.triangle.2.circlepath")
        }
        .disabled(busy || currentSnapshot?.buildStatus != "ready")

        if !btProgressText.isEmpty {
          Text(btProgressText).font(.caption.monospaced()).foregroundStyle(.secondary)
        }
      } header: {
        Text("Действия")
      } footer: {
        Text("Прогресс сборки сохраняется после каждого месяца в Documents/build_checkpoint.json — можно смело сворачивать и возвращаться. Докачка берёт только последние 7 дней.")
      }

      if let snap = currentSnapshot {
        autoExcludeSection(snap)
        posteriorSection(snap)
        leagueSection(snap)
        marketSection(snap)
        evSection(snap)
        oddsSection(snap)
        classSection(snap)
      }

      teamRatingsSection

      Section {
        Text("NO DATA → NO NUMBER → NO EDGE → NO BET").font(.subheadline).bold()
      } header: {
        Text("Принцип")
      }

      Section { Color.clear.frame(height: 56).listRowBackground(Color.clear) }
    }
    .listStyle(.insetGrouped)
    .navigationTitle("Авто")
    .navigationBarTitleDisplayMode(.large)
  }

  @ViewBuilder
  private var enrichmentSection: some View {
    if let snap = currentSnapshot, snap.enrichmentTotal > 0 {
      Section {
        let done = snap.enrichmentProgress
        let total = max(snap.enrichmentTotal, 1)
        let progress = Double(done) / Double(total)
        ProgressView(value: progress)
        HStack {
          Text("Обогащено")
          Spacer()
          Text("\(done) / \(total)")
            .font(.subheadline.monospacedDigit().bold())
            .foregroundStyle(done >= total ? .green : .primary)
        }
        if done >= total {
          Text("Все матчи обогащены углами и ЖК.")
            .font(.caption2).foregroundStyle(.secondary)
        } else {
          Button {
            Task { await runEnrichment() }
          } label: {
            Label("Продолжить обогащение (30 матчей)",
                  systemImage: "arrow.triangle.branch")
          }
          .disabled(busy)
        }
      } header: {
        Text("Обогащение котировок")
      } footer: {
        Text("Скачиваем /Odds/{id} для матчей, у которых ещё нет marketId 45 (углы Pinnacle) или 80 (карточки best). Успешные матчи сохраняются в HistoricalMarketCache — прогресс не теряется при перезапуске. Ночью BGTask добавляет ещё ~60 матчей при зарядке.")
      }
    }
  }

  @ViewBuilder
  private var modelComparisonSection: some View {
    let list = currentSnapshot?.decodedModelComparison() ?? []
    if !list.isEmpty {
      Section {
        ForEach(list) { c in
          VStack(alignment: .leading, spacing: 4) {
            HStack {
              Text(c.name).font(.subheadline.bold())
              Spacer()
              Text("n=\(c.matches)").font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
              miniBlock("Brier", String(format: "%.3f", c.brier))
              miniBlock("LogLoss", String(format: "%.3f", c.logLoss))
              miniBlock("P(H)", String(format: "%.2f", c.avgHomeP))
              miniBlock("P(D)", String(format: "%.2f", c.avgDrawP))
              miniBlock("P(A)", String(format: "%.2f", c.avgAwayP))
            }
          }
          .padding(.vertical, 2)
        }
      } header: {
        Text("Model comparison (E5)")
      } footer: {
        Text("DC — Dixon-Coles. BIV — Bivariate Poisson. NB — Negative Binomial. ENS — ансамбль. Brier и LogLoss ниже — модель точнее. P(H)/P(D)/P(A) — средние вероятности модели по выборке.")
      }
    }
  }

  // MARK: - W3b Walk-forward

  @ViewBuilder
  private var walkForwardSection: some View {
    if let snap = currentSnapshot,
       let train = snap.decodedTrainReport(),
       let val = snap.decodedValidationReport(),
       let holdout = snap.decodedHoldoutReport() {
      Section {
        wfBlock(title: "Train (60%)", color: .blue, delta: train)
        wfBlock(title: "Validation (20%)", color: .purple, delta: val)
        wfBlock(title: "Holdout (20%)", color: .orange, delta: holdout)
      } header: {
        Text("Walk-forward (W3b)")
      } footer: {
        Text("Train + Validation → в Self-Tuning (пороги, posterior, auto-exclude). Holdout не участвует в обучении — это независимая проверка. Если holdout сильно хуже train — модель переобучена.")
      }
    }
  }

  @ViewBuilder
  private func wfBlock(title: String, color: Color, delta: WalkForwardDelta) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(title).font(.subheadline.bold()).foregroundStyle(color)
        Spacer()
        Text("n=\(delta.bets)").font(.caption2).foregroundStyle(.secondary)
      }
      HStack(spacing: 14) {
        miniBlock("ROI", String(format: "%+.1f%%", delta.roi * 100))
          .foregroundStyle(delta.roi >= 0 ? .green : .red)
        miniBlock("Sharpe", String(format: "%.2f", delta.sharpe))
        miniBlock("ProfitF", String(format: "%.2f", delta.profitFactor))
        miniBlock("Brier", String(format: "%.3f", delta.brier))
        miniBlock("avgCLV", String(format: "%+.2f%%", delta.avgCLV * 100))
          .foregroundStyle(delta.avgCLV >= 0 ? .green : .red)
      }
      HStack(spacing: 14) {
        miniBlock("Матчей", "\(delta.matches)")
        miniBlock("W/L/P", "\(delta.wins)/\(delta.losses)/\(delta.pushes)")
        miniBlock("Hit", String(format: "%.0f%%", delta.hitRate * 100))
      }
    }
    .padding(.vertical, 2)
  }

  // MARK: - W3a OOS-валидация

  @ViewBuilder
  private var oosValidationSection: some View {
    let cfg = tuningConfig
    let enabled = cfg?.oosGateEnabled ?? false
    let window = cfg?.oosWindowDays ?? 90
    let minBets = cfg?.oosMinBets ?? 100
    let report = Metrics.oosFromJournal(journal, windowDays: window)
    let blocked = cfg.map { OOSBuilder.blockedMarkets(report: report, cfg: $0) } ?? []

    Section {
      LabeledContent("Флаг", value: enabled ? "включён" : "ВЫКЛ")
      LabeledContent("Окно", value: "\(window) дней")
      LabeledContent("Min n", value: "\(minBets)")
      if blocked.isEmpty {
        Text("Блокировок нет").font(.caption).foregroundStyle(.secondary)
      } else {
        Text("Заблокировано: \(blocked.sorted().joined(separator: ", "))")
          .font(.caption).foregroundStyle(.red)
      }
      if report.byMarket.isEmpty {
        Text("Пока нет закрытых записей в окне.").font(.caption2).foregroundStyle(.secondary)
      } else {
        ForEach(report.byMarket.keys.sorted(), id: \.self) { mk in
          if let r = report.byMarket[mk] {
            HStack {
              Text(mk).font(.subheadline)
              Spacer()
              VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%+.1f%% · n=%d", r.roi * 100, r.bets))
                  .font(.caption.monospacedDigit())
                  .foregroundStyle(r.roi >= 0 ? .green : .red)
                Text(String(format: "CLV %+.2f%% · Brier %.3f", r.avgCLV * 100, r.brier))
                  .font(.caption2.monospacedDigit())
                  .foregroundStyle(.secondary)
              }
            }
          }
        }
      }
    } header: {
      Text("OOS-валидация журнала (W3a)")
    } footer: {
      Text("Out-of-sample по реальному журналу (не бэктест). Если за окно n ≥ Min и ROI < порога — рынок автоматически блокируется в сканере (X NO BET). Пороги задаются в Self-Tuning.")
    }
  }

  @ViewBuilder
  private var liveMonitorSection: some View {
    Section {
      HStack {
        Label("Live-монитор", systemImage: "dot.radiowaves.left.and.right")
          .font(.headline)
        Spacer()
        Text(liveMonitor.isRunning ? "● идёт" : "○ стоп")
          .font(.caption)
          .foregroundStyle(liveMonitor.isRunning ? .green : .secondary)
      }
      LabeledContent("Матчей под наблюдением", value: "\(liveMonitor.snapshots.count)")
      if let t = liveMonitor.lastTick {
        LabeledContent("Последний цикл",
                       value: t.formatted(date: .omitted, time: .standard))
      }
      if let err = liveMonitor.lastError {
        Text(err).font(.caption).foregroundStyle(.orange)
      }

      if liveMonitor.isRunning {
        Button(role: .destructive) { liveMonitor.stop() } label: {
          Label("Остановить", systemImage: "stop.circle")
        }
      } else {
        Button { liveMonitor.start(settings: settings) } label: {
          Label("Запустить", systemImage: "play.circle")
        }
        .disabled(!settings.liveMonitorEnabled || signals.isEmpty)
      }
      if settings.preMatchHistoryEnabled {
        LabeledContent("Pre-match snapshots",
                       value: "\(liveMonitor.preMatchSnapshotsSaved)")
      }
    } header: {
      Text("Live (D1)")
    } footer: {
      Text("Live-монитор опрашивает котировки активных матчей. Каждый 5-й цикл — полные котировки (голы + углы + ЖК). Остальные — только голы. Это экономит лимит SStats.")
    }

    let regime = LiveMonitor.classifyRegime(
      snapshots: liveMonitor.snapshots,
      movements: liveMonitor.movements)
    Section {
      HStack {
        Text("Состояние").font(.subheadline)
        Spacer()
        Text(regime.regime.label).font(.subheadline.bold())
          .foregroundStyle(marketRegimeColor(regime.regime))
      }
      Text(regime.note).font(.caption).foregroundStyle(.secondary)
      HStack(spacing: 14) {
        miniBlock("Книг/рынок", String(format: "%.1f", regime.avgBooksPerMarket))
        miniBlock("Спред", String(format: "%.1f%%", regime.avgSpreadPct * 100))
        miniBlock("Sharp", "\(regime.sharpMovements)")
        miniBlock("Движений", "\(regime.totalMovements)")
      }
    } header: {
      Text("Регим рынка (W2b)")
    } footer: {
      Text("NORMAL — штатный режим. HIGH VOL — широкие спреды. LOW LIQ — мало книг. DISLOCATION — резкий переезд линий в 3+ книгах. Диагностика, не влияет на размер стейка.")
    }

    if !liveMonitor.movements.isEmpty {
      Section {
        let top = liveMonitor.movements.prefix(5)
        ForEach(Array(top)) { m in
          HStack(alignment: .top, spacing: 8) {
            Text(m.direction).font(.body.bold())
              .foregroundStyle(m.delta < 0 ? .green : (m.delta > 0 ? .red : .secondary))
            VStack(alignment: .leading, spacing: 2) {
              Text("\(m.market) · \(m.selection)\(m.line.map { " \($0)" } ?? "")")
                .font(.caption).lineLimit(1)
              Text(String(format: "%.2f → %.2f · книг: %d",
                          m.previousAvg, m.currentAvg, m.booksAgreeing))
                .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if m.isSharp {
              Text("SHARP").font(.caption2.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.purple).clipShape(Capsule())
            }
            Text(String(format: "%+.1f%%", m.delta * 100))
              .font(.caption.monospacedDigit())
              .foregroundStyle(m.delta < 0 ? .green : .red)
          }
        }
      } header: {
        Text("Движения линии (D2)")
      } footer: {
        Text("Если ≥ 3 книги двигают цену в одну сторону > 2% — линия помечается SHARP (вероятен инсайд или smart money).")
      }
    }
  }

  @ViewBuilder
  private var selfTuningLinkSection: some View {
    Section {
      NavigationLink { SelfTuningView() } label: {
        HStack {
          Image(systemName: "slider.horizontal.3").foregroundStyle(.blue)
          VStack(alignment: .leading, spacing: 2) {
            Text("Self-Tuning панель").font(.headline)
            if let cfg = tuningConfig {
              Text("Активных: \(activeCount(cfg)) из 9 · порогов: 24 · весов: 12")
                .font(.caption).foregroundStyle(.secondary)
            } else {
              Text("Открыть настройки автотюнинга")
                .font(.caption).foregroundStyle(.secondary)
            }
          }
          Spacer()
        }
      }
    } footer: {
      Text("Все ручные пороги и тумблеры. Каждое изменение логируется с возможностью отката.")
    }
  }

  private func activeCount(_ cfg: TuningConfig) -> Int {
    var n = 0
    if cfg.autoExcludeEnabled { n += 1 }
    if cfg.posteriorEnabled { n += 1 }
    if cfg.stopLossEnabled { n += 1 }
    if cfg.correlationEnabled { n += 1 }
    if cfg.playerImpactEnabled { n += 1 }
    if cfg.teamRatingEnabled { n += 1 }
    if cfg.cornersEnabled { n += 1 }
    if cfg.cardsEnabled { n += 1 }
    if cfg.oosGateEnabled { n += 1 }
    return n
  }

  @ViewBuilder
  private var leagueMarketHeatmapSection: some View {
    let stats = currentSnapshot?.decodedLeagueMarketStats() ?? [:]
    if !stats.isEmpty {
      let leagues = LeaguePool.pool.map { $0.name }
      let markets = ["GOALS", "CARDS", "CORNERS"]
      Section {
        ScrollView(.horizontal, showsIndicators: false) {
          Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            GridRow {
              Text("").frame(width: 100, alignment: .leading)
              ForEach(markets, id: \.self) { mk in
                Text(mk).font(.caption2.bold()).frame(width: 66)
              }
            }
            ForEach(leagues, id: \.self) { lg in
              GridRow {
                Text(lg).font(.caption2).frame(width: 100, alignment: .leading).lineLimit(1)
                ForEach(markets, id: \.self) { mk in
                  let key = "\(lg)|\(mk)"
                  heatCell(stats[key])
                }
              }
            }
          }
          .padding(.vertical, 4)
        }
      } header: {
        Text("Лиги × Рынки (ROI)")
      } footer: {
        Text("Разбивка ROI по каждой лиге и рынку отдельно. Зелёный — плюс. Красный — минус. n = число ставок в ячейке.")
      }
    }
  }

  @ViewBuilder
  private func heatCell(_ s: StoredSegmentStats?) -> some View {
    if let s, s.bets > 0 {
      VStack(spacing: 1) {
        Text(String(format: "%+.0f%%", s.roi * 100))
          .font(.caption2.monospacedDigit().bold())
        Text("n=\(s.bets)").font(.caption2).opacity(0.7)
      }
      .frame(width: 66, height: 34)
      .background(heatColor(s.roi).opacity(0.28))
      .clipShape(RoundedRectangle(cornerRadius: 6))
    } else {
      Text("—").font(.caption2).foregroundStyle(.secondary)
        .frame(width: 66, height: 34)
        .background(Color.gray.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
  }

  private func heatColor(_ roi: Double) -> Color {
    if roi >= 0.10 { return .green }
    if roi >= 0.02 { return Color.green.opacity(0.75) }
    if roi > -0.02 { return .yellow }
    if roi > -0.10 { return .orange }
    return .red
  }

  @ViewBuilder
  private var volatilitySection: some View {
    let cap = tuningConfig?.stopLossCapStreak ?? VolatilityStop.defaultCapThreshold
    let pause = tuningConfig?.stopLossPauseStreak ?? VolatilityStop.defaultPauseThreshold
    let enabled = tuningConfig?.stopLossEnabled ?? true
    let ev = VolatilityStop.evaluate(journal, capThreshold: cap, pauseThreshold: pause)
    Section {
      LabeledContent("Флаг", value: enabled ? "включён" : "ВЫКЛ")
      LabeledContent("Текущая серия", value: "\(ev.streak)")
      LabeledContent("Состояние", value: enabled ? ev.state.label : "OFF")
      switch (enabled, ev.state) {
      case (false, _):
        Text("Stop-loss отключён в Self-Tuning.")
          .font(.caption).foregroundStyle(.secondary)
      case (true, .cap(let v)):
        Text("После \(cap) проигрышей подряд — стейк ограничен \(Int(v * 100))%.")
          .font(.caption).foregroundStyle(.orange)
      case (true, .pause):
        Text("После \(pause) проигрышей подряд — новые ставки не создаются.")
          .font(.caption).foregroundStyle(.red)
      default:
        Text("Работаем в штатном режиме.")
          .font(.caption).foregroundStyle(.secondary)
      }
    } header: {
      Text("Volatility stop (B5)")
    } footer: {
      Text("Автоматическая защита от длинных серий проигрышей. NORMAL — штатно. CAP — стейк урезан до 5%. PAUSE — новые ставки не создаются.")
    }
  }

  @ViewBuilder
  private var correlationSection: some View {
    let m = correlationMatrix
    let enabled = tuningConfig?.correlationEnabled ?? true
    Section {
      LabeledContent("Флаг", value: enabled ? "включён" : "ВЫКЛ")
      if m.totalPairs == 0 {
        Text("Нужно ≥ 20 пар закрытых записей в одном дне для эмпирики.")
          .font(.caption).foregroundStyle(.secondary)
      } else {
        LabeledContent("Пар в журнале", value: "\(m.totalPairs)")
        LabeledContent("Market-пар (n≥20)", value: "\(m.marketPairsN.count)")
        LabeledContent("League-пар (n≥20)", value: "\(m.leaguePairsN.count)")
        if !m.marketPairs.isEmpty {
          Text("Сильнейшие market-связи:").font(.caption2).foregroundStyle(.secondary)
          let topM = m.marketPairs
            .filter { abs($0.value) > 0.001 }
            .sorted { abs($0.value) > abs($1.value) }
            .prefix(5)
          ForEach(Array(topM), id: \.key) { (k, v) in
            HStack {
              Text(k).font(.caption.monospacedDigit())
              Spacer()
              Text(String(format: "%+.2f", v))
                .font(.caption.monospacedDigit())
                .foregroundStyle(v > 0 ? .green : .red)
              if let n = m.marketPairsN[k] {
                Text("n=\(n)").font(.caption2).foregroundStyle(.secondary)
                  .frame(width: 52, alignment: .trailing)
              }
            }
          }
        }
      }
    } header: {
      Text("Correlation matrix (B4)")
    } footer: {
      Text("φ-коэффициенты между рынками и лигами из журнала. Если две ставки в портфеле сильно коррелируют (≥ 0.65), вторая отсекается. Fallback — структурные значения.")
    }
  }

  @ViewBuilder
  private var playerImpactSection: some View {
    let enabled = tuningConfig?.playerImpactEnabled ?? true
    Section {
      LabeledContent("Флаг", value: enabled ? "включён" : "ВЫКЛ")
    } header: {
      Text("Player impact (B6)")
    } footer: {
      Text("Коррекция λ, если в gameInfo есть составы (lineups) и у команды ≥ 6 игроков в истории. Отсутствие 3–4 топ-8 → λ × 0.92…0.95. Отсутствие 5+ → λ × 0.88.")
    }
  }

  @ViewBuilder
  private var teamRatingsSection: some View {
    let top = Array(teamRatings.prefix(20))
    let enabled = tuningConfig?.teamRatingEnabled ?? true
    if !top.isEmpty || !enabled {
      Section {
        LabeledContent("Флаг", value: enabled ? "включён" : "ВЫКЛ")
        ForEach(top) { r in
          HStack {
            VStack(alignment: .leading, spacing: 2) {
              Text(r.name.isEmpty ? r.teamID : r.name).font(.subheadline)
              Text("n=\(r.matches)").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text(String(format: "%.0f", r.rating))
              .font(.subheadline.monospacedDigit())
            if r.lastDelta != 0 {
              Text(String(format: "%+.0f", r.lastDelta))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(r.lastDelta > 0 ? .green : .red)
                .frame(width: 44, alignment: .trailing)
            }
          }
        }
      } header: {
        Text("Team ratings (B3)")
      } footer: {
        Text("Elo, старт 1500, HFA 60, K=32→20. Применяются после ≥ 3 матчей. Влияют на λ через glickoAdjust (не более ±12%).")
      }
    }
  }

  @ViewBuilder
  private func autoExcludeSection(_ snap: BacktestSnapshot) -> some View {
    let cfg = tuningConfig
    let minROI = cfg?.autoExcludeMinROI ?? AutoExclude.defaultMinROI
    let minBets = cfg?.autoExcludeMinBets ?? AutoExclude.defaultMinBets
    let enabled = cfg?.autoExcludeEnabled ?? true
    let rules = AutoExclude.rules(from: snap, minROI: minROI, minBets: minBets)
    let excluded = rules.filter { $0.excluded }
    Section {
      LabeledContent("Флаг", value: enabled ? "включён" : "ВЫКЛ")
      LabeledContent("Порог",
                     value: String(format: "ROI < %.1f%%, n ≥ %d",
                                   minROI * 100, minBets))
      if rules.isEmpty {
        Text("Нет данных по лига+рынок (соберите базу)")
          .font(.caption).foregroundStyle(.secondary)
      } else if excluded.isEmpty {
        Text("Пока не исключено ни одной комбинации")
          .font(.caption).foregroundStyle(.secondary)
      } else {
        Text("\(excluded.count) комбинаций будут отфильтрованы в сканере")
          .font(.caption2).foregroundStyle(.secondary)
        ForEach(excluded) { r in
          HStack {
            VStack(alignment: .leading, spacing: 2) {
              Text("\(r.league) · \(r.market)").font(.subheadline)
              Text("n=\(r.bets)").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text(String(format: "%+.1f%%", r.roi * 100))
              .font(.subheadline.monospacedDigit()).foregroundStyle(.red)
          }
        }
      }
    } header: {
      Text("Auto-Exclude")
    } footer: {
      Text("Комбинации лига+рынок с плохим ROI в бэктесте автоматически отсеиваются в сканере.")
    }
  }

  @ViewBuilder
  private func posteriorSection(_ snap: BacktestSnapshot) -> some View {
    let cfg = tuningConfig
    let enabled = cfg?.posteriorEnabled ?? true
    let w = cfg?.posteriorWeight ?? QuantEngine.defaultPosteriorWeight
    let buckets = snap.decodedPosteriorBuckets()
    let nonEmpty = buckets.filter { $0.n > 0 }
    let usable = nonEmpty.filter { $0.n >= 20 }.count
    Section {
      LabeledContent("Флаг", value: enabled ? "включён" : "ВЫКЛ")
      LabeledContent("Вес w", value: String(format: "%.2f", w))
      if nonEmpty.isEmpty {
        Text("Нет данных (соберите базу)")
          .font(.caption).foregroundStyle(.secondary)
      } else {
        Text("Применяются бакеты с n ≥ 20. Сейчас: \(usable) из \(nonEmpty.count)")
          .font(.caption2).foregroundStyle(.secondary)
        ForEach(nonEmpty) { b in
          HStack {
            Text(String(format: "P %.0f–%.0f%%",
                        b.probabilityLow * 100, b.probabilityHigh * 100))
              .font(.caption.monospacedDigit())
            Spacer()
            Text(String(format: "act %.0f%%", b.factHitRate * 100))
              .font(.caption.monospacedDigit())
              .foregroundStyle(b.n >= 20 ? .primary : .secondary)
            Text("n=\(b.n)").font(.caption2).foregroundStyle(.secondary)
              .frame(width: 52, alignment: .trailing)
          }
        }
      }
    } header: {
      Text("Posterior buckets (B2)")
    } footer: {
      Text("Байесовская коррекция вероятности: p_adj = (1-w)·p + w·p_post. p_post — исторически фактический hit rate для того же бакета вероятности. Применяется только для бакетов с n ≥ 20.")
    }
  }

  @ViewBuilder
  private func leagueSection(_ snap: BacktestSnapshot) -> some View {
    let stats = snap.decodedLeagueStats()
    if !stats.isEmpty {
      Section("Лиги (ROI)") {
        ForEach(stats.keys.sorted(), id: \.self) { lg in
          if let s = stats[lg] { segmentRow(name: lg, s: s) }
        }
      }
    }
  }

  @ViewBuilder
  private func marketSection(_ snap: BacktestSnapshot) -> some View {
    let stats = snap.decodedMarketStats()
    if !stats.isEmpty {
      Section("Рынки (ROI)") {
        ForEach(stats.keys.sorted(), id: \.self) { mk in
          if let s = stats[mk] { segmentRow(name: mk, s: s) }
        }
      }
    }
  }

  @ViewBuilder
  private func evSection(_ snap: BacktestSnapshot) -> some View {
    let stats = snap.decodedEVBuckets()
    if !stats.isEmpty {
      Section("EV buckets") {
        ForEach(stats.keys.sorted(), id: \.self) { k in
          if let s = stats[k] { segmentRow(name: k, s: s) }
        }
      }
    }
  }

  @ViewBuilder
  private func oddsSection(_ snap: BacktestSnapshot) -> some View {
    let stats = snap.decodedOddsBuckets()
    if !stats.isEmpty {
      Section("Odds bands") {
        ForEach(stats.keys.sorted(), id: \.self) { k in
          if let s = stats[k] { segmentRow(name: k, s: s) }
        }
      }
    }
  }

  @ViewBuilder
  private func classSection(_ snap: BacktestSnapshot) -> some View {
    let stats = snap.decodedClassification()
    if !stats.isEmpty {
      Section("Классы") {
        ForEach(stats.keys.sorted(), id: \.self) { k in
          if let s = stats[k] { segmentRow(name: k, s: s) }
        }
      }
    }
  }

  private func segmentRow(name: String, s: StoredSegmentStats) -> some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text(name).font(.subheadline)
        Text("n=\(s.bets) · hit \(String(format: "%.0f%%", s.hitRate * 100))")
          .font(.caption2).foregroundStyle(.secondary)
      }
      Spacer()
      Text(String(format: "%+.1f%%", s.roi * 100))
        .font(.subheadline.monospacedDigit())
        .foregroundStyle(s.roi >= 0 ? .green : .red)
    }
  }

  private static func shortDate(_ d: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: d)
  }

  private func runFullBuild() async {
    guard !busy else { return }
    busy = true
    defer { busy = false }
    btProgressText = "Запуск…"
    let ok = await BacktestService.shared.buildFullBase { progress, msg in
      btProgressText = String(format: "%.0f%% · %@", progress * 100, msg)
    }
    btProgressText = ok ? "Готово" : "Ошибка/прервано"
    try? context.save()
  }

  private func runIncremental() async {
    guard !busy else { return }
    busy = true
    defer { busy = false }
    btProgressText = "Докачка…"
    let ok = await BacktestService.shared.updateIncremental()
    btProgressText = ok ? "Докачка завершена" : "Докачка не выполнена"
    try? context.save()
  }

  private func runEnrichment() async {
    guard !busy else { return }
    busy = true
    defer { busy = false }
    btProgressText = "Обогащение…"
    await BacktestService.shared.continueEnrichmentInBackground(chunkSize: 30) { done, total, msg in
      btProgressText = String(format: "%d/%d · %@", done, total, msg)
    }
    btProgressText = "Обогащение завершено (порция)"
    try? context.save()
  }

  // MARK: - Контроль

  private var diagnosticsView: some View {
    List {
      Section("API") {
        LabeledContent("Base URL", value: settings.baseURL)
        LabeledContent("API key", value: settings.apiKey.isEmpty
          ? "не задан" : "\(settings.apiKey.count) симв.")
        LabeledContent("Engine", value: settings.engineVersion)
      }
      Section {
        Button { Task { await runChecks() } } label: {
          Label("Запустить проверки", systemImage: "checkmark.shield")
        }
        .disabled(busy)
        LabeledContent("API reachable", value: apiReachable)
        LabeledContent("API key", value: apiKeyState)
        LabeledContent("Settle", value: lastSettleStatus)
        if let lr = lastRefresh {
          LabeledContent("Last refresh",
                         value: lr.formatted(date: .omitted, time: .shortened))
        }
      } header: {
        Text("Проверки")
      } footer: {
        Text("Проверяет доступность SStats, валидность ключа и запускает settlement открытых записей.")
      }
      Section {
        Button { selfTestResults = QuantMathSelfTest.runAll() } label: {
          Label("Запустить unit-тесты", systemImage: "checkmark.seal")
        }
        if !selfTestResults.isEmpty {
          let passed = selfTestResults.filter { $0.pass }.count
          let total = selfTestResults.count
          HStack {
            Text("Пройдено")
            Spacer()
            Text("\(passed)/\(total)")
              .font(.subheadline.bold())
              .foregroundStyle(passed == total ? .green : .orange)
          }
          ForEach(selfTestResults) { r in
            HStack(alignment: .top, spacing: 8) {
              Image(systemName: r.pass ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .foregroundStyle(r.pass ? .green : .red)
              VStack(alignment: .leading, spacing: 2) {
                Text(r.name).font(.caption)
                Text(r.note).font(.caption2).foregroundStyle(.secondary)
              }
            }
          }
        } else {
          Text("Нажмите кнопку — 15 проверок QuantMath.")
            .font(.caption2).foregroundStyle(.secondary)
        }
      } header: {
        Text("Self-tests (E4)")
      } footer: {
        Text("15 юнит-тестов QuantMath: медиана, EV, Kelly, DC/BIV, split линий, β-shrink, NB-PMF. Все должны быть зелёными. Известная косметика: median чётная использует верхнюю медиану.")
      }
      Section("Sample / Consensus") {
        let m = Metrics.compute(journal)
        LabeledContent("Closed entries", value: "\(m.closedEntries)")
        LabeledContent("Calibration err",
                       value: String(format: "%.3f", Metrics.calibrationError(m)))
        LabeledContent("Avg CLV", value: String(format: "%+.2f%%", m.avgCLV * 100))
        LabeledContent("Brier", value: String(format: "%.3f", m.brier))
      }
      Section("CLV-first (W2b)") {
        let rep = Metrics.clvReport(journal)
        LabeledContent("Вердикт", value: rep.verdict)
        LabeledContent("Записей с CLV", value: "\(rep.totalWithCLV)")
        LabeledContent("+CLV доля",
                       value: String(format: "%.0f%%", rep.positiveRate * 100))
        LabeledContent("avg CLV", value: String(format: "%+.2f%%", rep.avgCLV * 100))
        LabeledContent("median CLV",
                       value: String(format: "%+.2f%%", rep.medianCLV * 100))
      }
      Section {
        LabeledContent("Статус", value: settings.preMatchHistoryEnabled ? "вкл" : "выкл")
        LabeledContent("Окно", value: "\(settings.preMatchCaptureWindowMin) мин")
        LabeledContent("Снимков за сессию",
                       value: "\(liveMonitor.preMatchSnapshotsSaved)")
        let total = LineSnapshotService.totalCount(in: context)
        LabeledContent("Всего в БД", value: "\(total)")
      } header: {
        Text("Pre-match line history (W2b)")
      } footer: {
        Text("Снимки котировок за T-60/30/15/5 минут до старта. Позволяют измерить реальное движение линии и отличить настоящий edge от one-off аномалии цены.")
      }
      Section {
        let snap = currentSnapshot
        let train = snap?.decodedTrainReport()
        let val = snap?.decodedValidationReport()
        let holdout = snap?.decodedHoldoutReport()
        LabeledContent("Режим", value: snap?.walkForwardMode ?? "off")
        if let t = train {
          LabeledContent("Train ROI", value: String(format: "%+.2f%%", t.roi * 100))
          LabeledContent("Train n", value: "\(t.bets)")
        }
        if let v = val {
          LabeledContent("Val ROI", value: String(format: "%+.2f%%", v.roi * 100))
          LabeledContent("Val n", value: "\(v.bets)")
        }
        if let h = holdout {
          LabeledContent("Holdout ROI", value: String(format: "%+.2f%%", h.roi * 100))
          LabeledContent("Holdout n", value: "\(h.bets)")
        }
      } header: {
        Text("Walk-forward (W3b)")
      } footer: {
        Text("Self-Tuning обучается на Train+Validation. Holdout — независимая проверка. Сильное расхождение → модель переобучена.")
      }
      Section {
        let cfg = tuningConfig
        let report = Metrics.oosFromJournal(journal, windowDays: cfg?.oosWindowDays ?? 90)
        LabeledContent("Флаг", value: (cfg?.oosGateEnabled ?? false) ? "вкл" : "выкл")
        LabeledContent("Окно", value: "\(cfg?.oosWindowDays ?? 90) дней")
        LabeledContent("Записей в окне", value: "\(report.totalEntries)")
        let blocked = cfg.map { OOSBuilder.blockedMarkets(report: report, cfg: $0) } ?? []
        LabeledContent("Заблокировано", value: blocked.isEmpty ? "—" : blocked.sorted().joined(separator: ", "))
      } header: {
        Text("OOS-валидация (W3a)")
      } footer: {
        Text("OOS по реальному журналу. Если рынок системно убыточен за окно — блокируется в сканере до восстановления.")
      }
      Section {
        let snap = currentSnapshot
        let allSample = sampleBreakdown(signals)
        LabeledContent("FULL", value: "\(allSample.full)")
        LabeledContent("GOOD", value: "\(allSample.good)")
        LabeledContent("USABLE", value: "\(allSample.usable)")
        LabeledContent("INS", value: "\(allSample.ins)")
        LabeledContent("С SHARP", value: "\(signals.filter { $0.sharpMoney == true }.count)")
        LabeledContent("С posterior", value: "\(signals.filter { $0.posteriorWeight != nil }.count)")
        if snap != nil {
          let cached = snap?.historicalCacheCount ?? 0
          LabeledContent("Historical cache", value: "\(cached) матчей")
        }
      } header: {
        Text("Data Health (W3c)")
      } footer: {
        Text("Сводка качества входных данных по последнему скану. FULL/GOOD/USABLE/INS — размер рыночной выборки. Чем больше INS — тем менее надёжны сигналы.")
      }
      Section("Self-Tuning") {
        if let cfg = tuningConfig {
          LabeledContent("Активных механизмов", value: "\(activeCount(cfg)) из 9")
          LabeledContent("posteriorWeight",
                         value: String(format: "%.2f", cfg.posteriorWeight))
          LabeledContent("autoExcludeMinROI",
                         value: String(format: "%.1f%%", cfg.autoExcludeMinROI * 100))
          LabeledContent("autoExcludeMinBets", value: "\(cfg.autoExcludeMinBets)")
          LabeledContent("stopLossCap/Pause",
                         value: "\(cfg.stopLossCapStreak)/\(cfg.stopLossPauseStreak)")
          LabeledContent("CORNERS",
                         value: String(format: "EV ≥ %.1f%%, QCS ≥ %.0f, MSS ≥ %.0f, stake ≤ %.1f%%",
                                       cfg.cornersMinEV * 100, cfg.cornersMinQCS,
                                       cfg.cornersMinMSS, cfg.cornersMaxStake * 100))
          LabeledContent("CARDS",
                         value: String(format: "EV ≥ %.1f%%, QCS ≥ %.0f, MSS ≥ %.0f, stake ≤ %.1f%%",
                                       cfg.cardsMinEV * 100, cfg.cardsMinQCS,
                                       cfg.cardsMinMSS, cfg.cardsMaxStake * 100))
          LabeledContent("OOS gate",
                         value: cfg.oosGateEnabled ? "вкл · n≥\(cfg.oosMinBets)" : "выкл")
          LabeledContent("Событий в логе", value: "\(tuningEvents.count)")
        } else {
          Text("Конфиг не создан").font(.caption).foregroundStyle(.secondary)
        }
      }
      Section("Отображение") {
        LabeledContent("Odds format", value: settings.oddsFormat.label)
        LabeledContent("Тема", value: settings.colorScheme.label)
      }
      Section("Банк") {
        LabeledContent("Ставки в деньгах",
                       value: settings.useMoneyStakes ? "да" : "нет")
        LabeledContent("Размер банка",
                       value: String(format: "%.0f", settings.bankroll))
      }
      Section {
        LabeledContent("Статус", value: liveMonitor.isRunning ? "идёт" : "стоп")
        LabeledContent("Матчей", value: "\(liveMonitor.snapshots.count)")
        LabeledContent("Движений", value: "\(liveMonitor.movements.count)")
        let sharpCount = liveMonitor.movements.filter { $0.isSharp }.count
        LabeledContent("Sharp", value: "\(sharpCount)")
        if let t = liveMonitor.lastTick {
          LabeledContent("Last tick",
                         value: t.formatted(date: .omitted, time: .standard))
        }
        let regime = LiveMonitor.classifyRegime(
          snapshots: liveMonitor.snapshots,
          movements: liveMonitor.movements)
        LabeledContent("Регим рынка", value: regime.regime.label)
      } header: {
        Text("Live-монитор (D1)")
      }
      Section("Team ratings (B3)") {
        LabeledContent("Всего команд", value: "\(teamRatings.count)")
        let usable = teamRatings.filter { $0.matches >= TeamRatingService.minMatchesForUse }.count
        LabeledContent("С ≥ 3 матчами", value: "\(usable)")
      }
      Section("Correlation (B4)") {
        let m = correlationMatrix
        LabeledContent("Пар в журнале", value: "\(m.totalPairs)")
        LabeledContent("Market-пар (n≥20)", value: "\(m.marketPairsN.count)")
        LabeledContent("League-пар (n≥20)", value: "\(m.leaguePairsN.count)")
      }
      Section {
        if let snap = currentSnapshot {
          LabeledContent("Status", value: snap.buildStatus)
          LabeledContent("Progress",
                         value: String(format: "%.1f%%", snap.buildProgress * 100))
          LabeledContent("Matches", value: "\(snap.totalMatches)")
          LabeledContent("Bets", value: "\(snap.totalBets)")
          if snap.enrichmentTotal > 0 {
            LabeledContent("Enrichment",
                           value: "\(snap.enrichmentProgress)/\(snap.enrichmentTotal)")
          }
          if snap.historicalCacheCount > 0 {
            LabeledContent("Historical cache",
                           value: "\(snap.historicalCacheCount) матчей")
          }
          if snap.totalBets > 0 {
            LabeledContent("avgROI",
                           value: String(format: "%+.2f%%", snap.avgROI * 100))
            LabeledContent("Sharpe", value: String(format: "%.2f", snap.sharpe))
          }
          let rules = AutoExclude.rules(from: snap)
          let excludedCount = rules.filter { $0.excluded }.count
          LabeledContent("Auto-Exclude (активных)", value: "\(excludedCount)")
          let buckets = snap.decodedPosteriorBuckets()
          let usableBuckets = buckets.filter { $0.n >= 20 }.count
          LabeledContent("Posterior (n≥20)", value: "\(usableBuckets)")
          let comps = snap.decodedModelComparison()
          if !comps.isEmpty {
            LabeledContent("Model comparison (E5)", value: "\(comps.count) строк")
          }
          if let err = snap.lastError {
            Text(err).font(.caption).foregroundStyle(.red)
          }
        } else {
          Text("Снапшот ещё не создан").font(.caption).foregroundStyle(.secondary)
        }
      } header: {
        Text("Backtest snapshot")
      }
      Section("Пул лиг") {
        ForEach(LeaguePool.pool, id: \.id) { lg in
          Text("\(lg.id) · \(lg.name)").font(.subheadline)
        }
      }
      Section {
        ForEach(LeagueBaselines.all) { b in
          VStack(alignment: .leading, spacing: 4) {
            Text(b.name).font(.subheadline).bold()
            HStack(spacing: 12) {
              miniBlock("λH", String(format: "%.2f", b.homeLambda))
              miniBlock("λA", String(format: "%.2f", b.awayLambda))
              miniBlock("Adv", String(format: "%.2f", b.homeAdvantage))
              miniBlock("ρ", String(format: "%+.2f", b.rho))
            }
          }
          .padding(.vertical, 2)
        }
      } header: {
        Text("League baselines (prior)")
      } footer: {
        Text("Структурные приоры λ для каждой лиги. sampleSize=0 → это prior, а не измеренные данные. Используются как fallback, когда истории мало.")
      }
      Section {
        Text("NO DATA → NO NUMBER → NO EDGE → NO BET").font(.subheadline).bold()
        Text("Quarter Kelly · max 2% · S BET до 2.5%")
          .font(.caption).foregroundStyle(.secondary)
        Text("Portfolio cap 10% bankroll в день")
          .font(.caption).foregroundStyle(.secondary)
      } header: {
        Text("Принципы")
      }
      if !diagnostics.isEmpty {
        Section("Последний запуск") {
          ForEach(diagnostics, id: \.self) { d in
            Text(d).font(.caption.monospaced()).textSelection(.enabled)
          }
        }
      }
      Section { Color.clear.frame(height: 56).listRowBackground(Color.clear) }
    }
    .listStyle(.insetGrouped)
    .navigationTitle("Контроль")
    .navigationBarTitleDisplayMode(.large)
  }

  private func sampleBreakdown(_ sigs: [BetSignal]) -> (full: Int, good: Int, usable: Int, ins: Int) {
    var f = 0, g = 0, u = 0, i = 0
    for s in sigs {
      switch s.sampleClass {
      case "FULL": f += 1
      case "GOOD": g += 1
      case "USABLE": u += 1
      default: i += 1
      }
    }
    return (f, g, u, i)
  }

  private func runChecks() async {
    guard !busy else { return }
    busy = true
    defer { busy = false }
    let key = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    apiKeyState = key.isEmpty ? "пусто" : "задан (\(key.count) симв.)"
    guard !key.isEmpty else {
      apiReachable = "пропущено (нет ключа)"
      return
    }
    let client = SStatsClient(settings: settings)
    do {
      _ = try await client.listToday()
      apiReachable = "OK"
    } catch {
      apiReachable = "FAIL: \(error.localizedDescription)"
    }
    let result = await JournalService.settleOpenEntries(
      context: context, client: client)
    lastSettleStatus = "закрыто \(result.closed), ошибок \(result.failed)"
  }

  // MARK: - Настройки

  private var settingsView: some View {
    SwiftUI.Form {
      Section {
        SecureField("API key", text: $settings.apiKey)
          .textInputAutocapitalization(.never).autocorrectionDisabled()
      } header: {
        Text("SStats API")
      } footer: {
        Text("Ключ хранится в Keychain и не попадает в репозиторий.")
      }
      Section("Отображение") {
        Picker("Формат коэффициентов", selection: $settings.oddsFormatRaw) {
          ForEach(OddsFormat.allCases) { f in Text(f.label).tag(f.rawValue) }
        }
        Text(settings.oddsFormat.hint).font(.caption2).foregroundStyle(.secondary)
        Picker("Тема", selection: $settings.colorSchemeRaw) {
          ForEach(AppColorScheme.allCases) { s in Text(s.label).tag(s.rawValue) }
        }
      }
      Section {
        Toggle("Ставки в деньгах", isOn: $settings.useMoneyStakes)
        if settings.useMoneyStakes {
          HStack {
            Text("Размер банка")
            Spacer()
            TextField("0", value: $settings.bankroll, format: .number)
              .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
              .frame(width: 140).monospacedDigit()
          }
        }
      } header: {
        Text("Банк")
      } footer: {
        Text("Включённый режим показывает стейк в деньгах: 2% банка = 0.02 × размер банка.")
      }
      Section {
        Toggle("Следить за линией", isOn: $settings.liveMonitorEnabled)
        if settings.liveMonitorEnabled {
          Stepper("Интервал: \(settings.liveMonitorIntervalSec) сек",
                  value: $settings.liveMonitorIntervalSec, in: 30...300, step: 30)
        }
      } header: {
        Text("Live-монитор")
      } footer: {
        Text("Каждый 5-й цикл — полные котировки (углы+ЖК). Остальные — только голы.")
      }
      Section {
        Toggle("Сохранять движение линии до старта",
               isOn: $settings.preMatchHistoryEnabled)
        if settings.preMatchHistoryEnabled {
          Stepper("Окно снимков: \(settings.preMatchCaptureWindowMin) мин",
                  value: $settings.preMatchCaptureWindowMin,
                  in: 15...180, step: 15)
        }
      } header: {
        Text("Pre-match line history (W2b)")
      } footer: {
        Text("Снимки пишутся в 4 контрольных точках (T-60/30/15/5) пока активен Live-монитор.")
      }
      Section {
        Toggle("Фоновое обновление", isOn: $settings.autoRefresh)
        Stepper("Интервал: \(settings.refreshMinutes) мин",
                value: $settings.refreshMinutes, in: 15...120, step: 15)
      } header: {
        Text("Автообновление")
      } footer: {
        Text("iOS сама решает, когда запускать фон (обычно ≥ 30 мин).")
      }
      Section("Параметры модели") {
        Stepper("История: \(settings.historyMatches) матчей",
                value: $settings.historyMatches, in: 6...20)
        Stepper("Матчей в сканере: \(settings.scanMatches)",
                value: $settings.scanMatches, in: 5...30)
      }
      Section("Уведомления") {
        Toggle("Уведомлять при S/A BET", isOn: $settings.notifyBets)
        Button { NotificationService.resetDedupe() } label: {
          Label("Сбросить дубликаты", systemImage: "arrow.counterclockwise")
        }
      }
      Section {
        Text("NO DATA → NO NUMBER → NO EDGE → NO BET").bold()
      } header: {
        Text("Принцип")
      }
      Section { Color.clear.frame(height: 56).listRowBackground(Color.clear) }
    }
    .navigationTitle("Настройки")
    .navigationBarTitleDisplayMode(.large)
  }

  private func refresh() async {
    guard !busy else { return }
    busy = true
    defer { busy = false }
    diagnostics = []
    status = "Сканирую…"

    let summary = await ScanCoordinator.shared.scan(
      settings: settings, selectedLeague: selectedLeague)

    signals = summary.signals
    lastRefresh = summary.finishedAt

    liveMonitor.clearObserved()
    for s in signals {
      liveMonitor.observe(
        gameID: s.gameID,
        numericID: Int(s.gameID),
        startTime: s.startTime,
        league: s.league,
        home: s.home,
        away: s.away)
    }
    if settings.liveMonitorEnabled && !signals.isEmpty {
      liveMonitor.start(settings: settings)
    }

    if summary.success {
      status = "Обновлено · \(signals.count) сигналов"
    } else {
      status = summary.notes.first ?? "Ошибка"
    }
    for n in summary.notes { diagnostics.append(n) }
    diagnostics.append("scanned=\(summary.scannedMatches)")
    diagnostics.append("corrPairs=\(summary.correlationPairs)")
    diagnostics.append("lineups=\(summary.lineupsFound)")
    diagnostics.append("h2h=\(summary.h2hFetched)")
    if !summary.oosBlocked.isEmpty {
      diagnostics.append("oosBlocked=\(summary.oosBlocked.joined(separator: ","))")
    }
  }

  private func settleJournal() async {
    guard !busy else { return }
    busy = true
    defer { busy = false }
    guard !settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { lastSettleStatus = "API key не задан"; return }
    let client = SStatsClient(settings: settings)
    lastSettleStatus = "Обновляю…"
    let result = await JournalService.settleOpenEntries(
      context: context, client: client)
    lastSettleStatus = "Закрыто \(result.closed), ошибок \(result.failed)"
  }
}
