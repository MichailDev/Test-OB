import Foundation
import SwiftUI
import SwiftData
import Charts

struct SelfTuningView: View {
  @Environment(\.modelContext) private var context
  @Query private var configs: [TuningConfig]
  @Query(sort: \TuningEvent.createdAt, order: .reverse) private var events: [TuningEvent]
  @Query(sort: \JournalEntry.createdAt, order: .reverse) private var journal: [JournalEntry]
  @Query private var snapshots: [BacktestSnapshot]

  @State private var rollbackMessage: String? = nil

  private var config: TuningConfig? { configs.first }
  private var snapshot: BacktestSnapshot? { snapshots.first }

  private var correlationMatrix: CorrelationMatrix {
    CorrelationBuilder.build(from: journal)
  }

  var body: some View {
    List {
      if let cfg = config {
        decisionsSection(cfg)
        marketsSection(cfg)
        thresholdsSection(cfg)
        marketThresholdsSection(cfg)
        oosThresholdsSection(cfg)
        cornersWeightsSection(cfg)
        cardsWeightsSection(cfg)
        eventsSection
        resetSection
      } else {
        Section {
          Text("Конфиг не создан. Перезапустите приложение.")
            .font(.caption).foregroundStyle(.secondary)
        }
      }
      Section { Color.clear.frame(height: 56).listRowBackground(Color.clear) }
    }
    .listStyle(.insetGrouped)
    .navigationTitle("Self-Tuning")
    .navigationBarTitleDisplayMode(.large)
    .onAppear {
      if configs.isEmpty { _ = TuningService.fetchOrCreate(in: context) }
    }
  }

