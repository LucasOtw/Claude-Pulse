import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var monitor: LiveMonitor
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            List {
                if !PulseConfig.isConfigured {
                    Section {
                        Label("Lance ios/setup.sh avec l'URL du backend et ton PULSE_TOKEN, puis recompile.",
                              systemImage: "wrench.and.screwdriver")
                    }
                }

                MonitorSection()

                if let error = monitor.lastError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                if let state = monitor.state {
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
                }
            }
            .navigationTitle("Claude Pulse")
            .toolbar {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
            }
            .refreshable { await monitor.refresh() }
            .task { await monitor.refresh() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active && !monitor.isRunning { Task { await monitor.refresh() } }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }
}

struct MonitorSection: View {
    @EnvironmentObject private var monitor: LiveMonitor

    var body: some View {
        Section {
            if monitor.isRunning {
                Label("Surveillance active", systemImage: "dot.radiowaves.left.and.right")
                    .foregroundStyle(.green)
                if let last = monitor.lastUpdate {
                    Text("Dernière mise à jour \(Text(last, style: .relative))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Arrêter la surveillance", role: .destructive) {
                    Task { await monitor.stop() }
                }
            } else {
                Button {
                    Task { await monitor.start() }
                } label: {
                    Label("Lancer la surveillance", systemImage: "play.circle.fill")
                        .font(.headline)
                }
                .disabled(!PulseConfig.isConfigured)
            }
        } footer: {
            Text("Affiche une Live Activity sur l'écran verrouillé et dans la Dynamic Island, et te notifie quand Claude attend ta validation ou a terminé. Elle reste active jusqu'à 8 h (limite d'iOS) ; balaie-la pour l'arrêter.")
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
    ContentView().environmentObject(LiveMonitor.shared)
}
