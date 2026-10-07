import SwiftUI
import WidgetKit

struct UsageEntry: TimelineEntry {
    let date: Date
    let state: PulseState?
    let error: String?
}

struct UsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: .now, state: .preview, error: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        Task { completion(await load()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        Task {
            let entry = await load()
            // Plus souvent quand Claude travaille ; iOS reste maître du rythme réel.
            let busy = !(entry.state?.activeSessions.isEmpty ?? true)
            let next = Date().addingTimeInterval(busy ? 5 * 60 : 15 * 60)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    private func load() async -> UsageEntry {
        do {
            return UsageEntry(date: .now, state: try await PulseAPI.fetchState(), error: nil)
        } catch {
            return UsageEntry(date: .now, state: PulseConfig.cachedState, error: error.localizedDescription)
        }
    }
}

struct UsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ClaudePulseUsage", provider: UsageProvider()) { entry in
            UsageWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Utilisation Claude")
        .description("Limites 5 h / 7 jours, coût du jour et sessions en cours.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct UsageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    private var state: PulseState? { entry.state }
    private var fiveHour: Double? { state?.limits.fiveHour?.pct }
    private var sevenDay: Double? { state?.limits.sevenDay?.pct }

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline: Text("Claude · 5h \(pctText(fiveHour)) · 7j \(pctText(sevenDay))")
        case .systemMedium: medium
        default: small
        }
    }

    // MARK: Écran d'accueil

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            LimitBar(title: "5 h", pct: fiveHour)
            LimitBar(title: "7 j", pct: sevenDay)
            Spacer(minLength: 0)
            HStack {
                Text(PulseStyle.cost(state?.today.costUsd ?? 0)).font(.headline.monospacedDigit())
                Spacer()
                activeBadge
            }
        }
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                header
                LimitBar(title: "5 h", pct: fiveHour)
                LimitBar(title: "7 j", pct: sevenDay)
                Spacer(minLength: 0)
                Text("Aujourd'hui \(PulseStyle.cost(state?.today.costUsd ?? 0))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 8) {
                let sessions = Array((state?.activeSessions ?? []).prefix(2))
                if sessions.isEmpty {
                    Spacer()
                    Label("Aucune tâche en cours", systemImage: "moon.zzz.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    ForEach(sessions) { session in
                        VStack(alignment: .leading, spacing: 3) {
                            Label(session.project, systemImage: PulseStyle.symbol(for: session.status))
                                .font(.caption.bold())
                                .foregroundStyle(PulseStyle.color(for: session.status))
                                .lineLimit(1)
                            Text(session.activity).font(.caption2).lineLimit(1)
                            if session.stepsTotal > 0 {
                                ProgressView(value: Double(session.stepsDone), total: Double(session.stepsTotal))
                                    .tint(PulseStyle.color(for: session.status))
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkle").foregroundStyle(PulseStyle.accent)
            Text("Claude").font(.headline)
            Spacer()
            if entry.error != nil {
                Image(systemName: "wifi.exclamationmark").foregroundStyle(.secondary).font(.caption)
            }
        }
    }

    @ViewBuilder private var activeBadge: some View {
        let count = state?.activeSessions.count ?? 0
        if count > 0 {
            Label("\(count)", systemImage: "bolt.fill")
                .font(.caption.bold())
                .foregroundStyle(PulseStyle.accent)
        }
    }

    // MARK: Écran verrouillé

    private var circular: some View {
        Gauge(value: min(fiveHour ?? 0, 100), in: 0...100) {
            Text("5h")
        } currentValueLabel: {
            Text(fiveHour.map { "\(Int($0.rounded()))" } ?? "–")
        }
        .gaugeStyle(.accessoryCircular)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Claude · 5h \(pctText(fiveHour)) · 7j \(pctText(sevenDay))")
                .font(.headline)
            if let session = state?.activeSessions.first {
                Text("\(session.project) : \(session.activity)").lineLimit(1)
                if session.stepsTotal > 0 {
                    ProgressView(value: Double(session.stepsDone), total: Double(session.stepsTotal))
                }
            } else {
                Text("Aujourd'hui \(PulseStyle.cost(state?.today.costUsd ?? 0))")
            }
        }
    }

    private func pctText(_ pct: Double?) -> String {
        pct.map { "\(Int($0.rounded())) %" } ?? "–"
    }
}

struct LimitBar: View {
    let title: String
    let pct: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(pct.map { "\(Int($0.rounded())) %" } ?? "–").font(.caption.bold().monospacedDigit())
            }
            ProgressView(value: min(pct ?? 0, 100), total: 100)
                .tint(PulseStyle.gauge(pct ?? 0))
        }
    }
}

#Preview(as: .systemMedium) {
    UsageWidget()
} timeline: {
    UsageEntry(date: .now, state: .preview, error: nil)
}