  @ViewBuilder
  private func decisionsSection(_ cfg: TuningConfig) -> some View {
    let decisions = TuningService.decisions(config: cfg, snapshot: snapshot,
                                            journal: journal, corr: correlationMatrix)
    Section {
      ForEach(decisions) { d in
        VStack(alignment: .leading, spacing: 6) {
          HStack {
            Text(d.title).font(.subheadline.bold())
            Spacer()
            Toggle("", isOn: Binding(
              get: { d.enabled },
              set: { newValue in setFlag(d.flagKey, value: newValue, in: cfg) }
            ))
            .labelsHidden()
          }
          Text(d.summary).font(.caption).foregroundStyle(.secondary)
          Text(d.detail).font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
      }
    } header: {
      Text("Активные механизмы")
    } footer: {
      Text("Отключённый механизм не применяется при следующем скане.")
    }
  }

  @ViewBuilder
  private func marketsSection(_ cfg: TuningConfig) -> some View {
    Section {
      Toggle(isOn: Binding(
        get: { cfg.cornersEnabled },
        set: { v in setFlag("cornersEnabled", value: v, in: cfg) }
      )) {
        VStack(alignment: .leading, spacing: 2) {
          Text("Рынок CORNERS").font(.subheadline)
          Text("Углы. Edge vs Pinnacle (sharp).")
            .font(.caption2).foregroundStyle(.secondary)
        }
      }
      Toggle(isOn: Binding(
        get: { cfg.cardsEnabled },
        set: { v in setFlag("cardsEnabled", value: v, in: cfg) }
      )) {
        VStack(alignment: .leading, spacing: 2) {
          Text("Рынок CARDS").font(.subheadline)
          Text("ЖК + красные. Edge vs best available.")
            .font(.caption2).foregroundStyle(.secondary)
        }
      }
    } header: {
      Text("Рынки")
    } footer: {
      Text("Выключенный рынок не генерирует сигналы — ни в скане, ни в portfolio.")
    }
  }

  private func setFlag(_ key: String, value: Bool, in cfg: TuningConfig) {
    let before = currentFlagValue(key, cfg)
    switch key {
    case "autoExcludeEnabled": cfg.autoExcludeEnabled = value
    case "posteriorEnabled": cfg.posteriorEnabled = value
    case "stopLossEnabled": cfg.stopLossEnabled = value
    case "correlationEnabled": cfg.correlationEnabled = value
    case "playerImpactEnabled": cfg.playerImpactEnabled = value
    case "teamRatingEnabled": cfg.teamRatingEnabled = value
    case "cornersEnabled": cfg.cornersEnabled = value
    case "cardsEnabled": cfg.cardsEnabled = value
    case "oosGateEnabled": cfg.oosGateEnabled = value
    default: return
    }
    cfg.updatedAt = Date()
    TuningService.log(context: context, kind: "toggle", target: key,
                      before: before ? "on" : "off",
                      after: value ? "on" : "off",
                      note: "Переключение флага")
  }

  private func currentFlagValue(_ key: String, _ cfg: TuningConfig) -> Bool {
    switch key {
    case "autoExcludeEnabled": return cfg.autoExcludeEnabled
    case "posteriorEnabled": return cfg.posteriorEnabled
    case "stopLossEnabled": return cfg.stopLossEnabled
    case "correlationEnabled": return cfg.correlationEnabled
    case "playerImpactEnabled": return cfg.playerImpactEnabled
    case "teamRatingEnabled": return cfg.teamRatingEnabled
    case "cornersEnabled": return cfg.cornersEnabled
    case "cardsEnabled": return cfg.cardsEnabled
    case "oosGateEnabled": return cfg.oosGateEnabled
    default: return false
    }
  }

  @ViewBuilder
  private func thresholdsSection(_ cfg: TuningConfig) -> some View {
    Section {
      thresholdRow("posteriorWeight", label: "Вес posterior",
        formattedValue: String(format: "%.2f", cfg.posteriorWeight),
        onDelta: { d in cfg.posteriorWeight = max(0.0, min(0.5, cfg.posteriorWeight + d)) },
        currentString: { String(format: "%.4f", cfg.posteriorWeight) },
        step: 0.05, rangeLabel: "0.00 – 0.50")

      thresholdRow("autoExcludeMinROI", label: "Auto-Exclude min ROI",
        formattedValue: String(format: "%.1f%%", cfg.autoExcludeMinROI * 100),
        onDelta: { d in cfg.autoExcludeMinROI = max(-0.5, min(0.0, cfg.autoExcludeMinROI + d)) },
        currentString: { String(format: "%.4f", cfg.autoExcludeMinROI) },
        step: 0.005, rangeLabel: "−50% … 0%")

      thresholdRow("autoExcludeMinBets", label: "Auto-Exclude min n",
        formattedValue: "\(cfg.autoExcludeMinBets)",
        onDelta: { d in
          let v = cfg.autoExcludeMinBets + Int(d.rounded())
          cfg.autoExcludeMinBets = max(5, min(200, v))
        },
        currentString: { "\(cfg.autoExcludeMinBets)" },
        step: 5, rangeLabel: "5 – 200")

      thresholdRow("stopLossCapStreak", label: "Stop-loss: cap после N LOSS",
        formattedValue: "\(cfg.stopLossCapStreak)",
        onDelta: { d in
          let v = cfg.stopLossCapStreak + Int(d.rounded())
          cfg.stopLossCapStreak = max(2, min(10, v))
        },
        currentString: { "\(cfg.stopLossCapStreak)" },
        step: 1, rangeLabel: "2 – 10")

      thresholdRow("stopLossPauseStreak", label: "Stop-loss: pause после N LOSS",
        formattedValue: "\(cfg.stopLossPauseStreak)",
        onDelta: { d in
          let v = cfg.stopLossPauseStreak + Int(d.rounded())
          let lower = cfg.stopLossCapStreak + 1
          cfg.stopLossPauseStreak = max(lower, min(15, v))
        },
        currentString: { "\(cfg.stopLossPauseStreak)" },
        step: 1, rangeLabel: "> cap · … · 15")
    } header: {
      Text("Пороги (глобальные)")
    }
  }

  @ViewBuilder
  private func marketThresholdsSection(_ cfg: TuningConfig) -> some View {
    Section {
      thresholdRow("cornersMinEV", label: "CORNERS min EV",
        formattedValue: String(format: "%.1f%%", cfg.cornersMinEV * 100),
        onDelta: { d in cfg.cornersMinEV = max(0.0, min(0.30, cfg.cornersMinEV + d)) },
        currentString: { String(format: "%.4f", cfg.cornersMinEV) },
        step: 0.005, rangeLabel: "0% … 30%")

      thresholdRow("cornersMinQCS", label: "CORNERS min QCS",
        formattedValue: String(format: "%.0f", cfg.cornersMinQCS),
        onDelta: { d in cfg.cornersMinQCS = max(40, min(100, cfg.cornersMinQCS + d)) },
        currentString: { String(format: "%.0f", cfg.cornersMinQCS) },
        step: 2, rangeLabel: "40 – 100")

      thresholdRow("cornersMaxStake", label: "CORNERS max stake",
        formattedValue: String(format: "%.1f%%", cfg.cornersMaxStake * 100),
        onDelta: { d in cfg.cornersMaxStake = max(0.002, min(0.10, cfg.cornersMaxStake + d)) },
        currentString: { String(format: "%.4f", cfg.cornersMaxStake) },
        step: 0.002, rangeLabel: "0.2% … 10%")

      thresholdRow("cornersMinSample", label: "CORNERS min sample",
        formattedValue: "\(cfg.cornersMinSample)",
        onDelta: { d in
          let v = cfg.cornersMinSample + Int(d.rounded())
          cfg.cornersMinSample = max(2, min(20, v))
        },
        currentString: { "\(cfg.cornersMinSample)" },
        step: 1, rangeLabel: "2 – 20")

      thresholdRow("cornersMinRobustEV", label: "CORNERS min robustEV",
        formattedValue: String(format: "%.1f%%", cfg.cornersMinRobustEV * 100),
        onDelta: { d in cfg.cornersMinRobustEV = max(-0.05, min(0.10, cfg.cornersMinRobustEV + d)) },
        currentString: { String(format: "%.4f", cfg.cornersMinRobustEV) },
        step: 0.005, rangeLabel: "−5% … 10%")

      thresholdRow("cornersMinMSS", label: "CORNERS min MSS",
        formattedValue: String(format: "%.0f", cfg.cornersMinMSS),
        onDelta: { d in cfg.cornersMinMSS = max(0, min(100, cfg.cornersMinMSS + d)) },
        currentString: { String(format: "%.0f", cfg.cornersMinMSS) },
        step: 5, rangeLabel: "0 – 100")

      thresholdRow("cornersMaxUncertainty", label: "CORNERS max uncertainty",
        formattedValue: String(format: "%.2f", cfg.cornersMaxUncertainty),
        onDelta: { d in cfg.cornersMaxUncertainty = max(0.05, min(0.40, cfg.cornersMaxUncertainty + d)) },
        currentString: { String(format: "%.4f", cfg.cornersMaxUncertainty) },
        step: 0.01, rangeLabel: "0.05 – 0.40")
    } header: {
      Text("Пороги CORNERS (углы)")
    }

    Section {
      thresholdRow("cardsMinEV", label: "CARDS min EV",
        formattedValue: String(format: "%.1f%%", cfg.cardsMinEV * 100),
        onDelta: { d in cfg.cardsMinEV = max(0.0, min(0.30, cfg.cardsMinEV + d)) },
        currentString: { String(format: "%.4f", cfg.cardsMinEV) },
        step: 0.005, rangeLabel: "0% … 30%")

      thresholdRow("cardsMinQCS", label: "CARDS min QCS",
        formattedValue: String(format: "%.0f", cfg.cardsMinQCS),
        onDelta: { d in cfg.cardsMinQCS = max(40, min(100, cfg.cardsMinQCS + d)) },
        currentString: { String(format: "%.0f", cfg.cardsMinQCS) },
        step: 2, rangeLabel: "40 – 100")

      thresholdRow("cardsMaxStake", label: "CARDS max stake",
        formattedValue: String(format: "%.1f%%", cfg.cardsMaxStake * 100),
        onDelta: { d in cfg.cardsMaxStake = max(0.002, min(0.10, cfg.cardsMaxStake + d)) },
        currentString: { String(format: "%.4f", cfg.cardsMaxStake) },
        step: 0.002, rangeLabel: "0.2% … 10%")

      thresholdRow("cardsMinSample", label: "CARDS min sample",
        formattedValue: "\(cfg.cardsMinSample)",
        onDelta: { d in
          let v = cfg.cardsMinSample + Int(d.rounded())
          cfg.cardsMinSample = max(2, min(20, v))
        },
        currentString: { "\(cfg.cardsMinSample)" },
        step: 1, rangeLabel: "2 – 20")

      thresholdRow("cardsMinRobustEV", label: "CARDS min robustEV",
        formattedValue: String(format: "%.1f%%", cfg.cardsMinRobustEV * 100),
        onDelta: { d in cfg.cardsMinRobustEV = max(-0.05, min(0.10, cfg.cardsMinRobustEV + d)) },
        currentString: { String(format: "%.4f", cfg.cardsMinRobustEV) },
        step: 0.005, rangeLabel: "−5% … 10%")

      thresholdRow("cardsMinMSS", label: "CARDS min MSS",
        formattedValue: String(format: "%.0f", cfg.cardsMinMSS),
        onDelta: { d in cfg.cardsMinMSS = max(0, min(100, cfg.cardsMinMSS + d)) },
        currentString: { String(format: "%.0f", cfg.cardsMinMSS) },
        step: 5, rangeLabel: "0 – 100")

      thresholdRow("cardsMaxUncertainty", label: "CARDS max uncertainty",
        formattedValue: String(format: "%.2f", cfg.cardsMaxUncertainty),
        onDelta: { d in cfg.cardsMaxUncertainty = max(0.05, min(0.40, cfg.cardsMaxUncertainty + d)) },
        currentString: { String(format: "%.4f", cfg.cardsMaxUncertainty) },
        step: 0.01, rangeLabel: "0.05 – 0.40")
    } header: {
      Text("Пороги CARDS (ЖК)")
    }

    Section {
      thresholdRow("goalsMinRobustEV", label: "GOALS min robustEV",
        formattedValue: String(format: "%.1f%%", cfg.goalsMinRobustEV * 100),
        onDelta: { d in cfg.goalsMinRobustEV = max(-0.05, min(0.10, cfg.goalsMinRobustEV + d)) },
        currentString: { String(format: "%.4f", cfg.goalsMinRobustEV) },
        step: 0.005, rangeLabel: "−5% … 10%")

      thresholdRow("goalsMinSample", label: "GOALS min sample",
        formattedValue: "\(cfg.goalsMinSample)",
        onDelta: { d in
          let v = cfg.goalsMinSample + Int(d.rounded())
          cfg.goalsMinSample = max(2, min(20, v))
        },
        currentString: { "\(cfg.goalsMinSample)" },
        step: 1, rangeLabel: "2 – 20")

      thresholdRow("goalsMaxUncertainty", label: "GOALS max uncertainty",
        formattedValue: String(format: "%.2f", cfg.goalsMaxUncertainty),
        onDelta: { d in cfg.goalsMaxUncertainty = max(0.05, min(0.40, cfg.goalsMaxUncertainty + d)) },
        currentString: { String(format: "%.4f", cfg.goalsMaxUncertainty) },
        step: 0.01, rangeLabel: "0.05 – 0.40")
    } header: {
      Text("Пороги GOALS")
    }
  }

  // [W3a] OOS-пороги
  @ViewBuilder
  private func oosThresholdsSection(_ cfg: TuningConfig) -> some View {
    Section {
      Toggle(isOn: Binding(
        get: { cfg.oosGateEnabled },
        set: { v in setFlag("oosGateEnabled", value: v, in: cfg) }
      )) {
        VStack(alignment: .leading, spacing: 2) {
          Text("OOS-блокировка рынков").font(.subheadline)
          Text("Блокирует рынок, если журнал за окно показывает минус.")
            .font(.caption2).foregroundStyle(.secondary)
        }
      }

      thresholdRow("oosWindowDays", label: "Окно наблюдения (дней)",
        formattedValue: "\(cfg.oosWindowDays)",
        onDelta: { d in
          let v = cfg.oosWindowDays + Int(d.rounded())
          cfg.oosWindowDays = max(14, min(365, v))
        },
        currentString: { "\(cfg.oosWindowDays)" },
        step: 5, rangeLabel: "14 – 365")

      thresholdRow("oosMinBets", label: "Min n в окне",
        formattedValue: "\(cfg.oosMinBets)",
        onDelta: { d in
          let v = cfg.oosMinBets + Int(d.rounded())
          cfg.oosMinBets = max(20, min(500, v))
        },
        currentString: { "\(cfg.oosMinBets)" },
        step: 10, rangeLabel: "20 – 500")

      thresholdRow("goalsOOSMinROI", label: "GOALS min ROI (OOS)",
        formattedValue: String(format: "%.1f%%", cfg.goalsOOSMinROI * 100),
        onDelta: { d in cfg.goalsOOSMinROI = max(-0.20, min(0.05, cfg.goalsOOSMinROI + d)) },
        currentString: { String(format: "%.4f", cfg.goalsOOSMinROI) },
        step: 0.005, rangeLabel: "−20% … 5%")

      thresholdRow("cornersOOSMinROI", label: "CORNERS min ROI (OOS)",
        formattedValue: String(format: "%.1f%%", cfg.cornersOOSMinROI * 100),
        onDelta: { d in cfg.cornersOOSMinROI = max(-0.20, min(0.05, cfg.cornersOOSMinROI + d)) },
        currentString: { String(format: "%.4f", cfg.cornersOOSMinROI) },
        step: 0.005, rangeLabel: "−20% … 5%")

      thresholdRow("cardsOOSMinROI", label: "CARDS min ROI (OOS)",
        formattedValue: String(format: "%.1f%%", cfg.cardsOOSMinROI * 100),
        onDelta: { d in cfg.cardsOOSMinROI = max(-0.20, min(0.05, cfg.cardsOOSMinROI + d)) },
        currentString: { String(format: "%.4f", cfg.cardsOOSMinROI) },
        step: 0.005, rangeLabel: "−20% … 5%")
    } header: {
      Text("OOS-валидация (W3a)")
    } footer: {
      Text("Out-of-sample по реальному журналу. Если по рынку n ≥ Min и ROI ниже порога — рынок автоматически блокируется в сканере. Обновляется после каждой докачки.")
    }
  }

  @ViewBuilder
  private func cornersWeightsSection(_ cfg: TuningConfig) -> some View {
    Section {
      thresholdRow("cornersWeightRecentOwn", label: "Own corners",
        formattedValue: String(format: "%.2f", cfg.cornersWeightRecentOwn),
        onDelta: { d in cfg.cornersWeightRecentOwn = max(0, min(1, cfg.cornersWeightRecentOwn + d)) },
        currentString: { String(format: "%.4f", cfg.cornersWeightRecentOwn) },
        step: 0.05, rangeLabel: "0.00 – 1.00")

      thresholdRow("cornersWeightRecentOpp", label: "Opp corners",
        formattedValue: String(format: "%.2f", cfg.cornersWeightRecentOpp),
        onDelta: { d in cfg.cornersWeightRecentOpp = max(0, min(1, cfg.cornersWeightRecentOpp + d)) },
        currentString: { String(format: "%.4f", cfg.cornersWeightRecentOpp) },
        step: 0.05, rangeLabel: "0.00 – 1.00")

      thresholdRow("cornersWeightLeague", label: "League avg",
        formattedValue: String(format: "%.2f", cfg.cornersWeightLeague),
        onDelta: { d in cfg.cornersWeightLeague = max(0, min(1, cfg.cornersWeightLeague + d)) },
        currentString: { String(format: "%.4f", cfg.cornersWeightLeague) },
        step: 0.05, rangeLabel: "0.00 – 1.00")

      thresholdRow("cornersWeightXG", label: "xG factor",
        formattedValue: String(format: "%.2f", cfg.cornersWeightXG),
        onDelta: { d in cfg.cornersWeightXG = max(0, min(1, cfg.cornersWeightXG + d)) },
        currentString: { String(format: "%.4f", cfg.cornersWeightXG) },
        step: 0.05, rangeLabel: "0.00 – 1.00")

      thresholdRow("cornersWeightPossession", label: "Possession",
        formattedValue: String(format: "%.2f", cfg.cornersWeightPossession),
        onDelta: { d in cfg.cornersWeightPossession = max(0, min(1, cfg.cornersWeightPossession + d)) },
        currentString: { String(format: "%.4f", cfg.cornersWeightPossession) },
        step: 0.05, rangeLabel: "0.00 – 1.00")

      thresholdRow("cornersWeightH2H", label: "H2H",
        formattedValue: String(format: "%.2f", cfg.cornersWeightH2H),
        onDelta: { d in cfg.cornersWeightH2H = max(0, min(1, cfg.cornersWeightH2H + d)) },
        currentString: { String(format: "%.4f", cfg.cornersWeightH2H) },
        step: 0.05, rangeLabel: "0.00 – 1.00")
    } header: {
      Text("Веса λ CORNERS")
    } footer: {
      Text("Сумма весов не обязана быть 1 — нормализуется автоматически. Own/Opp разлагают λ на «создаёт» и «позволяет».")
    }
  }

  @ViewBuilder
  private func cardsWeightsSection(_ cfg: TuningConfig) -> some View {
    Section {
      thresholdRow("cardsWeightRecentOwn", label: "Own cards",
        formattedValue: String(format: "%.2f", cfg.cardsWeightRecentOwn),
        onDelta: { d in cfg.cardsWeightRecentOwn = max(0, min(1, cfg.cardsWeightRecentOwn + d)) },
        currentString: { String(format: "%.4f", cfg.cardsWeightRecentOwn) },
        step: 0.05, rangeLabel: "0.00 – 1.00")

      thresholdRow("cardsWeightRecentOpp", label: "Opp cards",
        formattedValue: String(format: "%.2f", cfg.cardsWeightRecentOpp),
        onDelta: { d in cfg.cardsWeightRecentOpp = max(0, min(1, cfg.cardsWeightRecentOpp + d)) },
        currentString: { String(format: "%.4f", cfg.cardsWeightRecentOpp) },
        step: 0.05, rangeLabel: "0.00 – 1.00")

      thresholdRow("cardsWeightLeague", label: "League avg",
        formattedValue: String(format: "%.2f", cfg.cardsWeightLeague),
        onDelta: { d in cfg.cardsWeightLeague = max(0, min(1, cfg.cardsWeightLeague + d)) },
        currentString: { String(format: "%.4f", cfg.cardsWeightLeague) },
        step: 0.05, rangeLabel: "0.00 – 1.00")

      thresholdRow("cardsWeightFouls", label: "Fouls factor",
        formattedValue: String(format: "%.2f", cfg.cardsWeightFouls),
        onDelta: { d in cfg.cardsWeightFouls = max(0, min(1, cfg.cardsWeightFouls + d)) },
        currentString: { String(format: "%.4f", cfg.cardsWeightFouls) },
        step: 0.05, rangeLabel: "0.00 – 1.00")

      thresholdRow("cardsWeightReferee", label: "Referee",
        formattedValue: String(format: "%.2f", cfg.cardsWeightReferee),
        onDelta: { d in cfg.cardsWeightReferee = max(0, min(1, cfg.cardsWeightReferee + d)) },
        currentString: { String(format: "%.4f", cfg.cardsWeightReferee) },
        step: 0.05, rangeLabel: "0.00 – 1.00")

      thresholdRow("cardsWeightH2H", label: "H2H",
        formattedValue: String(format: "%.2f", cfg.cardsWeightH2H),
        onDelta: { d in cfg.cardsWeightH2H = max(0, min(1, cfg.cardsWeightH2H + d)) },
        currentString: { String(format: "%.4f", cfg.cardsWeightH2H) },
        step: 0.05, rangeLabel: "0.00 – 1.00")
    } header: {
      Text("Веса λ CARDS")
    } footer: {
      Text("Сумма весов не обязана быть 1 — нормализуется автоматически.")
    }
  }

  @ViewBuilder
  private func thresholdRow(_ key: String, label: String,
                            formattedValue: String,
                            onDelta: @escaping (Double) -> Void,
                            currentString: @escaping () -> String,
                            step: Double, rangeLabel: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(label).font(.subheadline)
        Spacer()
        Text(formattedValue).font(.subheadline.monospacedDigit().bold())
          .foregroundStyle(.blue)
      }
      HStack(spacing: 8) {
        Button {
          let b = currentString(); onDelta(-step); let a = currentString()
          TuningService.log(context: context, kind: "threshold", target: key,
                            before: b, after: a, note: label)
        } label: { Image(systemName: "minus.circle.fill").foregroundStyle(.blue) }
        .buttonStyle(.plain)

        Button {
          let b = currentString(); onDelta(step); let a = currentString()
          TuningService.log(context: context, kind: "threshold", target: key,
                            before: b, after: a, note: label)
        } label: { Image(systemName: "plus.circle.fill").foregroundStyle(.blue) }
        .buttonStyle(.plain)

        Spacer()
        Text(rangeLabel).font(.caption2).foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 2)
  }

