import ActivityKit
import Foundation
import WidgetKit

/// Surveillance sans push Apple : l'app interroge le backend toutes les quelques secondes,
/// met à jour elle-même la Live Activity et envoie des notifications locales.
/// Un son silencieux la garde éveillée en arrière-plan tant que la surveillance tourne.
@MainActor
final class LiveMonitor: ObservableObject {
    static let shared = LiveMonitor()

    @Published private(set) var isRunning = false
    @Published private(set) var state: PulseState? = PulseConfig.cachedState
    @Published private(set) var lastError: String?
    @Published private(set) var lastUpdate: Date?

    /// Rythme d'interrogation du backend (quota gratuit Upstash : voir le README).
    private let activeInterval: Double = 5
    private let idleInterval: Double = 20

    private var activity: Activity<PulseAttributes>?
    private var loop: Task<Void, Never>?
    private var watcher: Task<Void, Never>?
    private let keepAlive = SilentAudio()
    private var knownStatus: [String: String] = [:]
    private var lastContent: PulseAttributes.ContentState?
    private var lastPushed = Date.distantPast

    // MARK: Démarrer / arrêter

    func start() async {
        guard !isRunning else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            lastError = "Active les Activités en direct : Réglages > Claude Pulse."
            return
        }
        await Notifier.requestAuthorization()

        let fresh = try? await PulseAPI.fetchState()
        if let fresh {
            state = fresh
            lastUpdate = Date()
            fresh.sessions.forEach { knownStatus[$0.sid] = $0.status } // pas de notification pour l'existant
        }
        let content = Self.content(from: fresh ?? state)

        // Une Live Activity ne peut être lancée que quand l'app est au premier plan : c'est maintenant.
        do {
            for old in Activity<PulseAttributes>.activities {
                await old.end(nil, dismissalPolicy: .immediate)
            }
            activity = try Activity.request(
                attributes: PulseAttributes(name: "Claude Pulse"),
                content: .init(state: content, staleDate: staleDate())
            )
        } catch {
            lastError = "Impossible de lancer la Live Activity : \(error.localizedDescription)"
            return
        }
        lastContent = content
        lastPushed = Date()
        keepAlive.start()
        isRunning = true
        lastError = nil
        watchActivity()
        loop = Task { [weak self] in await self?.run() }
    }

    func stop() async {
        loop?.cancel()
        loop = nil
        watcher?.cancel()
        watcher = nil
        keepAlive.stop()
        if let activity {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        activity = nil
        isRunning = false
    }

    /// Rafraîchit l'écran de l'app sans lancer la surveillance.
    func refresh() async {
        do {
            state = try await PulseAPI.fetchState()
            lastUpdate = Date()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Boucle

    private func run() async {
        while !Task.isCancelled {
            var delay = idleInterval
            do {
                let fresh = try await PulseAPI.fetchState()
                state = fresh
                lastUpdate = Date()
                lastError = nil
                let changed = notifyTransitions(fresh)
                if changed { WidgetCenter.shared.reloadAllTimelines() }
                await push(Self.content(from: fresh))
                if !fresh.activeSessions.isEmpty { delay = activeInterval }
            } catch {
                lastError = error.localizedDescription
                delay = 15
            }
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }

    private func push(_ content: PulseAttributes.ContentState) async {
        guard let activity else { return }
        // Une mise à jour au moins par minute pour repousser la date de péremption.
        guard content != lastContent || Date().timeIntervalSince(lastPushed) > 60 else { return }
        await activity.update(.init(state: content, staleDate: staleDate()))
        lastContent = content
        lastPushed = Date()
    }

    /// Si l'app est tuée, la Live Activity s'affiche comme périmée au bout de 3 minutes.
    private func staleDate() -> Date { Date().addingTimeInterval(180) }

    private func watchActivity() {
        guard let activity else { return }
        watcher = Task { [weak self] in
            for await phase in activity.activityStateUpdates {
                // Balayée à la main ou fermée par iOS (limite de 8 h) : on arrête tout pour la batterie.
                if phase == .dismissed || phase == .ended {
                    await self?.stop()
                    return
                }
            }
        }
    }

    // MARK: Notifications

    /// Renvoie true si un statut a changé.
    @discardableResult
    private func notifyTransitions(_ fresh: PulseState) -> Bool {
        var changed = false
        for s in fresh.sessions {
            let previous = knownStatus[s.sid]
            knownStatus[s.sid] = s.status
            guard previous != s.status else { continue }
            changed = true
            switch s.status {
            case "waiting":
                Notifier.send(title: "\(s.project) attend ta validation", body: s.activity)
            case "done", "error":
                // Seulement pour une tâche qu'on a vue tourner et qui a duré plus de 30 s.
                guard let previous, ["running", "waiting", "background"].contains(previous),
                      s.updatedAt - s.startedAt >= 30 else { continue }
                if s.status == "done" {
                    Notifier.send(title: "\(s.project) : terminé ✅", body: "En \(s.duration) · \(PulseStyle.cost(s.costUsd))")
                } else {
                    Notifier.send(title: "\(s.project) : erreur", body: s.activity)
                }
            default:
                break
            }
        }
        return changed
    }

    // MARK: Contenu de la Live Activity

    /// La session à afficher : celle qui attend ta validation, sinon la plus récente en cours, sinon la dernière.
    static func focus(_ sessions: [PulseState.Session]) -> PulseState.Session? {
        sessions.first { $0.status == "waiting" } ?? sessions.first { $0.isActive } ?? sessions.first
    }

    static func content(from state: PulseState?) -> PulseAttributes.ContentState {
        let fiveHour = state?.limits.fiveHour.map { Int($0.pct.rounded()) } ?? -1
        let resetsAt = state?.limits.fiveHour?.resetsAt ?? 0
        guard let state, let s = focus(state.sessions) else {
            return .idle(fiveHourPct: fiveHour, fiveHourResetsAt: resetsAt)
        }
        return PulseAttributes.ContentState(
            project: s.project,
            status: s.status,
            activity: s.activity,
            currentStep: s.currentStep,
            stepsDone: s.stepsDone,
            stepsTotal: s.stepsTotal,
            agents: s.agents,
            workflow: s.workflow,
            costUsd: s.costUsd,
            fiveHourPct: fiveHour,
            fiveHourResetsAt: resetsAt,
            startedAt: s.startedAt,
            duration: s.duration,
            otherActive: state.activeSessions.filter { $0.sid != s.sid }.count
        )
    }
}
