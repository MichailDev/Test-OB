import Foundation
import SwiftUI

struct SignalCard: View {
  let signal: BetSignal
  let oddsFormat: OddsFormat
  @EnvironmentObject private var settings: AppSettings

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top) {
        Text("\(signal.home) — \(signal.away)").font(.headline)
          .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 8)
        Text(signal.classification).font(.caption.bold())
          .padding(.horizontal, 8).padding(.vertical, 4)
          .background(classificationColor(signal.classification).opacity(0.25))
          .clipShape(Capsule())
      }
      if let s = formatMatchStart(signal.startTime) {
        HStack(spacing: 4) {
          Image(systemName: "clock")
          Text(s)
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
      }
      Text(marketLine).font(.subheadline).foregroundStyle(.secondary)
      HStack(alignment: .top, spacing: 14) {
        metric("Odds", OddsFormatter.format(signal.odds, as: oddsFormat))
        metric("P", String(format: "%.1f%%", signal.probability * 100))
        metric("EV", String(format: "%+.1f%%", signal.ev * 100))
        metric("Rob.", String(format: "%+.1f%%", signal.robustEV * 100))
        metric("QCS", String(format: "%.0f", signal.qcs))
        stakeMetric
      }
      HStack(spacing: 10) {
        Text("DCS \(String(format: "%.0f", signal.dcs))")
        Text("MS \(String(format: "%.0f", signal.ms))")
        Text("Sample \(signal.sampleClass)")
        Text("\(signal.bookmakers)b")
        if let src = signal.oddsSource {
          Text(src).foregroundStyle(.blue)
        }
        if let mss = signal.mss, signal.market == "CORNERS" || signal.market == "CARDS" {
          Text("MSS \(String(format: "%.0f", mss))")
            .foregroundStyle(mss >= 70 ? .green : (mss >= 40 ? .primary : .orange))
        }
        if signal.posteriorWeight != nil { Text("PST").foregroundStyle(.purple) }
        if signal.stopApplied != nil { Text("STOP").foregroundStyle(.red) }
        if signal.playerImpactHome != nil || signal.playerImpactAway != nil {
          Text("PLR").foregroundStyle(.orange)
        }
        if signal.sharpMoney == true { Text("SHARP").foregroundStyle(.purple) }
        if let v = signal.modelVote {
          Text("VOTE \(v)/4")
            .foregroundStyle(v >= 3 ? .green : (v == 2 ? .orange : .red))
        }
      }
      .font(.caption2).foregroundStyle(.secondary)
    }
    .padding(.vertical, 6)
  }

  private var marketLine: String {
    let linePart: String = signal.line.map { " \($0)" } ?? ""
    var base = "\(signal.league) · \(signal.market) · \(signal.selection)\(linePart)"
    if let src = signal.oddsSource {
      base += " · \(src)"
    }
    return base
  }

  @ViewBuilder
  private var stakeMetric: some View {
    if settings.useMoneyStakes, let money = signal.stakeMoney {
      VStack(alignment: .leading, spacing: 2) {
        Text("Stake").font(.caption2).foregroundStyle(.secondary)
        Text(String(format: "%.0f", money)).font(.caption.monospacedDigit())
      }
    } else {
      metric("Stake", String(format: "%.2f%%", signal.stake * 100))
    }
  }

  private func classificationColor(_ c: String) -> Color {
    switch c {
    case "S BET": return .green
    case "A BET": return .blue
    case "B LEAN": return .yellow
    case "C WATCH": return .orange
    default: return .gray
    }
  }

  private func metric(_ n: String, _ v: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(n).font(.caption2).foregroundStyle(.secondary)
      Text(v).font(.caption.monospacedDigit())
    }
  }
}
