import Charts
import SwiftUI

/// Vue détaillée ouverte depuis la jauge 5 h : limites, équivalent API en dollars, tokens.
struct UsageDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var monitor: LiveMonitor
    @State private var stats: PulseStats?
    @State private var error: String?
    @State private var metric: Metric = .dollars

    enum Metric: String, CaseIterable, Identifiable {
        case dollars = "Dollars"
        case tokens = "Tokens"
        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 12) {
                    LimitTile(title: "5 heures", limit: monitor.state?.limits.fiveHour)
                    LimitTile(title: "7 jours", limit: monitor.state?.limits.sevenDay)
                }

                if let stats {
                    apiSection(stats)
                    chartSection(stats)
                    tokensSection(stats)
                    if !stats.models.isEmpty { modelsSection(stats) }
                    Footnote(
                        "Estimation au tarif public de l'API, pour comparer avec ton abonnement : ce n'est pas ce que tu paies. "
                            + "Calculé à partir des sessions Claude Code gardées sur ton Mac (30 derniers jours par défaut) ; "
                            + "les conversations sur claude.ai et l'app mobile ne sont pas comptées."
                    )
                } else if let error {
                    NoticeCard(symbol: "exclamationmark.triangle", text: error, tint: PulseStyle.critical)
                } else {
                    ProgressView().tint(PulseStyle.accent).frame(maxWidth: .infinity).padding(.top, 40)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            ZStack {
                Text("Utilisation")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(PulseStyle.textPrimary)
                HStack {
                    CircleButton(symbol: "xmark", label: "Fermer") { dismiss() }
                    Spacer()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)
            .background(PulseStyle.background)
        }
        .background(PulseStyle.background.ignoresSafeArea())
        .presentationDragIndicator(.visible)
        .task { await load() }
        .refreshable { await load() }
        .tint(PulseStyle.accent)
    }

    private func load() async {
        do {
            stats = try await PulseAPI.fetchStats()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: Sections

    private func apiSection(_ s: PulseStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: "Si tu payais l'API")
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(PulseStyle.dollars(s.totals.costUsd, decimals: 0))
                        .font(.system(size: 44, weight: .regular, design: .serif).monospacedDigit())
                        .foregroundStyle(PulseStyle.textPrimary)
                    Text(s.sinceDate.map { "depuis le \(PulseStyle.shortDate($0)) · \(s.sessions) sessions" } ?? "aucune session pour l'instant")
                        .font(.subheadline)
                        .foregroundStyle(PulseStyle.textSecondary)
                }
                HStack(spacing: 0) {
                    PeriodStat(title: "Aujourd'hui", value: PulseStyle.dollars(s.periods.today.costUsd))
                    PeriodStat(title: "7 jours", value: PulseStyle.dollars(s.periods.week.costUsd, decimals: 0))
                    PeriodStat(title: "30 jours", value: PulseStyle.dollars(s.periods.month.costUsd, decimals: 0))
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PulseStyle.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private func chartSection(_ s: PulseStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(title: "30 derniers jours")
                Spacer()
                Picker("Mesure", selection: $metric) {
                    ForEach(Metric.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
                .sensoryFeedback(.selection, trigger: metric)
            }
            Chart(s.days) { d in
                BarMark(
                    x: .value("Jour", d.date, unit: .day),
                    y: .value(metric.rawValue, metric == .dollars ? d.costUsd : Double(d.tokens))
                )
                .foregroundStyle(PulseStyle.peach.gradient)
                .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated), centered: true)
                        .foregroundStyle(PulseStyle.textSecondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(PulseStyle.separator)
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(metric == .dollars ? PulseStyle.dollars(v, decimals: 0) : PulseStyle.tokens(Int(v)))
                                .foregroundStyle(PulseStyle.textSecondary)
                        }
                    }
                }
            }
            .frame(height: 180)
            .padding(16)
            .background(PulseStyle.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private func tokensSection(_ s: PulseStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: "Tokens")
            RowGroup {
                HStack(alignment: .firstTextBaseline) {
                    Text(PulseStyle.tokens(s.totals.tokens))
                        .font(.system(size: 30, weight: .regular, design: .serif).monospacedDigit())
                        .foregroundStyle(PulseStyle.textPrimary)
                    Text("au total")
                        .foregroundStyle(PulseStyle.textSecondary)
                    Spacer()
                    Text("\(PulseStyle.tokens(s.periods.today.tokens)) aujourd'hui")
                        .font(.subheadline)
                        .foregroundStyle(PulseStyle.textSecondary)
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                RowDivider()
                InfoRow(symbol: "arrow.down.circle", title: "Envoyés à Claude", value: PulseStyle.tokens(s.totals.input))
                RowDivider()
                InfoRow(symbol: "arrow.up.circle", title: "Écrits par Claude", value: PulseStyle.tokens(s.totals.output))
                RowDivider()
                InfoRow(symbol: "square.and.arrow.down", title: "Mis en cache", value: PulseStyle.tokens(s.totals.cacheWrite))
                RowDivider()
                InfoRow(symbol: "bolt", title: "Relus depuis le cache", value: PulseStyle.tokens(s.totals.cacheRead))
            }
        }
    }

    private func modelsSection(_ s: PulseStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: "Par modèle")
            RowGroup {
                ForEach(Array(s.models.enumerated()), id: \.element.id) { index, m in
                    if index > 0 { RowDivider() }
                    HStack(spacing: 12) {
                        RowIcon(symbol: "sparkle", color: PulseStyle.peach)
                        Text(m.model).foregroundStyle(PulseStyle.textPrimary)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(PulseStyle.dollars(m.costUsd, decimals: 0))
                                .monospacedDigit()
                                .foregroundStyle(PulseStyle.textPrimary)
                            Text("\(PulseStyle.tokens(m.tokens)) tokens")
                                .font(.caption)
                                .foregroundStyle(PulseStyle.textSecondary)
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                }
            }
        }
    }
}

private struct LimitTile: View {
    let title: String
    let limit: PulseState.Limit?

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RingGauge(pct: limit?.pct, lineWidth: 10)
                Text(limit.map { "\(Int($0.pct.rounded())) %" } ?? "—")
                    .font(.system(size: 22, weight: .regular, design: .serif).monospacedDigit())
                    .foregroundStyle(PulseStyle.textPrimary)
            }
            .frame(width: 96, height: 96)
            VStack(spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PulseStyle.textPrimary)
                Text(limit.map { "Remise à zéro \(PulseStyle.resetTime($0.resetDate))" } ?? "Pro ou Max")
                    .font(.caption)
                    .foregroundStyle(PulseStyle.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(PulseStyle.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct PeriodStat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(PulseStyle.textSecondary)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(PulseStyle.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
