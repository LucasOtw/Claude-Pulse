import ActivityKit
import SwiftUI
import WidgetKit

struct PulseLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PulseAttributes.self) { context in
            LockScreenView(state: context.state, isStale: context.isStale)
                .activityBackgroundTint(Color.black)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = context.state
            let color = PulseStyle.color(for: state.status)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        StatusBadge(status: state.status, size: 28)
                        Text(state.project)
                            .font(.headline)
                            .lineLimit(1)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ElapsedText(state: state)
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(color)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 80, alignment: .trailing)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(state.activity)
                            .font(.subheadline)
                            .foregroundStyle(PulseStyle.textSecondary)
                            .lineLimit(1)
                        TaskLine(state: state)
                        LimitFooter(state: state, barHeight: 10)
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
                }
            } compactLeading: {
                Image(systemName: PulseStyle.symbol(for: state.status))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(color)
            } compactTrailing: {
                if state.fiveHourPct >= 0 {
                    Text("\(state.fiveHourPct)%")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(PulseStyle.gauge(Double(state.fiveHourPct)))
                } else if state.isActive {
                    ElapsedText(state: state)
                        .font(.caption.monospacedDigit())
                        .frame(maxWidth: 44)
                }
            } minimal: {
                ZStack {
                    RingGauge(pct: state.fiveHourPct >= 0 ? Double(state.fiveHourPct) : nil, lineWidth: 3)
                    Image(systemName: PulseStyle.symbol(for: state.status))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(color)
                }
                .padding(2)
            }
            .keylineTint(color)
        }
    }
}

/// Chrono qui défile pendant la tâche, durée figée une fois terminée.
struct ElapsedText: View {
    let state: PulseAttributes.ContentState

    var body: some View {
        if state.isActive {
            Text(state.startDate, style: .timer)
        } else if !state.duration.isEmpty {
            Text(state.duration)
        } else {
            Text("—")
        }
    }
}

/// Écran verrouillé : en-tête, tâche en cours, puis la grosse barre de limite 5 h.
struct LockScreenView: View {
    let state: PulseAttributes.ContentState
    let isStale: Bool

    var body: some View {
        let color = PulseStyle.color(for: state.status)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                StatusBadge(status: state.status, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.project)
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(isStale ? "Plus de nouvelles : rouvre Claude Pulse" : state.activity)
                        .font(.subheadline)
                        .foregroundStyle(PulseStyle.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    ElapsedText(state: state)
                        .font(.system(.title3, design: .rounded).weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 90, alignment: .trailing)
                    Text(PulseStyle.label(for: state.status).uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(color)
                }
            }

            if state.stepsTotal > 0 || state.agents > 0 || !state.workflow.isEmpty || state.otherActive > 0 {
                TaskLine(state: state)
            }

            LimitFooter(state: state, barHeight: 14)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }
}

/// Étape en cours, workflow, sous-agents, autres sessions.
struct TaskLine: View {
    let state: PulseAttributes.ContentState

    var body: some View {
        HStack(spacing: 8) {
            if state.stepsTotal > 0 {
                Text("\(min(state.stepsDone + 1, state.stepsTotal))/\(state.stepsTotal)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(PulseStyle.accent)
                Text(state.currentStep.isEmpty ? "Étape en cours" : state.currentStep)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
            } else if !state.workflow.isEmpty {
                Label(state.workflow, systemImage: "flowchart")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if state.agents > 0 {
                Chip(text: "\(state.agents)", symbol: "person.2.fill")
            }
            if state.otherActive > 0 {
                Chip(text: "+\(state.otherActive)", symbol: "rectangle.stack.fill")
            }
        }
    }
}

struct Chip: View {
    let text: String
    let symbol: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            Text(text)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.white.opacity(0.75))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.white.opacity(0.10), in: Capsule())
    }
}

/// Libellé + grosse barre de la limite 5 h.
struct LimitFooter: View {
    let state: PulseAttributes.ContentState
    let barHeight: CGFloat

    var body: some View {
        let known = state.fiveHourPct >= 0
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Limite 5 h")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
                if known {
                    Text("\(state.fiveHourPct) %")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(PulseStyle.gauge(Double(state.fiveHourPct)))
                }
                Spacer()
                if let reset = state.fiveHourResetDate {
                    Text("réinit. \(PulseStyle.resetTime(reset))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(PulseStyle.textTertiary)
                } else if !known {
                    Text("en attente d'un relevé")
                        .font(.caption2)
                        .foregroundStyle(PulseStyle.textTertiary)
                }
            }
            LimitBar(pct: known ? Double(state.fiveHourPct) : nil, height: barHeight)
        }
    }
}

#Preview("Écran verrouillé", as: .content, using: PulseAttributes(name: "Claude Pulse")) {
    PulseLiveActivity()
} contentStates: {
    PulseAttributes.ContentState.preview
    PulseAttributes.ContentState.idle(fiveHourPct: 82, fiveHourResetsAt: Date().addingTimeInterval(3600).timeIntervalSince1970)
}
