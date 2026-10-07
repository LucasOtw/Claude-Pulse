import SwiftUI

/// Écran principal, dans l'esprit de l'app Claude : fond ivoire, groupes de lignes gris sable,
/// icônes au trait, boutons ronds flottants, serif pour le contenu.
struct ContentView: View {
    @EnvironmentObject private var monitor: LiveMonitor
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var showDetail = false
    @State private var selected: PulseState.Session?
    @State private var refreshes = 0

    private var sessions: [PulseState.Session] { monitor.state?.sessions ?? [] }
    private var active: [PulseState.Session] { sessions.filter(\.isActive) }
    private var recent: [PulseState.Session] { sessions.filter { !$0.isActive } }
    private var statuses: [String: String] {
        Dictionary(sessions.map { ($0.sid, $0.status) }, uniquingKeysWith: { a, _ in a })
    }

    // Le corps est découpé en petits morceaux : une seule longue chaîne de modificateurs
    // dépasse le temps que le compilateur Swift s'accorde pour vérifier les types.
    var body: some View {
        scroll
            .safeAreaInset(edge: .top, spacing: 0) { header }
            .background(PulseStyle.background.ignoresSafeArea())
            .refreshable { await pullToRefresh() }
            .modifier(HomeHaptics(
                showDetail: showDetail,
                selectedID: selected?.id,
                refreshes: refreshes,
                statuses: statuses,
                error: monitor.lastError
            ))
            .task {
                await monitor.resume()
                if !monitor.isRunning { await monitor.refresh() }
            }
            .onChange(of: scenePhase) { _, phase in onScenePhase(phase) }
            .modifier(HomeSheets(showSettings: $showSettings, showDetail: $showDetail, selected: $selected))
            .tint(PulseStyle.accent)
    }

    private var header: some View {
        Header(onSettings: { showSettings = true }, onRefresh: { Task { await monitor.refresh() } })
    }

    private var scroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                summary
                sessionLists
                placeholder
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 40)
            .animation(.snappy, value: sessions.map(\.status))
        }
        .scrollIndicators(.hidden)
    }

    /// Configuration, limites, surveillance, erreur.
    @ViewBuilder
    private var summary: some View {
        if !PulseConfig.isConfigured {
            NoticeCard(
                symbol: "wrench.and.screwdriver",
                text: "Lance ios/setup.sh avec l'URL du backend et ton PULSE_TOKEN, puis recompile."
            )
        }

        Button { showDetail = true } label: {
            LimitHero(limit: monitor.state?.limits.fiveHour)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Ouvre le détail de ton utilisation")

        RowGroup {
            WeekRow(limit: monitor.state?.limits.sevenDay)
            RowDivider()
            InfoRow(symbol: "terminal", title: "Sessions aujourd'hui", value: todaySessions)
        }

        MonitorCTA()

        if let error = monitor.lastError {
            NoticeCard(symbol: "exclamationmark.triangle", text: error, tint: PulseStyle.critical)
        }
    }

    /// Sessions en cours (cartes) et récentes (lignes).
    @ViewBuilder
    private var sessionLists: some View {
        if !active.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(title: "En cours")
                ForEach(active) { session in
                    Button { selected = session } label: { SessionCard(session: session) }
                        .buttonStyle(.plain)
                }
            }
        }

        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(title: "Récemment")
                RowGroup {
                    ForEach(Array(recent.enumerated()), id: \.element.id) { index, session in
                        if index > 0 { RowDivider() }
                        Button { selected = session } label: { RecentRow(session: session) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var placeholder: some View {
        if sessions.isEmpty && monitor.state != nil {
            EmptyState()
        } else if monitor.state == nil && PulseConfig.isConfigured {
            ProgressView().tint(PulseStyle.accent).frame(maxWidth: .infinity).padding(.top, 24)
        }
    }

    private var todaySessions: String {
        guard let state = monitor.state else { return "—" }
        return "\(state.today.sessions)"
    }

    private func pullToRefresh() async {
        await monitor.refresh()
        refreshes += 1
    }

    private func onScenePhase(_ phase: ScenePhase) {
        guard phase == .active else { return }
        Task {
            await monitor.resume()
            if !monitor.isRunning { await monitor.refresh() }
        }
    }
}

/// Retours haptiques de l'écran principal : ouvrir un détail, fin d'un tirer-pour-rafraîchir,
/// Claude qui attend ta validation ou qui termine, erreur.
private struct HomeHaptics: ViewModifier {
    let showDetail: Bool
    let selectedID: String?
    let refreshes: Int
    let statuses: [String: String]
    let error: String?

    func body(content: Content) -> some View {
        content
            .sensoryFeedback(.impact(flexibility: .soft), trigger: showDetail) { (_: Bool, open: Bool) -> Bool in open }
            .sensoryFeedback(.impact(flexibility: .soft), trigger: selectedID) { (_: String?, id: String?) -> Bool in id != nil }
            .sensoryFeedback(.impact(weight: .light), trigger: refreshes)
            .sensoryFeedback(trigger: statuses) { (old: [String: String], new: [String: String]) -> SensoryFeedback? in
                PulseHaptics.sessions(old: old, new: new)
            }
            .sensoryFeedback(trigger: error) { (_: String?, new: String?) -> SensoryFeedback? in
                new == nil ? nil : .error
            }
    }
}

/// Feuilles ouvertes depuis l'écran principal.
private struct HomeSheets: ViewModifier {
    @EnvironmentObject private var monitor: LiveMonitor
    @Binding var showSettings: Bool
    @Binding var showDetail: Bool
    @Binding var selected: PulseState.Session?

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showSettings) { SettingsView().environmentObject(monitor) }
            .sheet(isPresented: $showDetail) { UsageDetailView().environmentObject(monitor) }
            .sheet(item: $selected) { (session: PulseState.Session) in SessionDetailView(initial: session) }
    }
}

