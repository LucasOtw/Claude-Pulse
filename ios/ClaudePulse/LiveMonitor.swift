import ActivityKit
import Foundation
import WidgetKit

/// Surveillance sans push Apple : l'app interroge le backend toutes les quelques secondes,
/// met à jour elle-même la Live Activity et envoie des notifications locales.
/// Un son silencieux et la localisation en arrière-plan la gardent éveillée tant que la surveillance tourne.
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
    private let location = LocationKeepAlive()
    private var knownStatus: [String: String] = [:]
    private var lastContent: PulseAttributes.ContentState?
    private var lastPushed = Date.distantPast
    private var resuming = false
    private var knownApprovals = Set<String>()
    private var seededApprovals = false
    /// Une limite atteinte arrête toutes les sessions d'un coup : une seule notification d'erreur par 10 min.
    private var lastErrorNotice = Date.distantPast

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
        startKeepAlive()
        isRunning = true
        lastError = nil
        watchActivity()
        loop = Task { [weak self] in await self?.run() }
    }

    /// À chaque retour au premier plan (et au lancement) : si une Live Activity est déjà affichée,
    /// on la reprend et on la met à jour tout de suite. Sans ça, une app relancée par iOS ou Xcode
    /// laissait l'activité figée sur « Mise à jour en pause ».
    func resume() async {
        guard !resuming else { return }
        resuming = true
        defer { resuming = false }
        if isRunning {
            startKeepAlive() // un appel ou une autre app a pu couper le son silencieux
            await tick()
            if loop == nil { loop = Task { [weak self] in await self?.run() } }
            return
        }
        guard let existing = Activity<PulseAttributes>.activities.first(where: {
            $0.activityState == .active || $0.activityState == .stale
        }) else { return }
        activity = existing
        lastContent = existing.content.state
        if knownStatus.isEmpty, let state {
            state.sessions.forEach { knownStatus[$0.sid] = $0.status } // pas de notification pour l'existant
        }
        startKeepAlive()
        isRunning = true
        watchActivity()
        await tick()
        loop = Task { [weak self] in await self?.run() }
    }

    /// Change l'apparence de la Live Activity en cours, sans attendre le prochain relevé.
    func setTheme(_ theme: PulseConfig.ActivityTheme) async {
        PulseConfig.activityTheme = theme
        objectWillChange.send()
        guard var content = lastContent else { return }
        content.theme = theme.rawValue
        await push(content)
    }

    func stop() async {
        loop?.cancel()
        loop = nil
        watcher?.cancel()
        watcher = nil
        keepAlive.stop()
        location.stop()
        if let activity {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        activity = nil
        isRunning = false
    }

    /// Garde l'app éveillée écran verrouillé. À lancer au premier plan (iOS refuse ensuite).
    private func startKeepAlive() {
        keepAlive.start()
        if PulseConfig.backgroundLocation { location.start() } else { location.stop() }
    }

    func setBackgroundLocation(_ on: Bool) {
        PulseConfig.backgroundLocation = on
        objectWillChange.send()
        guard isRunning else { return }
        if on { location.start() } else { location.stop() }
    }

    /// Rafraîchit l'écran de l'app sans lancer la surveillance.
    func refresh() async {
        do {
            let fresh = try await PulseAPI.fetchState()
            state = fresh
            lastUpdate = Date()
            lastError = nil
            handle(fresh)
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Boucle

    private func run() async {
        while !Task.isCancelled {
            let delay = await tick()
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }

    /// Un relevé : état du backend, notifications, Live Activity. Renvoie le délai avant le suivant.
    @discardableResult
    private func tick() async -> Double {
        if isRunning { keepAlive.ensurePlaying() }
        do {
            let fresh = try await PulseAPI.fetchState()
            state = fresh
            lastUpdate = Date()
            lastError = nil
            handle(fresh)
            await push(Self.content(from: fresh))
            return fresh.activeSessions.isEmpty ? idleInterval : activeInterval
        } catch {
            lastError = error.localizedDescription
            return 15
        }
    }

    private func push(_ content: PulseAttributes.ContentState) async {
        guard let activity else { return }
        // Une mise à jour au moins par minute pour repousser la date de péremption.
        let due = Date().timeIntervalSince(lastPushed) > 60 || activity.activityState == .stale
        guard content != lastContent || due else { return }
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
        let local = fresh.ntfy != true // sinon le serveur envoie déjà ces notifications via ntfy
        for s in fresh.sessions {
            let previous = knownStatus[s.sid]
            knownStatus[s.sid] = s.status
            guard previous != s.status else { continue }
            changed = true
            guard local else { continue }
            switch s.status {
            case "waiting":
                Notifier.send(title: "\(s.project) · Accord nécessaire", body: "Claude attend ta réponse dans le terminal.")
            case "done", "error":
                // Seulement pour une tâche qu'on a vue tourner et qui a duré plus de 30 s.
                guard let previous, ["running", "waiting", "background"].contains(previous),
                      s.updatedAt - s.startedAt >= 30 else { continue }
                if s.status == "done" {
                    Notifier.send(
                        title: "\(s.project) · Terminé en \(s.duration)",
                        body: s.summary ?? "Claude a fini et attend ta prochaine demande."
                    )
                } else {
                    guard Date().timeIntervalSince(lastErrorNotice) > 600 else { continue }
                    lastErrorNotice = Date()
                    Notifier.send(title: "\(s.project) · Arrêt sur erreur", body: "\(s.activity)\nRelance la tâche depuis le terminal.")
                }
            default:
                break
            }
        }
        return changed
    }

    /// Limite 5 h à 80 % : notification tout de suite, et une autre programmée à la remise à zéro
    /// (iOS la délivre même si l'app est fermée entre-temps). Une seule fois par fenêtre.
    private func limitAlerts(_ fresh: PulseState) {
        guard fresh.ntfy != true, let limit = fresh.limits.fiveHour, limit.pct >= 80 else { return }
        let key = "alert80-\(Int(limit.resetsAt))"
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: key) else { return }
        defaults.set(true, forKey: key)
        let pct = Int(limit.pct.rounded())
        Notifier.send(
            title: "Limite de 5 h utilisée à \(pct) %",
            body: "Il te reste \(max(0, 100 - pct)) % jusqu'à la remise à zéro à \(PulseStyle.clock(limit.resetDate))."
        )
        Notifier.schedule(
            id: "reset-\(Int(limit.resetsAt))",
            title: "Limite de 5 h remise à zéro",
            body: "Ta limite repart de zéro : tu peux relancer Claude Code.",
            at: limit.resetDate
        )
    }

    /// Nouvelle demande d'autorisation (validation à distance) : notification locale.
    private func approvalAlerts(_ fresh: PulseState) {
        let pending = fresh.pendingApprovals
        defer { knownApprovals = Set(pending.map(\.id)) }
        guard fresh.ntfy != true, !knownApprovals.isEmpty || seededApprovals else {
            seededApprovals = true
            return
        }
        for a in pending where !knownApprovals.contains(a.id) {
            Notifier.send(
                title: "\(a.project) · Autoriser \(a.tool) ?",
                body: a.text + (a.danger ? "\nCommande sensible : seul le Mac peut l'autoriser." : "\nRéponds depuis l'app ou la Live Activity.")
            )
        }
    }

    /// Tout ce qu'un relevé déclenche, que la surveillance tourne ou non.
    private func handle(_ fresh: PulseState) {
        if notifyTransitions(fresh) { WidgetCenter.shared.reloadAllTimelines() }
        limitAlerts(fresh)
        approvalAlerts(fresh)
    }

    // MARK: Validation à distance

    func decide(_ approval: PulseState.Approval, allow: Bool) async {
        do {
            try await PulseAPI.decide(id: approval.id, allow: allow)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        if isRunning { await tick() } else { await refresh() }
    }

    func setRemote(_ on: Bool) async {
        do {
            try await PulseAPI.setRemote(on)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        if isRunning { await tick() } else { await refresh() }
    }

    // MARK: Contenu de la Live Activity

    /// La session à afficher : celle qui attend ta validation, sinon la plus récente en cours, sinon la dernière.
    static func focus(_ sessions: [PulseState.Session]) -> PulseState.Session? {
        sessions.first { $0.status == "waiting" } ?? sessions.first { $0.isActive } ?? sessions.first
    }

    /// Fin estimée arrondie à 30 s, pour ne pas redessiner la Live Activity à chaque relevé.
    static func estimatedEnd(_ s: PulseState.Session) -> Double {
        guard let eta = s.etaSeconds, eta >= 0, s.isActive else { return 0 }
        return ((Date().timeIntervalSince1970 + Double(eta)) / 30).rounded() * 30
    }

    static func content(from state: PulseState?) -> PulseAttributes.ContentState {
        let fiveHour = state?.limits.fiveHour.map { Int($0.pct.rounded()) } ?? -1
        let resetsAt = state?.limits.fiveHour?.resetsAt ?? 0
        let approval = state?.pendingApprovals.first
        guard let state, let s = focus(state.sessions) else {
            var idle = PulseAttributes.ContentState.idle(fiveHourPct: fiveHour, fiveHourResetsAt: resetsAt)
            idle.approvalId = approval?.id ?? ""
            idle.approvalTitle = approval.map { "\($0.project) · \($0.tool)" } ?? ""
            idle.approvalText = approval?.text ?? ""
            idle.approvalDanger = approval?.danger ?? false
            return idle
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
            estimatedEndAt: Self.estimatedEnd(s),
            fiveHourPct: fiveHour,
            fiveHourResetsAt: resetsAt,
            startedAt: s.startedAt,
            duration: s.duration,
            otherActive: state.activeSessions.filter { $0.sid != s.sid }.count,
            theme: PulseConfig.activityTheme.rawValue,
            approvalId: approval?.id ?? "",
            approvalTitle: approval.map { "\($0.project) · \($0.tool)" } ?? "",
            approvalText: approval?.text ?? "",
            approvalDanger: approval?.danger ?? false
        )
    }
}
