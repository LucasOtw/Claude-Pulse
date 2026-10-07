import ActivityKit
import SwiftUI
import WidgetKit

/// Live Activity façon suivi de course : marque, grand titre, détail précis,
/// étapes en segments et piste de la limite 5 h. Toujours en noir.
struct PulseLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PulseAttributes.self) { context in
            LockScreenView(state: context.state, isStale: context.isStale)
                .activityTheme(context.state.theme)
        } dynamicIsland: { context in
            let state = context.state
            let color = PulseStyle.color(for: state.status)
            let symbol = state.hasApproval ? "hand.raised.fill" : PulseStyle.symbol(for: state.status)
            let tint: Color = state.hasApproval ? PulseStyle.warn : color
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Brand(project: nil)
                        .padding(.leading, 6)
                        .padding(.top, 2)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(state.project)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(PulseStyle.textSecondary)
                        .lineLimit(1)
                        .padding(.trailing, 6)
                        .padding(.top, 2)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if state.hasApproval {
                        ApprovalBlock(state: state, compact: true)
                            .padding(.horizontal, 6)
                            .environment(\.colorScheme, .dark)
                    } else {
                        tracking(state)
                    }
                }
            } compactLeading: {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(tint)
            } compactTrailing: {
                compactTrailing(state, color: color)
            } minimal: {
                ZStack {
                    RingGauge(pct: state.fiveHourPct >= 0 ? Double(state.fiveHourPct) : nil, lineWidth: 3)
                    Image(systemName: symbol)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(tint)
                }
                .padding(2)
                .environment(\.colorScheme, .dark)
            }
            .keylineTint(tint)
        }
    }

    private func tracking(_ state: PulseAttributes.ContentState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Headline(state: state, size: 19)
            Subline(state: state)
            if state.stepsTotal > 0 {
                SegmentedBar(done: state.stepsDone, total: state.stepsTotal)
            }
            LimitRow(state: state)
        }
        .padding(.horizontal, 6)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private func compactTrailing(_ state: PulseAttributes.ContentState, color: Color) -> some View {
        if state.hasApproval {
            Text("?")
                .font(.caption.weight(.heavy))
                .foregroundStyle(PulseStyle.warn)
        } else if let end = state.estimatedEnd {
            Text(timerInterval: Date.now...max(end, Date.now), countsDown: true, showsHours: false)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
                .frame(maxWidth: 44)
        } else if state.fiveHourPct >= 0 {
            Text("\(state.fiveHourPct)%")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(PulseStyle.gauge(Double(state.fiveHourPct)))
        }
    }
}

// MARK: - Écran verrouillé

extension View {
    /// Noir, blanc, ou apparence de l'écran verrouillé (« auto »).
    @ViewBuilder
    func activityTheme(_ theme: String) -> some View {
        switch theme {
        case "light":
            environment(\.colorScheme, .light)
                .activityBackgroundTint(Color.white)
                .activitySystemActionForegroundColor(.black)
        case "auto":
            activityBackgroundTint(PulseStyle.background)
        default:
            environment(\.colorScheme, .dark)
                .activityBackgroundTint(Color.black)
                .activitySystemActionForegroundColor(.white)
        }
    }
}

struct LockScreenView: View {
    let state: PulseAttributes.ContentState
    let isStale: Bool

    var body: some View {
        if state.hasApproval {
            // Demande d'autorisation : elle prend la place du suivi, la limite reste en bas.
            VStack(alignment: .leading, spacing: 10) {
                Brand(project: nil)
                ApprovalBlock(state: state, compact: false)
                LimitRow(state: state)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        } else {
            tracking
        }
    }

    private var tracking: some View {
        VStack(alignment: .leading, spacing: 9) {
            Brand(project: state.project)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Headline(state: state, size: 22)
                Spacer(minLength: 4)
                if state.isActive {
                    Text(state.startDate, style: .timer)
                        .font(.subheadline.weight(.medium).monospacedDigit())
                        .foregroundStyle(PulseStyle.textTertiary)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 70, alignment: .trailing)
                }
            }

            if isStale {
                Text("Plus de nouvelles : rouvre Claude Pulse")
                    .font(.subheadline)
                    .foregroundStyle(PulseStyle.warn)
                    .lineLimit(1)
            } else {
                Subline(state: state)
            }

            if state.stepsTotal > 0 {
                SegmentedBar(done: state.stepsDone, total: state.stepsTotal)
            }

            LimitRow(state: state)
                .padding(.top, 2)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}

/// Demande d'autorisation avec ses deux boutons (exécutés sans ouvrir l'app).
struct ApprovalBlock: View {
    let state: PulseAttributes.ContentState
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            HStack(spacing: 6) {
                Image(systemName: "hand.raised.fill")
                    .foregroundStyle(PulseStyle.warn)
                Text("Autoriser ?")
                    .font(.system(size: compact ? 16 : 19, weight: .bold, design: .rounded))
                    .foregroundStyle(PulseStyle.textPrimary)
                Text(state.approvalTitle)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(PulseStyle.textSecondary)
                    .lineLimit(1)
            }
            Text(state.approvalText)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(PulseStyle.textPrimary)
                .lineLimit(compact ? 1 : 2)
            HStack(spacing: 8) {
                Button(intent: DecideApprovalIntent(approvalID: state.approvalId, allow: false)) {
                    Text("Refuser")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(PulseStyle.track, in: Capsule())
                        .foregroundStyle(PulseStyle.textPrimary)
                }
                .buttonStyle(.plain)
                if state.approvalDanger {
                    Text("Sensible : à valider sur le Mac")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PulseStyle.warn)
                        .frame(maxWidth: .infinity)
                } else {
                    Button(intent: DecideApprovalIntent(approvalID: state.approvalId, allow: true)) {
                        Text("Autoriser")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(PulseStyle.peach, in: Capsule())
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// « Claude Pulse » à gauche, projet à droite (comme la plaque d'immatriculation chez Uber).
struct Brand: View {
    let project: String?

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(PulseStyle.accent)
            (Text("Claude ").foregroundStyle(PulseStyle.textPrimary) + Text("Pulse").foregroundStyle(PulseStyle.accent))
                .font(.system(size: 15, weight: .bold, design: .rounded))
            if let project {
                Spacer(minLength: 8)
                Text(project)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(PulseStyle.textSecondary)
                    .lineLimit(1)
            }
        }
    }
}

/// Le grand titre : temps restant, demande de validation, ou fin.
struct Headline: View {
    let state: PulseAttributes.ContentState
    let size: CGFloat

