import Foundation

/// Réponse de GET /api/state.
struct PulseState: Codable {
    struct Limit: Codable {
        var pct: Double
        /// Secondes Unix
        var resetsAt: Double
        var resetDate: Date { Date(timeIntervalSince1970: resetsAt) }
    }

    struct Limits: Codable {
        var fiveHour: Limit?
        var sevenDay: Limit?
    }

    struct Today: Codable {
        var costUsd: Double
        var sessions: Int
    }

    struct Session: Codable, Identifiable {
        var sid: String
        var project: String
        var title: String?
        var status: String
        var activity: String
        var currentStep: String
        var stepsDone: Int
        var stepsTotal: Int
        var agents: Int
        var workflow: String
        var costUsd: Double
        var contextPct: Int
        var model: String?
        var duration: String
        /// Temps restant estimé en secondes, -1 si inconnu
        var etaSeconds: Int?
        /// Secondes Unix
        var startedAt: Double
        var updatedAt: Double

        var id: String { sid }
        var isActive: Bool { ["running", "waiting", "background"].contains(status) }
    }

    var updatedAt: Double
    var limits: Limits
    var today: Today
    var sessions: [Session]

    var activeSessions: [Session] { sessions.filter(\.isActive) }

    static let preview = PulseState(
        updatedAt: Date().timeIntervalSince1970,
        limits: Limits(
            fiveHour: Limit(pct: 23.5, resetsAt: Date().addingTimeInterval(2 * 3600).timeIntervalSince1970),
            sevenDay: Limit(pct: 41.2, resetsAt: Date().addingTimeInterval(3 * 86400).timeIntervalSince1970)
        ),
        today: Today(costUsd: 4.87, sessions: 3),
        sessions: [
            Session(sid: "1", project: "Studio_Granit", title: "Refonte accueil", status: "running",
                    activity: "Modifie des fichiers", currentStep: "Écriture du CSS", stepsDone: 2, stepsTotal: 5,
                    agents: 1, workflow: "", costUsd: 1.42, contextPct: 38, model: "Opus", duration: "12 min", etaSeconds: 420,
                    startedAt: Date().addingTimeInterval(-720).timeIntervalSince1970,
                    updatedAt: Date().timeIntervalSince1970),
        ]
    )
}

/// Réponse de GET /api/stats : tokens lus dans les transcripts Claude Code du Mac.
struct PulseStats: Codable {
    struct Period: Codable {
        var tokens: Int
        var costUsd: Double
    }

    struct Periods: Codable {
        var today: Period
        var week: Period
        var month: Period
    }

    struct Totals: Codable {
        var tokens: Int
        var input: Int
        var output: Int
        var cacheWrite: Int
        var cacheRead: Int
        var costUsd: Double
    }

    struct Day: Codable, Identifiable {
        /// « 2026-10-07 »
        var day: String
        var tokens: Int
        var costUsd: Double

        var id: String { day }
        var date: Date { PulseStats.dayFormatter.date(from: day) ?? .distantPast }
    }

    struct Model: Codable, Identifiable {
        var model: String
        var tokens: Int
        var costUsd: Double
        var id: String { model }
    }

    var since: String?
    var totals: Totals
    var periods: Periods
    var days: [Day]
    var models: [Model]
    var sessions: Int

    var sinceDate: Date? { since.flatMap { PulseStats.dayFormatter.date(from: $0) } }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

/// Réponse de GET /api/session?sid=… : tout le détail d'une session.
struct SessionDetail: Codable {
    struct Step: Codable {
        var text: String
        /// completed | in_progress | pending
        var status: String
    }

    struct Agent: Codable, Identifiable {
        var id: String
        var type: String
        var description: String
        var activity: String
        /// running | done
        var status: String
        var startedAt: Double
        var endedAt: Double?

        var startDate: Date { Date(timeIntervalSince1970: startedAt) }
        var seconds: Int { Int((endedAt ?? Date().timeIntervalSince1970) - startedAt) }
    }

    struct Workflow: Codable {
        var name: String
        var phases: [String]
    }

    struct LogLine: Codable {
        var at: Double
        var text: String
        var date: Date { Date(timeIntervalSince1970: at) }
    }

    struct Tokens: Codable {
        var tokens: Int
        var input: Int
        var output: Int
        var cacheWrite: Int
        var cacheRead: Int
        var costUsd: Double
    }

    var session: PulseState.Session
    var steps: [Step]
    var agents: [Agent]
    var workflow: Workflow?
    var log: [LogLine]
    var tokens: Tokens?
}
