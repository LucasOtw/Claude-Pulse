import ActivityKit
import Foundation

/// La Live Activity unique de Claude Pulse. Elle suit la session la plus importante du moment
/// (celle qui attend ta validation, sinon la plus récente en cours) et change de session toute seule.
struct PulseAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var project: String
        /// running | waiting | background | done | error | idle
        var status: String
        var activity: String
        var currentStep: String
        var stepsDone: Int
        var stepsTotal: Int
        var agents: Int
        var workflow: String
        var costUsd: Double
        /// -1 si inconnu (pas d'abonnement Pro/Max ou pas encore de relevé)
        var fiveHourPct: Int
        /// Début de la tâche, secondes Unix
        var startedAt: Double
        /// Durée figée, ex. « 12 min », affichée une fois la tâche finie
        var duration: String
        /// Autres sessions actives en parallèle
        var otherActive: Int
    }

    var name: String
}

extension PulseAttributes.ContentState {
    var startDate: Date { Date(timeIntervalSince1970: startedAt) }
    var isActive: Bool { ["running", "waiting", "background"].contains(status) }

    var progress: Double? {
        stepsTotal > 0 ? Double(stepsDone) / Double(stepsTotal) : nil
    }

    static func idle(fiveHourPct: Int = -1) -> Self {
        Self(project: "Claude Code", status: "idle", activity: "En attente d'une tâche", currentStep: "",
             stepsDone: 0, stepsTotal: 0, agents: 0, workflow: "", costUsd: 0, fiveHourPct: fiveHourPct,
             startedAt: Date().timeIntervalSince1970, duration: "", otherActive: 0)
    }

    static let preview = Self(
        project: "Studio_Granit", status: "running", activity: "Modifie des fichiers", currentStep: "Écriture des tests",
        stepsDone: 2, stepsTotal: 5, agents: 2, workflow: "", costUsd: 1.42, fiveHourPct: 23,
        startedAt: Date().addingTimeInterval(-240).timeIntervalSince1970, duration: "4 min", otherActive: 1
    )
}
