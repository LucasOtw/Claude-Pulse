import ActivityKit
import SwiftUI
import WidgetKit

struct PulseLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PulseAttributes.self) { context in
            LockScreenView(state: context.state, isStale: context.isStale)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = context.state
            let color = PulseStyle.color(for: state.status)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(state.project).lineLimit(1)
                    } icon: {
                        Image(systemName: PulseStyle.symbol(for: state.status)).foregroundStyle(color)
                    }
                    .font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ElapsedText(state: state)
                        .font(.headline.monospacedDigit())
                        .multilineTextAlignment(.trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    DetailView(state: state)
                }
            } compactLeading: {
                Image(systemName: PulseStyle.symbol(for: state.status)).foregroundStyle(color)
            } compactTrailing: {
                if state.stepsTotal > 0 {
                    Text("\(state.stepsDone)/\(state.stepsTotal)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(color)
                } else if state.isActive {
                    ElapsedText(state: state)
                        .font(.caption.monospacedDigit())
                        .frame(maxWidth: 44)
                } else if state.fiveHourPct >= 0 {
                    Text("\(state.fiveHourPct)%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(PulseStyle.gauge(Double(state.fiveHourPct)))
                }
            } minimal: {
                Image(systemName: PulseStyle.symbol(for: state.status)).foregroundStyle(color)
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
        } else {
            Text(state.duration)
        }
    }
}

struct LockScreenView: View {
    let state: PulseAttributes.ContentState
    let isStale: Bool

    var body: some View {
        let color = PulseStyle.color(for: state.status)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: PulseStyle.symbol(for: state.status)).foregroundStyle(color)
                Text(state.project).font(.headline).lineLimit(1)
                Text(PulseStyle.label(for: state.status))
                    .font(.caption.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.25), in: Capsule())
                    .foregroundStyle(color)
                Spacer()
                ElapsedText(state: state)
                    .font(.headline.monospacedDigit())
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 80, alignment: .trailing)
            }
            DetailView(state: state)
            if isStale {
                Text("Plus de nouvelles : rouvre Claude Pulse pour relancer la surveillance.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .foregroundStyle(.white)
        .padding()
    }
}

struct DetailView: View {
    let state: PulseAttributes.ContentState

    var body: some View {
        let color = PulseStyle.color(for: state.status)
        VStack(alignment: .leading, spacing: 6) {
            Text(state.activity)
                .font(.subheadline)
                .lineLimit(1)
            if state.stepsTotal > 0 {
                if let progress = state.progress {
                    ProgressView(value: progress).tint(color)
                }
                Text("Étape \(min(state.stepsDone + 1, state.stepsTotal))/\(state.stepsTotal)\(state.currentStep.isEmpty ? "" : " · \(state.currentStep)")")
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(.white.opacity(0.8))
            }
            HStack(spacing: 10) {
                if !state.workflow.isEmpty {
                    Label(state.workflow, systemImage: "flowchart").lineLimit(1)
                }
                if state.agents > 0 {
                    Label("\(state.agents) agent\(state.agents > 1 ? "s" : "")", systemImage: "person.2.fill")
                }
                if state.otherActive > 0 {
                    Text("+\(state.otherActive) session\(state.otherActive > 1 ? "s" : "")")
                }
                Spacer()
                if state.status != "idle" {
                    Text(PulseStyle.cost(state.costUsd))
                }
                if state.fiveHourPct >= 0 {
                    Text("5h \(state.fiveHourPct) %")
                        .foregroundStyle(PulseStyle.gauge(Double(state.fiveHourPct)))
                }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(0.7))
        }
    }
}

#Preview("Écran verrouillé", as: .content, using: PulseAttributes(name: "Claude Pulse")) {
    PulseLiveActivity()
} contentStates: {
    PulseAttributes.ContentState.preview
    PulseAttributes.ContentState.idle(fiveHourPct: 42)
}