  @ViewBuilder
  private var eventsSection: some View {
    Section {
      Button {
        if let rb = TuningService.rollbackLastThreshold(in: context) {
          rollbackMessage = "Откат: \(rb.target) → \(rb.beforeValue)"
        } else {
          rollbackMessage = "Нет изменений для отката"
        }
      } label: {
        Label("Откатить последнее изменение", systemImage: "arrow.uturn.backward")
      }
      if let msg = rollbackMessage {
        Text(msg).font(.caption).foregroundStyle(.secondary)
      }
      if events.isEmpty {
        Text("Журнал пуст").font(.caption).foregroundStyle(.secondary)
      } else {
        ForEach(events.prefix(30)) { e in
          HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
              HStack(spacing: 6) {
                Text(kindLabel(e.kind)).font(.caption2.bold())
                  .foregroundStyle(kindColor(e.kind))
                Text(e.target).font(.caption.monospaced())
              }
              HStack(spacing: 4) {
                Text(e.beforeValue).font(.caption2.monospacedDigit())
                  .foregroundStyle(.secondary)
                Image(systemName: "arrow.right").font(.caption2)
                  .foregroundStyle(.secondary)
                Text(e.afterValue).font(.caption2.monospacedDigit())
                  .foregroundStyle(.primary)
              }
              if !e.note.isEmpty {
                Text(e.note).font(.caption2).foregroundStyle(.tertiary)
              }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
              Text(e.createdAt.formatted(date: .omitted, time: .shortened))
                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
              if e.rolledBack {
                Text("откатано").font(.caption2).foregroundStyle(.orange)
              }
            }
          }
          .padding(.vertical, 2)
        }
      }
    } header: {
      Text("Журнал изменений")
    } footer: {
      Text("Показываются последние 30 событий. Каждое изменение порога или тумблера логируется с возможностью отката.")
    }
  }

  private func kindLabel(_ k: String) -> String {
    switch k {
    case "toggle": return "TOGGLE"
    case "threshold": return "THRESH"
    case "rollback": return "ROLL"
    case "auto": return "AUTO"
    default: return k.uppercased()
    }
  }

  private func kindColor(_ k: String) -> Color {
    switch k {
    case "toggle": return .blue
    case "threshold": return .purple
    case "rollback": return .orange
    case "auto": return .green
    default: return .gray
    }
  }

  @ViewBuilder
  private var resetSection: some View {
    Section {
      Button(role: .destructive) {
        guard let cfg = config else { return }
        let before = "custom"
        cfg.autoExcludeEnabled = true
        cfg.posteriorEnabled = true
        cfg.stopLossEnabled = true
        cfg.correlationEnabled = true
        cfg.playerImpactEnabled = true
        cfg.teamRatingEnabled = true
        cfg.posteriorWeight = 0.15
        cfg.autoExcludeMinROI = -0.05
        cfg.autoExcludeMinBets = 20
        cfg.stopLossCapStreak = 4
        cfg.stopLossPauseStreak = 7
        cfg.cornersEnabled = true
        cfg.cardsEnabled = true
        cfg.cornersMinEV = 0.03
        cfg.cardsMinEV = 0.03
        cfg.cornersMinQCS = 70
        cfg.cardsMinQCS = 70
        cfg.cornersMaxStake = 0.02
        cfg.cardsMaxStake = 0.02
        cfg.cornersMinSample = 5
        cfg.cardsMinSample = 5
        cfg.goalsMinRobustEV = 0.0
        cfg.goalsMinSample = 6
        cfg.goalsMaxUncertainty = 0.25
        cfg.cornersMinRobustEV = 0.0
        cfg.cornersMinMSS = 30
        cfg.cornersMaxUncertainty = 0.22
        cfg.cardsMinRobustEV = 0.0
        cfg.cardsMinMSS = 30
        cfg.cardsMaxUncertainty = 0.22
        cfg.oosGateEnabled = false
        cfg.oosMinBets = 100
        cfg.oosWindowDays = 90
        cfg.goalsOOSMinROI = -0.03
        cfg.cornersOOSMinROI = -0.03
        cfg.cardsOOSMinROI = -0.03
        cfg.cornersWeightRecentOwn = 0.35
        cfg.cornersWeightRecentOpp = 0.25
        cfg.cornersWeightLeague = 0.15
        cfg.cornersWeightXG = 0.10
        cfg.cornersWeightPossession = 0.05
        cfg.cornersWeightH2H = 0.10
        cfg.cardsWeightRecentOwn = 0.30
        cfg.cardsWeightRecentOpp = 0.20
        cfg.cardsWeightLeague = 0.15
        cfg.cardsWeightFouls = 0.10
        cfg.cardsWeightReferee = 0.20
        cfg.cardsWeightH2H = 0.05
        cfg.updatedAt = Date()
        TuningService.log(context: context, kind: "threshold", target: "all",
                          before: before, after: "defaults", note: "Сброс к дефолтам")
        rollbackMessage = "Сброшено к дефолтам"
      } label: {
        Label("Сбросить к дефолтам", systemImage: "arrow.clockwise")
      }
    } header: {
      Text("Сброс")
    }
  }
}
