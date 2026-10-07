import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var monitor: LiveMonitor
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false

    private var sessions: [PulseState.Session] { monitor.state?.sessions ?? [] }
    private var active: [PulseState.Session] { sessions.filter(\.isActive) }
    private var recent: [PulseState.Session] { sessions.filter { !$0.isActive } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if !PulseConfig.isConfigured {
                        NoticeCard(
                            symbol: "wrench.and.screwdriver.fill",
                            text: "Lance ios/setup.sh avec l'URL du backend et ton PULSE_TOKEN, puis recompile."
                        )
                    }

                    UsageHero(limits: monitor.state?.limits, today: monitor.state?.today)
                    MonitorCard()

                    if let error = monitor.lastError {
                        NoticeCard(symbol: "exclamationmark.triangle.fill", text: error, tint: PulseStyle.critical)
                    }

                    if !active.isEmpty {
                        SectionTitle(title: "En cours", count: active.count)
                        ForEach(active) { SessionCard(session: $0) }
                    }

                    if !recent.isEmpty {
                        SectionTitle(title: "Récemment", count: nil)
                        VStack(spacing: 0) {
                            ForEach(Array(recent.enumerated()), id: \.element.id) { index, session in
                                if index > 0 { Divider().overlay(PulseStyle.stroke).padding(.leading, 54) }
                                RecentRow(session: session)
                            }
                        }
                        .pulseCard()
                    }

                    if sessions.isEmpty && monitor.state != nil {
                        EmptyState()
                    } else if monitor.state == nil && PulseConfig.isConfigured {
                        ProgressView().tint(PulseStyle.accent).padding(.top, 24)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
                .animation(.snappy, value: sessions.map(\.status))
            }
            .scrollIndicators(.hidden)
            .background(PulseStyle.background.ignoresSafeArea())
            .navigationTitle("Claude Pulse")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape.fill").foregroundStyle(PulseStyle.textSecondary)
                    }
                    .accessibilityLabel("Réglages")
                }
            }
            .refreshable { await monitor.refresh() }
            .task { await monitor.refresh() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active && !monitor.isRunning { Task { await monitor.refresh() } }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
        .preferredColorScheme(.dark)
        .tint(PulseStyle.accent)
    }
}

// MARK: - Limites

struct UsageHero: View {
    let limits: PulseState.Limits?
    let today: PulseState.Today?

    var body: some View {
        let five = limits?.fiveHour
        let seven = limits?.sevenDay
        HStack(alignment: .center, spacing: 20) {
            ZStack {
                RingGauge(pct: five?.pct, lineWidth: 13)
                VStack(spacing: 0) {
                    Text(five.map { "\(Int($0.pct.rounded()))" } ?? "—")
                        .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text(five == nil ? "Pro / Max" : "% · 5 h")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PulseStyle.textSecondary)
                }
            }
            .frame(width: 128, height: 128)

            VStack(alignment: .leading, spacing: 14) {
                HeroStat(label: "Réinitialisation 5 h", value: five.map { PulseStyle.resetTime($0.resetDate) } ?? "—")

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("7 jours")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PulseStyle.textSecondary)
                        Spacer()
                        Text(seven.map { "\(Int($0.pct.rounded())) %" } ?? "—")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(seven.map { PulseStyle.gauge($0.pct) } ?? PulseStyle.textTertiary)
                    }
                    LimitBar(pct: seven?.pct, height: 8)
                    if let seven {
                        Text("réinit. \(PulseStyle.resetTime(seven.resetDate))")
                            .font(.caption2)
                            .foregroundStyle(PulseStyle.textTertiary)
                    }
                }

                HeroStat(
                    label: "Aujourd'hui",
                    value: today.map { "\(PulseStyle.cost($0.costUsd)) · \($0.sessions) session\($0.sessions > 1 ? "s" : "")" } ?? "—"
                )
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .pulseCard()
    }
}

struct HeroStat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PulseStyle.textSecondary)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

// MARK: - Surveillance

struct MonitorCard: View {
    @EnvironmentObject private var monitor: LiveMonitor

