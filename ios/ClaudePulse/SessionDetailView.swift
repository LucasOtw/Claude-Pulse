import SwiftUI

/// Détail d'une session en cours : temps restant, contexte, étapes, sous-agents, journal, tokens.
/// Se rafraîchit toute seule tant qu'elle est ouverte.
struct SessionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let initial: PulseState.Session
    @State private var detail: SessionDetail?
    @State private var error: String?

    private var session: PulseState.Session { detail?.session ?? initial }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                contextCard

                if let detail {
                    if !detail.steps.isEmpty { stepsSection(detail.steps) }
                    if !detail.agents.isEmpty { agentsSection(detail.agents) }
                    if let wf = detail.workflow, !wf.name.isEmpty { workflowSection(wf) }
                    if !detail.log.isEmpty { logSection(detail.log) }
                    if let t = detail.tokens { tokensSection(t) }
                } else if let error {
                    NoticeCard(symbol: "exclamationmark.triangle", text: error, tint: PulseStyle.critical)
                } else {
                    ProgressView().tint(PulseStyle.accent).frame(maxWidth: .infinity).padding(.top, 24)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .animation(.snappy, value: detail?.agents.map(\.status))
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            ZStack {
                VStack(spacing: 1) {
                    Text(session.project)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(PulseStyle.textPrimary)
                        .lineLimit(1)
                    if let title = session.title, !title.isEmpty {
                        Text(title)
                            .font(.caption)
                            .foregroundStyle(PulseStyle.textSecondary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 60)
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
        .tint(PulseStyle.accent)
        .task {
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }
        }
    }

    private func load() async {
        do {
            detail = try await PulseAPI.fetchSession(initial.sid)
            error = nil
        } catch {
            if detail == nil { self.error = error.localizedDescription }
        }
    }

    // MARK: En-tête : où en est la tâche

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                StatusPill(status: session.status)
                Spacer()
                if session.isActive {
                    (Text("depuis ") + Text(Date(timeIntervalSince1970: session.startedAt), style: .timer))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(PulseStyle.textSecondary)
                } else {
                    Text(session.duration)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(PulseStyle.textSecondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                if let eta = session.etaSeconds, eta >= 0, session.isActive {
                    (Text(PulseStyle.remaining(eta)).foregroundStyle(PulseStyle.accent)
                        + Text(" restantes").foregroundStyle(PulseStyle.textPrimary))
                        .font(.system(size: 32, weight: .regular, design: .serif))
                    Text("Fin estimée vers \(PulseStyle.clock(Date().addingTimeInterval(TimeInterval(eta))))")
                        .font(.subheadline)
                        .foregroundStyle(PulseStyle.textSecondary)
                } else {
                    Text(headline)
                        .font(.system(size: 30, weight: .regular, design: .serif))
                        .foregroundStyle(PulseStyle.textPrimary)
                }
            }

            Text(session.activity)
                .font(.system(size: 17, design: .serif))
                .foregroundStyle(PulseStyle.textPrimary.opacity(0.85))

            if session.stepsTotal > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    SegmentedBar(done: session.stepsDone, total: session.stepsTotal, color: PulseStyle.peach, height: 6)
                    Text("Étape \(min(session.stepsDone + 1, session.stepsTotal)) sur \(session.stepsTotal)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PulseStyle.textSecondary)
                }
            }

            if session.isActive && (session.etaSeconds ?? -1) < 0 {
                Text("Le temps restant s'affiche quand Claude a fait une liste d'étapes et en a terminé au moins une.")
                    .font(.caption)
                    .foregroundStyle(PulseStyle.textTertiary)
            }
        }
        .padding(18)
        .background(PulseStyle.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var headline: String {
        switch session.status {
        case "waiting": return "Attend ta validation"
        case "done": return "Terminé en \(session.duration)"
        case "error": return "Erreur"
        case "background": return "En arrière-plan"
        case "idle": return "Inactif"
        default: return "Claude travaille"
        }
    }

    // MARK: Contexte

    private var contextCard: some View {
        let pct = Double(session.contextPct)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Contexte")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PulseStyle.textPrimary)
                Spacer()
                Text("\(session.contextPct) %")
                    .font(.system(size: 24, weight: .regular, design: .serif).monospacedDigit())
                    .foregroundStyle(PulseStyle.gauge(pct))
            }
            LimitBar(pct: pct, height: 8)
            HStack(spacing: 6) {
                if let model = session.model { MetaChip(symbol: "sparkle", text: model) }
                if session.agents > 0 {
                    MetaChip(symbol: "person.2", text: "\(session.agents) sous-agent\(session.agents > 1 ? "s" : "") actif\(session.agents > 1 ? "s" : "")")
                }
                Spacer(minLength: 0)
            }
            Text("Part de la mémoire de travail de Claude déjà remplie. Proche du maximum, Claude Code résume la conversation pour continuer.")
                .font(.caption)
                .foregroundStyle(PulseStyle.textTertiary)
        }
        .padding(18)
        .background(PulseStyle.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    // MARK: Étapes

    private func stepsSection(_ steps: [SessionDetail.Step]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: "Étapes")
            RowGroup {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    if index > 0 { RowDivider() }
                    HStack(alignment: .top, spacing: 12) {
                        stepIcon(step.status)
                            .frame(width: 24)
                        Text(step.text)
                            .font(step.status == "in_progress" ? .system(size: 16, weight: .medium, design: .serif) : .body)
                            .foregroundStyle(step.status == "completed" ? PulseStyle.textSecondary : PulseStyle.textPrimary)
                            .strikethrough(step.status == "completed", color: PulseStyle.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    @ViewBuilder
    private func stepIcon(_ status: String) -> some View {
        switch status {
        case "completed":
            Image(systemName: "checkmark.circle.fill").foregroundStyle(PulseStyle.good)
        case "in_progress":
            Image(systemName: "circle.dotted.circle")
                .foregroundStyle(PulseStyle.peach)
                .symbolEffect(.pulse, options: .repeating)
        default:
            Image(systemName: "circle").foregroundStyle(PulseStyle.textTertiary)
        }
    }

    // MARK: Sous-agents

    private func agentsSection(_ agents: [SessionDetail.Agent]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: "Sous-agents")
            RowGroup {
                ForEach(Array(agents.enumerated()), id: \.element.id) { index, agent in
                    if index > 0 { RowDivider() }
                    AgentRow(agent: agent)
                }
            }
        }
    }

    // MARK: Workflow

    private func workflowSection(_ wf: SessionDetail.Workflow) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: "Workflow")
            VStack(alignment: .leading, spacing: 10) {
                Label(wf.name, systemImage: "flowchart")
                    .font(.body.weight(.medium))
                    .foregroundStyle(PulseStyle.textPrimary)
                if !wf.phases.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(wf.phases.enumerated()), id: \.offset) { index, phase in
                            if index > 0 {
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(PulseStyle.textTertiary)
                            }
                            Text(phase)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(PulseStyle.textSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(PulseStyle.cardRaised, in: Capsule())
                        }
                    }
                }
                Text("Claude Code ne signale pas la phase en cours : on voit les phases prévues et les sous-agents actifs.")
                    .font(.caption)
                    .foregroundStyle(PulseStyle.textTertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PulseStyle.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    // MARK: Journal

    private func logSection(_ log: [SessionDetail.LogLine]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: "Activité récente")
            RowGroup {
                ForEach(Array(log.prefix(12).enumerated()), id: \.offset) { index, line in
                    if index > 0 { RowDivider() }
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(PulseStyle.clock(line.date))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(PulseStyle.textTertiary)
                            .frame(width: 40, alignment: .leading)
                        Text(line.text)
                            .font(.subheadline)
                            .foregroundStyle(index == 0 ? PulseStyle.textPrimary : PulseStyle.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    // MARK: Tokens

    private func tokensSection(_ t: SessionDetail.Tokens) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: "Cette session")
            RowGroup {
                InfoRow(symbol: "number", title: "Tokens", value: PulseStyle.tokens(t.tokens))
                RowDivider()
                InfoRow(symbol: "arrow.up.circle", title: "Écrits par Claude", value: PulseStyle.tokens(t.output))
                RowDivider()
                InfoRow(symbol: "dollarsign.circle", title: "Équivalent API", value: PulseStyle.dollars(t.costUsd))
            }
            Footnote("Mis à jour à chaque fin de tour de Claude.")
        }
    }
}

private struct AgentRow: View {
    let agent: SessionDetail.Agent

    var body: some View {
        let running = agent.status == "running"
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: running ? "person.crop.circle.badge.clock" : "person.crop.circle.badge.checkmark")
                .font(.system(size: 18))
                .foregroundStyle(running ? PulseStyle.peach : PulseStyle.good)
                .symbolEffect(.pulse, options: .repeating, isActive: running)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(agent.type)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PulseStyle.textPrimary)
                    if !agent.description.isEmpty {
                        Text(agent.description)
                            .font(.subheadline)
                            .foregroundStyle(PulseStyle.textSecondary)
                            .lineLimit(1)
                    }
                }
                Text(running ? (agent.activity.isEmpty ? "Travaille…" : agent.activity) : "Terminé en \(PulseStyle.shortDuration(agent.seconds))")
                    .font(.system(size: 15, design: .serif))
                    .foregroundStyle(running ? PulseStyle.textPrimary : PulseStyle.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            if running {
                Text(agent.startDate, style: .timer)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(PulseStyle.textSecondary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 56, alignment: .trailing)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }
}