// MARK: - En-tête

struct Header: View {
    let onSettings: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        HStack {
            CircleButton(symbol: "slider.horizontal.3", label: "Réglages", action: onSettings)
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(PulseStyle.accent)
                Text("Claude Pulse")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(PulseStyle.textPrimary)
            }
            Spacer()
            CircleButton(symbol: "arrow.clockwise", label: "Rafraîchir", action: onRefresh)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        // Fondu vers le haut : le contenu glisse sous les boutons de verre sans gêner le titre.
        .background(
            LinearGradient(
                colors: [PulseStyle.background, PulseStyle.background.opacity(0.85), PulseStyle.background.opacity(0)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        )
    }
}

/// Bouton rond en Liquid Glass (iOS 26) ; bouton blanc flottant sur les versions plus anciennes.
struct CircleButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    @State private var taps = 0

    var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(PulseStyle.textPrimary)
                .frame(width: 44, height: 44)
                .glassCircle()
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
        .accessibilityLabel(label)
    }
}

extension View {
    /// Verre liquide interactif en cercle, ou pastille blanche ombrée avant iOS 26.
    @ViewBuilder
    func glassCircle() -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.interactive(), in: Circle())
        } else {
            background(PulseStyle.floating, in: Circle())
                .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        }
    }

    /// Verre liquide en capsule, ou capsule grise avant iOS 26.
    @ViewBuilder
    func glassCapsule() -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.interactive(), in: Capsule())
        } else {
            background(PulseStyle.cardRaised, in: Capsule())
        }
    }
}

// MARK: - Limites

/// La limite 5 h en grand : chiffre en serif, piste, heure de remise à zéro.
struct LimitHero: View {
    let limit: PulseState.Limit?

    var body: some View {
        let pct = limit?.pct
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(pct.map { "\(Int($0.rounded()))" } ?? "—")
                    .font(.system(size: 56, weight: .regular, design: .serif).monospacedDigit())
                    .foregroundStyle(PulseStyle.textPrimary)
                    .contentTransition(.numericText())
                Text(pct == nil ? "" : "%")
                    .font(.system(size: 26, weight: .regular, design: .serif))
                    .foregroundStyle(PulseStyle.textSecondary)
                Spacer()
                if let pct {
                    Text(levelLabel(pct))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(PulseStyle.gauge(pct))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(PulseStyle.gauge(pct).opacity(0.14), in: Capsule())
                }
            }

            LimitTrack(pct: pct, color: pct.map { PulseStyle.gauge($0) } ?? PulseStyle.textTertiary)

