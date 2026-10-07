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
        /// Fin estimée de la tâche, secondes Unix (0 si pas d'estimation)
        var estimatedEndAt: Double
        /// -1 si inconnu (pas d'abonnement Pro/Max ou pas encore de relevé)
        var fiveHourPct: Int
        /// Remise à zéro de la limite 5 h, secondes Unix (0 si inconnue)
        var fiveHourResetsAt: Double
        /// Début de la tâche, secondes Unix
        var startedAt: Double
        /// Durée figée, ex. « 12 min », affichée une fois la tâche finie
        var duration: String
        /// Autres sessions actives en parallèle
        var otherActive: Int
        /// Apparence choisie dans l'app : "dark", "light" ou "auto"
        var theme: String
    }

    var name: String
}

extension PulseAttributes.ContentState {
    var startDate: Date { Date(timeIntervalSince1970: startedAt) }
    var isActive: Bool { ["running", "waiting", "background"].contains(status) }

    var progress: Double? {
        stepsTotal > 0 ? Double(stepsDone) / Double(stepsTotal) : nil
    }

    /// Heure de fin estimée, si une estimation existe.
    var estimatedEnd: Date? {
        estimatedEndAt > 0 && isActive ? Date(timeIntervalSince1970: estimatedEndAt) : nil
    }

    var fiveHourResetDate: Date? {
        fiveHourResetsAt > 0 ? Date(timeIntervalSince1970: fiveHourResetsAt) : nil
    }

    static func idle(fiveHourPct: Int = -1, fiveHourResetsAt: Double = 0) -> Self {
        Self(project: "Claude Code", status: "idle", activity: "En attente d'une tâche", currentStep: "",
             stepsDone: 0, stepsTotal: 0, agents: 0, workflow: "", estimatedEndAt: 0, fiveHourPct: fiveHourPct,
             fiveHourResetsAt: fiveHourResetsAt, startedAt: Date().timeIntervalSince1970, duration: "",
             otherActive: 0, theme: PulseConfig.activityTheme.rawValue)
    }

    static let preview = Self(
        project: "Studio_Granit", status: "running", activity: "Modifie des fichiers", currentStep: "Écriture des tests",
        stepsDone: 2, stepsTotal: 5, agents: 2, workflow: "", estimatedEndAt: Date().addingTimeInterval(380).timeIntervalSince1970, fiveHourPct: 23,
        fiveHourResetsAt: Date().addingTimeInterval(7200).timeIntervalSince1970, startedAt: Date().addingTimeInterval(-240).timeIntervalSince1970, duration: "4 min", otherActive: 1, theme: "dark"
    )
}
