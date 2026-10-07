import ActivityKit
import Foundation

/// Transmet au backend les jetons push qui lui permettent de lancer et de mettre à jour
/// les Live Activities sans que l'app soit ouverte.
@MainActor
final class ActivityManager: ObservableObject {
    static let shared = ActivityManager()

    @Published private(set) var startTokenRegistered = false
    @Published private(set) var lastError: String?

    private var started = false
    private var observed = Set<String>()
    private var lastStartToken: Data?

    func start() {
        guard !started else { return }
        started = true

        Task {
            for await token in Activity<PulseAttributes>.pushToStartTokenUpdates {
                lastStartToken = token
                await register(kind: "start", token: token)
            }
        }
        Task {
            for await activity in Activity<PulseAttributes>.activityUpdates {
                observe(activity)
            }
        }
        Activity<PulseAttributes>.activities.forEach(observe)
    }

    /// À appeler après avoir changé l'URL ou le jeton dans les réglages.
    func resendTokens() async {
        if let lastStartToken { await register(kind: "start", token: lastStartToken) }
        for activity in Activity<PulseAttributes>.activities {
            if let token = activity.pushToken {
                await register(kind: "activity", token: token, sessionId: activity.attributes.sessionId)
            }
        }
    }

    func endAll() async {
        for activity in Activity<PulseAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private func observe(_ activity: Activity<PulseAttributes>) {
        guard observed.insert(activity.id).inserted else { return }
        Task {
            for await token in activity.pushTokenUpdates {
                await register(kind: "activity", token: token, sessionId: activity.attributes.sessionId)
            }
        }
    }

    private func register(kind: String, token: Data, sessionId: String? = nil) async {
        do {
            try await PulseAPI.registerToken(kind: kind, token: token, sessionId: sessionId)
            if kind == "start" { startTokenRegistered = true }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}