    var body: some View {
        if monitor.isRunning {
            HStack(spacing: 12) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(PulseStyle.good)
                    .symbolEffect(.variableColor.iterative, options: .repeating)
                    .frame(width: 36, height: 36)
                    .background(PulseStyle.good.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Surveillance active")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    if let last = monitor.lastUpdate {
                        Text("Mise à jour \(Text(last, style: .relative))")
                            .font(.caption)
                            .foregroundStyle(PulseStyle.textSecondary)
                    }
                }
                Spacer()
                Button("Arrêter") { Task { await monitor.stop() } }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.10), in: Capsule())
            }
            .padding(14)
            .pulseCard()
        } else {
            VStack(spacing: 8) {
                Button {
                    Task { await monitor.start() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                        Text("Lancer la surveillance")
                    }
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        LinearGradient(colors: [PulseStyle.accentSoft, PulseStyle.accent], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                }
                .disabled(!PulseConfig.isConfigured)
                .opacity(PulseConfig.isConfigured ? 1 : 0.4)

                Text("Live Activity sur l'écran verrouillé et notifications quand Claude attend ta validation ou a terminé. Jusqu'à 8 h.")
                    .font(.caption)
                    .foregroundStyle(PulseStyle.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
        }
    }
}

// MARK: - Sessions

struct SectionTitle: View {
    let title: String
    let count: Int?

    var body: some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(PulseStyle.textSecondary)
            if let count {
                Text("\(count)")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(.black)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(PulseStyle.accent, in: Capsule())
            }
            Spacer()
        }
        .padding(.top, 8)
        .padding(.horizontal, 4)
    }
}

struct SessionCard: View {
    let session: PulseState.Session

    var body: some View {
        let color = PulseStyle.color(for: session.status)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                StatusBadge(status: session.status, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.project)
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let title = session.title, !title.isEmpty {
                        Text(title)
                            .font(.subheadline)
                            .foregroundStyle(PulseStyle.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(PulseStyle.label(for: session.status).uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(color)
                    Text(Date(timeIntervalSince1970: session.startedAt), style: .timer)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 80, alignment: .trailing)
                }
            }

            Text(session.activity)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(2)

            if session.stepsTotal > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("\(min(session.stepsDone + 1, session.stepsTotal))/\(session.stepsTotal)")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(PulseStyle.accent)
                        Text(session.currentStep)
                            .font(.caption)
                            .foregroundStyle(PulseStyle.textSecondary)
                            .lineLimit(1)
                    }
                    ProgressView(value: Double(session.stepsDone), total: Double(session.stepsTotal))
                        .tint(PulseStyle.accent)
                }
            }

            HStack(spacing: 6) {
                MetaChip(symbol: "text.alignleft", text: "ctx \(session.contextPct) %")
                if session.agents > 0 {
                    MetaChip(symbol: "person.2.fill", text: "\(session.agents)")
                }
                if !session.workflow.isEmpty {
                    MetaChip(symbol: "flowchart", text: session.workflow)
                }
                if let model = session.model {
                    MetaChip(symbol: "cpu", text: model)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .pulseCard(highlight: session.status == "waiting" ? PulseStyle.warn : nil)
    }
}

struct RecentRow: View {
    let session: PulseState.Session

    var body: some View {
        HStack(spacing: 12) {
            StatusBadge(status: session.status, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.project)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(session.title ?? session.activity)
                    .font(.caption)
                    .foregroundStyle(PulseStyle.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(session.duration)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.85))
                Text(Date(timeIntervalSince1970: session.updatedAt), format: .relative(presentation: .named))
                    .font(.caption2)
                    .foregroundStyle(PulseStyle.textTertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

struct MetaChip: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            Text(text).lineLimit(1)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(PulseStyle.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(PulseStyle.cardRaised, in: Capsule())
    }
}

// MARK: - États

struct EmptyState: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(PulseStyle.accent.opacity(0.8))
            Text("Aucune session récente")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Lance Claude Code sur ton Mac : tes sessions apparaîtront ici.")
                .font(.subheadline)
                .foregroundStyle(PulseStyle.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 36)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .pulseCard()
    }
}

struct NoticeCard: View {
    let symbol: String
    let text: String
    var tint: Color = PulseStyle.warn

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .pulseCard(highlight: tint)
    }
}

extension View {
    /// Carte sombre aux coins continus, bordure fine (ou colorée pour attirer l'œil).
    func pulseCard(highlight: Color? = nil) -> some View {
        background(PulseStyle.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(highlight.map { $0.opacity(0.45) } ?? PulseStyle.stroke, lineWidth: 1)
            )
    }
}

#Preview {
    ContentView().environmentObject(LiveMonitor.shared)
}