            HStack {
                Text("Limite 5 heures")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(PulseStyle.textPrimary)
                Spacer()
                Text(limit.map { "Remise à zéro \(PulseStyle.resetTime($0.resetDate))" } ?? "Visible avec Pro ou Max")
                    .font(.subheadline)
                    .foregroundStyle(PulseStyle.textSecondary)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(PulseStyle.textTertiary)
            }
        }
        .padding(18)
        .background(PulseStyle.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .sensoryFeedback(trigger: PulseHaptics.level(limit?.pct)) { (old: Int, new: Int) -> SensoryFeedback? in
            old >= 0 && new > old ? .warning : nil
        }
    }

    private func levelLabel(_ pct: Double) -> String {
        switch pct {
        case ..<50: return "Tranquille"
        case ..<75: return "À surveiller"
        case ..<90: return "Bientôt au max"
        default: return "Presque épuisée"
        }
    }
}

struct WeekRow: View {
    let limit: PulseState.Limit?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                RowIcon(symbol: "calendar")
                Text("Limite 7 jours")
                    .foregroundStyle(PulseStyle.textPrimary)
                Spacer()
                Text(limit.map { "\(Int($0.pct.rounded())) %" } ?? "—")
                    .monospacedDigit()
                    .foregroundStyle(limit.map { PulseStyle.gauge($0.pct) } ?? PulseStyle.textSecondary)
            }
            if let limit {
                LimitBar(pct: limit.pct, height: 6)
                    .padding(.leading, 36)
                Text("Remise à zéro \(PulseStyle.resetTime(limit.resetDate))")
                    .font(.caption)
                    .foregroundStyle(PulseStyle.textSecondary)
                    .padding(.leading, 36)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
    }
}

// MARK: - Surveillance

/// Bouton d'action : « Lancer la surveillance » en pêche, puis l'état actif avec « Arrêter ».
struct MonitorCTA: View {
    @EnvironmentObject private var monitor: LiveMonitor
    @State private var busy = false
    @State private var presses = 0

    var body: some View {
        content
            .sensoryFeedback(.impact(weight: .medium), trigger: presses)
            .sensoryFeedback(trigger: monitor.isRunning) { (_: Bool, running: Bool) -> SensoryFeedback? in
                running ? .success : nil
            }
    }

    @ViewBuilder
    private var content: some View {
        if monitor.isRunning {
            HStack(spacing: 12) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(PulseStyle.good)
                    .symbolEffect(.variableColor.iterative, options: .repeating)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Surveillance active")
                        .font(.body.weight(.medium))
                        .foregroundStyle(PulseStyle.textPrimary)
                    if let last = monitor.lastUpdate {
                        Text("Mise à jour \(Text(last, style: .relative))")
                            .font(.caption)
                            .foregroundStyle(PulseStyle.textSecondary)
                    }
                }
                Spacer()
                Button {
                    run { await monitor.stop() }
                } label: {
                    Text("Arrêter")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PulseStyle.textPrimary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .glassCapsule()
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(PulseStyle.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else {
            VStack(spacing: 8) {
                Button {
                    run { await monitor.start() }
                } label: {
                    HStack(spacing: 8) {
                        if busy {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "waveform.path.ecg")
                        }
                        Text("Lancer la surveillance")
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(PulseStyle.peach, in: Capsule())
                    .shadow(color: PulseStyle.peach.opacity(0.35), radius: 12, y: 4)
                }
                .buttonStyle(.plain)
                .disabled(!PulseConfig.isConfigured || busy)
                .opacity(PulseConfig.isConfigured ? 1 : 0.45)

                Text("Live Activity et notifications quand Claude attend ta validation ou a terminé, pendant 8 h.")
                    .font(.caption)
                    .foregroundStyle(PulseStyle.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }
        }
    }

    private func run(_ action: @escaping () async -> Void) {
        guard !busy else { return }
        presses += 1
        busy = true
        Task {
            await action()
            busy = false
        }
    }
}

// MARK: - Sessions

struct SessionCard: View {
    let session: PulseState.Session

    private var estimatedEnd: Date? {
        guard let eta = session.etaSeconds, eta >= 0 else { return nil }
        return Date().addingTimeInterval(TimeInterval(eta))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "terminal")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(PulseStyle.textSecondary)
                Text(session.project)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PulseStyle.textPrimary)
                    .lineLimit(1)
                StatusPill(status: session.status)
                Spacer(minLength: 6)
                Text(Date(timeIntervalSince1970: session.startedAt), style: .timer)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(PulseStyle.textSecondary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 72, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: 6) {
                if let end = estimatedEnd {
                    (Text(PulseStyle.remaining(session.etaSeconds ?? 0)).foregroundStyle(PulseStyle.accent)
                        + Text(" · fin vers \(PulseStyle.clock(end))").foregroundStyle(PulseStyle.textPrimary))
                        .font(.system(size: 22, weight: .regular, design: .serif))
                }
                Text(session.activity)
                    .font(.system(size: 17, design: .serif))
                    .foregroundStyle(PulseStyle.textPrimary)
                    .lineLimit(2)
                if let title = session.title, !title.isEmpty {
                    Text(title)
                        .font(.footnote)
                        .foregroundStyle(PulseStyle.textSecondary)
                        .lineLimit(1)
                }
            }

            if session.stepsTotal > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    SegmentedBar(done: session.stepsDone, total: session.stepsTotal, color: PulseStyle.peach)
                    HStack(spacing: 6) {
                        Text("Étape \(min(session.stepsDone + 1, session.stepsTotal)) sur \(session.stepsTotal)")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(PulseStyle.textPrimary)
                        if !session.currentStep.isEmpty {
                            Text("· \(session.currentStep)")
                                .font(.caption)
                                .foregroundStyle(PulseStyle.textSecondary)
                                .lineLimit(1)
                        }
                    }
                }
            }