    var body: some View {
        title
            .font(.system(size: size, weight: .bold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    private var title: Text {
        let white = PulseStyle.textPrimary
        switch state.status {
        case "waiting":
            return Text("Attend ta validation").foregroundStyle(PulseStyle.warn)
        case "done":
            return Text("Terminé").foregroundStyle(PulseStyle.good)
                + Text(state.duration.isEmpty ? "" : " en \(state.duration)").foregroundStyle(white)
        case "error":
            return Text("Erreur").foregroundStyle(PulseStyle.critical)
        case "idle":
            return Text("Aucune tâche en cours").foregroundStyle(white)
        default:
            if let end = state.estimatedEnd {
                let seconds = Int(end.timeIntervalSinceNow)
                return Text(PulseStyle.remaining(seconds)).foregroundStyle(PulseStyle.accent)
                    + Text(" · fin vers \(PulseStyle.clock(end))").foregroundStyle(white)
            }
            if !state.currentStep.isEmpty {
                return Text(state.currentStep).foregroundStyle(white)
            }
            if state.status == "background" {
                return Text("En arrière-plan").foregroundStyle(PulseStyle.info)
            }
            return Text("Claude travaille").foregroundStyle(white)
        }
    }
}

/// Ce que fait Claude précisément, préfixé de l'étape en cours.
struct Subline: View {
    let state: PulseAttributes.ContentState

    var body: some View {
        HStack(spacing: 6) {
            if state.stepsTotal > 0 && state.isActive {
                Text("\(min(state.stepsDone + 1, state.stepsTotal))/\(state.stepsTotal)")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(PulseStyle.accent)
            }
            Text(state.activity)
                .font(.subheadline)
                .foregroundStyle(PulseStyle.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if state.agents > 0 {
                Label("\(state.agents)", systemImage: "person.2.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PulseStyle.textTertiary)
            }
            if state.otherActive > 0 {
                Text("+\(state.otherActive)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(PulseStyle.textTertiary)
            }
        }
    }
}

/// « 5 h » — piste — « 10 % · 14:00 »
struct LimitRow: View {
    let state: PulseAttributes.ContentState

    var body: some View {
        let known = state.fiveHourPct >= 0
        let pct = Double(state.fiveHourPct)
        HStack(spacing: 10) {
            Text("5 h")
                .font(.caption.weight(.bold))
                .foregroundStyle(PulseStyle.textSecondary)
            LimitTrack(pct: known ? pct : nil, color: known ? PulseStyle.gauge(pct) : PulseStyle.textTertiary)
            VStack(alignment: .trailing, spacing: 0) {
                Text(known ? "\(state.fiveHourPct) %" : "—")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(known ? PulseStyle.gauge(pct) : PulseStyle.textTertiary)
                if let reset = state.fiveHourResetDate {
                    Text(PulseStyle.clock(reset))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(PulseStyle.textTertiary)
                }
            }
            .frame(minWidth: 38, alignment: .trailing)
        }
    }
}

#Preview("Écran verrouillé", as: .content, using: PulseAttributes(name: "Claude Pulse")) {
    PulseLiveActivity()
} contentStates: {
    PulseAttributes.ContentState.preview
    PulseAttributes.ContentState.idle(fiveHourPct: 82, fiveHourResetsAt: Date().addingTimeInterval(3600).timeIntervalSince1970)
}
