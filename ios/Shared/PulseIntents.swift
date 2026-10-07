import AppIntents

/// Bouton « Autoriser » / « Refuser » de la Live Activity (et de l'app) pour une demande
/// d'autorisation de Claude Code. S'exécute sans ouvrir l'app.
struct DecideApprovalIntent: AppIntent {
    static var title: LocalizedStringResource = "Répondre à une demande de Claude"
    static var isDiscoverable: Bool = false

    @Parameter(title: "Demande")
    var approvalID: String

    @Parameter(title: "Autoriser")
    var allow: Bool

    init() {}

    init(approvalID: String, allow: Bool) {
        self.approvalID = approvalID
        self.allow = allow
    }

    func perform() async throws -> some IntentResult {
        try await PulseAPI.decide(id: approvalID, allow: allow)
        return .result()
    }
}
