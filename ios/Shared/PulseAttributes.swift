import ActivityKit
import Foundation

/// Données de la Live Activity.
/// ⚠️ Les noms des champs doivent correspondre exactement à ce qu'envoie le backend
/// (backend/lib/state.js : `attributes()` et `contentState()`).
struct PulseAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// running | waiting | background | done | error
        var status: String
        var activity: String
        var currentStep: String
        var stepsDone: Int
        var stepsTotal: Int
        var agents: Int
        var workflow: String
        var costUsd: Double
        var contextPct: Int
        /// -1 si inconnu (pas d'abonnement Pro/Max ou pas encore de relevé)
        var fiveHourPct: Int
        /// Durée figée envoyée par le backend, ex. « 12 min »
        var duration: String
    }

    var sessionId: String
    var project: String
    /// Secondes Unix (pas de `Date` : ActivityKit décode les dates dans un format peu pratique).
    var startedAt: Double

    var startDate: Date { Date(timeIntervalSince1970: startedAt) }
}

extension PulseAttributes.ContentState {
    var progress: Double? {
        stepsTotal > 0 ? Double(stepsDone) / Double(stepsTotal) : nil
    }

    var isFinished: Bool { status == "done" || status == "error" }

    static let preview = PulseAttributes.ContentState(
        status: "running", activity: "Modifie des fichiers", currentStep: "Écriture des tests",
        stepsDone: 2, stepsTotal: 5, agents: 2, workflow: "", costUsd: 1.42, contextPct: 38,
        fiveHourPct: 23, duration: "4 min"
    )
}
