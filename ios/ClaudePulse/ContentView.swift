import SwiftUI
import WidgetKit

struct ContentView: View {
    @EnvironmentObject private var activities: ActivityManager
    @Environment(\.scenePhase) private var scenePhase

    @State private var state: PulseState? = PulseConfig.cachedState
    @State private var errorMessage: String?
    @State private var showSettings = !PulseConfig.isConfigured

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                if let state {
                    Section("Limites d'abonnement") {
                        LimitRow(title: "5 heures", limit: state.limits.fiveHour)
                        LimitRow(title: "7 jours", limit: state.limits.sevenDay)
                    }

                    Section("Aujourd'hui") {
                        LabeledContent("Coût estimé", value: PulseStyle.cost(state.today.costUsd))
                        LabeledContent("Sessions", value: "\(state.today.sessions)")
                    }

                    Section("Sessions récentes") {
                        if state.sessions.isEmpty {
                            Text("Aucune session ces 6 dernières heures")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(state.sessions) { SessionRow(session: $0) }
                    }
                } else if PulseConfig.isConfigured {
                    ProgressView()
                } else {
                    Text("Configure le backend dans les réglages ⚙️")
                }
            }
            .navigationTitle("Claude Pulse")
            .toolbar {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
            }
            .refreshable { await load() }
            .task { await load() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await load() } }
            }
            .sheet(isPresented: $showSettings, onDismiss: { Task { await load() } }) {
                SettingsView().environmentObject(activities)
            }
        }
    }

    private func load() async {
        guard PulseConfig.isConfigured else { return }
        do {
            state = try await PulseAPI.fetchState()
            errorMessage = nil
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct LimitRow: View {
    let title: String
    let limit: PulseState.Limit?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(limit.map { "\(Int($0.pct.rounded())) %" } ?? "—")
                    .monospacedDigit()
                    .foregroundStyle(limit.map { PulseStyle.gauge($0.pct) } ?? .secondary)
            }
            if let limit {
                ProgressView(value: min(limit.pct, 100), total: 100)
                    .tint(PulseStyle.gauge(limit.pct))
                Text("Remise à zéro dans \(Text(limit.resetDate, style: .relative))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Disponible avec un abonnement Pro ou Max, après ton premier message.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct SessionRow: View {
    let session: PulseState.Session

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: PulseStyle.symbol(for: session.status))
                .foregroundStyle(PulseStyle.color(for: session.status))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(session.project).font(.headline)
                    Spacer()
                    Text(PulseStyle.cost(session.costUsd))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if let title = session.title, !title.isEmpty {
                    Text(title).font(.subheadline).foregroundStyle(.secondary)
                }
                Text(session.isActive ? session.activity : PulseStyle.label(for: session.status))
                    .font(.subheadline)
                if session.stepsTotal > 0 {
                    ProgressView(value: Double(session.stepsDone), total: Double(session.stepsTotal))
                        .tint(PulseStyle.color(for: session.status))
                    Text("\(session.stepsDone)/\(session.stepsTotal) · \(session.currentStep)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 10) {
                    if !session.workflow.isEmpty { Label(session.workflow, systemImage: "flowchart") }
                    if session.agents > 0 { Label("\(session.agents)", systemImage: "person.2.fill") }
                    Label("\(session.contextPct) %", systemImage: "text.alignleft")
                    Label(session.duration, systemImage: "clock")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ContentView().environmentObject(ActivityManager.shared)
}