            HStack(spacing: 6) {
                MetaChip(symbol: "text.alignleft", text: "Contexte \(session.contextPct) %")
                if session.agents > 0 {
                    MetaChip(symbol: "person.2", text: "\(session.agents) agent\(session.agents > 1 ? "s" : "")")
                }
                if !session.workflow.isEmpty {
                    MetaChip(symbol: "flowchart", text: session.workflow)
                }
                if let model = session.model {
                    MetaChip(symbol: "sparkle", text: model)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(PulseStyle.textTertiary)
            }
        }
        .padding(16)
        .background(PulseStyle.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            if session.status == "waiting" {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(PulseStyle.warn.opacity(0.6), lineWidth: 1.5)
            }
        }
    }
}

struct StatusPill: View {
    let status: String

    var body: some View {
        let color = PulseStyle.color(for: status)
        Text(PulseStyle.label(for: status))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
    }
}

struct RecentRow: View {
    let session: PulseState.Session

    var body: some View {
        HStack(spacing: 12) {
            RowIcon(symbol: PulseStyle.symbol(for: session.status), color: PulseStyle.color(for: session.status))
            VStack(alignment: .leading, spacing: 2) {
                Text(session.project)
                    .foregroundStyle(PulseStyle.textPrimary)
                    .lineLimit(1)
                Text(session.title ?? session.activity)
                    .font(.caption)
                    .foregroundStyle(PulseStyle.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(session.duration)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(PulseStyle.textSecondary)
                Text(Date(timeIntervalSince1970: session.updatedAt), format: .relative(presentation: .named))
                    .font(.caption2)
                    .foregroundStyle(PulseStyle.textTertiary)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
    }
}

// MARK: - Briques

/// Groupe de lignes gris sable aux coins arrondis, sans bordure.
struct RowGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(PulseStyle.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct RowDivider: View {
    var body: some View {
        Rectangle()
            .fill(PulseStyle.separator)
            .frame(height: 0.5)
            .padding(.leading, 52)
    }
}

struct RowIcon: View {
    let symbol: String
    var color: Color = PulseStyle.textPrimary

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .regular))
            .foregroundStyle(color)
            .frame(width: 24)
    }
}

struct InfoRow: View {
    let symbol: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            RowIcon(symbol: symbol)
            Text(title).foregroundStyle(PulseStyle.textPrimary)
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(PulseStyle.textSecondary)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
    }
}

struct SectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(PulseStyle.textSecondary)
            .padding(.horizontal, 4)
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
        .font(.caption2.weight(.medium))
        .foregroundStyle(PulseStyle.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(PulseStyle.cardRaised, in: Capsule())
    }
}

struct EmptyState: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(PulseStyle.peach)
            Text("Aucune session récente")
                .font(.system(size: 20, design: .serif))
                .foregroundStyle(PulseStyle.textPrimary)
            Text("Lance Claude Code sur ton Mac : tes sessions apparaîtront ici.")
                .font(.subheadline)
                .foregroundStyle(PulseStyle.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 36)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .background(PulseStyle.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct NoticeCard: View {
    let symbol: String
    let text: String
    var tint: Color = PulseStyle.warn

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RowIcon(symbol: symbol, color: tint)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(PulseStyle.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

#Preview {
    ContentView().environmentObject(LiveMonitor.shared)
}
