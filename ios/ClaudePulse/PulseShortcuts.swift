import AppIntents

/// « Dis Siri, où en est Claude Pulse ? » : ce que fait Claude et la limite 5 h, à voix haute.
struct ClaudeStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Où en est Claude"
    static var description = IntentDescription("Dit ce que fait Claude Code sur ton Mac, le temps restant et ta limite 5 h.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let state = try await PulseAPI.fetchState()
        return .result(dialog: "\(SiriText.status(state))")
    }
}

/// « Dis Siri, limite de Claude Pulse » : où en est la limite 5 h et quand elle se remet à zéro.
struct ClaudeLimitIntent: AppIntent {
    static var title: LocalizedStringResource = "Limite Claude"
    static var description = IntentDescription("Dit où en sont tes limites 5 h et 7 jours.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let state = try await PulseAPI.fetchState()
        return .result(dialog: "\(SiriText.limits(state))")
    }
}

struct PulseShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ClaudeStatusIntent(),
            phrases: [
                "Où en est \(.applicationName)",
                "Que fait \(.applicationName)",
                "Statut de \(.applicationName)",
            ],
            shortTitle: "Où en est Claude",
            systemImageName: "waveform.path.ecg"
        )
        AppShortcut(
            intent: ClaudeLimitIntent(),
            phrases: [
                "Limite de \(.applicationName)",
                "Ma limite \(.applicationName)",
            ],
            shortTitle: "Limite 5 h",
            systemImageName: "gauge.with.dots.needle.50percent"
        )
    }
}

/// Phrases lues par Siri.
enum SiriText {
    static func status(_ state: PulseState) -> String {
        var parts: [String] = []
        let active = state.activeSessions
        if let waiting = active.first(where: { $0.status == "waiting" }) {
            parts.append("\(waiting.project) attend ta validation.")
        }
        for s in active.prefix(2) where s.status != "waiting" {
            var line = "\(s.project) : \(s.activity)."
            if let eta = s.etaSeconds, eta >= 0 {
                line += " Environ \(minutes(eta)) restantes."
            } else if s.stepsTotal > 0 {
                line += " Étape \(min(s.stepsDone + 1, s.stepsTotal)) sur \(s.stepsTotal)."
            }
            parts.append(line)
        }
        if active.isEmpty {
            if let last = state.sessions.first, last.status == "done" {
                parts.append("Claude ne travaille sur rien. Dernière tâche terminée : \(last.project), en \(last.duration).")
            } else {
                parts.append("Claude ne travaille sur rien en ce moment.")
            }
        } else if active.count > 2 {
            parts.append("Et \(active.count - 2) autre\(active.count - 2 > 1 ? "s" : "") session\(active.count - 2 > 1 ? "s" : "") en cours.")
        }
        if let five = state.limits.fiveHour {
            parts.append("Ta limite 5 heures est à \(Int(five.pct.rounded())) %.")
        }
        return parts.joined(separator: " ")
    }

    static func limits(_ state: PulseState) -> String {
        guard let five = state.limits.fiveHour else {
            return "Je n'ai pas de relevé de tes limites. Lance Claude Code pour l'actualiser."
        }
        var text = "Ta limite 5 heures est à \(Int(five.pct.rounded())) %, remise à zéro à \(PulseStyle.clock(five.resetDate))."
        if let week = state.limits.sevenDay {
            text += " Sur 7 jours, tu es à \(Int(week.pct.rounded())) %."
        }
        if state.limits.isOld {
            text += " Attention, ce relevé date de plus d'une heure."
        }
        return text
    }

    private static func minutes(_ seconds: Int) -> String {
        let m = max(1, Int((Double(seconds) / 60).rounded()))
        if m < 60 { return "\(m) minute\(m > 1 ? "s" : "")" }
        return "\(m / 60) heure\(m / 60 > 1 ? "s" : "") \(m % 60)"
    }
}
