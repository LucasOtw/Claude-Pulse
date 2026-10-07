import ActivityKit
import SwiftUI
import WidgetKit

struct PulseLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PulseAttributes.self) { context in
            LockScreenView(attributes: context.attributes, state: context.state, isStale: context.isStale)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = context.state
            let color = PulseStyle.color(for: state.status)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(context.attributes.project).lineLimit(1)
                    } icon: {
                        Image(systemName: PulseStyle.symbol(for: state.status)).foregroundStyle(color)
                    }
                    .font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ElapsedText(attributes: context.attributes, state: state)
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
                } else {
                    ElapsedText(attributes: context.attributes, state: state)
                        .font(.caption.monospacedDigit())
                        .frame(maxWidth: 44)
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
    let attributes: PulseAttributes
    let state: PulseAttributes.ContentState

    var body: some View {
        if state.isFinished {
            Text(state.duration)
        } else {
            Text(attributes.startDate, style: .timer)
        }
    }
}

struct LockScreenView: View {
    let attributes: PulseAttributes
    let state: PulseAttributes.ContentState
    let isStale: Bool

    var body: some View {
        let color = PulseStyle.color(for: state.status)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: PulseStyle.symbol(for: state.status)).foregroundStyle(color)
                Text(attributes.project).font(.headline).lineLimit(1)
                Text(PulseStyle.label(for: state.status))
                    .font(.caption.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.25), in: Capsule())
                    .foregroundStyle(color)
                Spacer()
                ElapsedText(attributes: attributes, state: state)
                    .font(.headline.monospacedDigit())
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 80, alignment: .trailing)
            }
            DetailView(state: state)
            if isStale {
                Text("Pas de nouvelles depuis un moment…")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
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
                Spacer()
                Text(PulseStyle.cost(state.costUsd))
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

#Preview("Écran verrouillé", as: .content, using: PulseAttributes(sessionId: "1", project: "Studio_Granit", startedAt: Date().addingTimeInterval(-240).timeIntervalSince1970)) {
    PulseLiveActivity()
} contentStates: {
    PulseAttributes.ContentState.preview
}
