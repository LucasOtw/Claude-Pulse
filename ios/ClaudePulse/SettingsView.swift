import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("URL", value: PulseConfig.isConfigured ? PulseConfig.baseURL : "non configurée")
                    LabeledContent("Jeton", value: PulseConfig.isConfigured ? "••••" + String(PulseConfig.token.suffix(4)) : "non configuré")
                } header: {
                    Text("Backend")
                } footer: {
                    Text("Pour changer : relance ios/setup.sh sur le Mac, puis recompile depuis Xcode.")
                }

                Section {
                    Button("Démo : tâche en cours") { test("start") }
                    Button("Démo : attente de validation") { test("waiting") }
                    Button("Démo : terminée") { test("end") }
                    if let message {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Tester")
                } footer: {
                    Text("Crée une fausse session « Démo » sur le backend. Lance la surveillance avant, puis verrouille l'iPhone pour voir la Live Activity changer.")
                }
            }
            .navigationTitle("Réglages")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
    }

    private func test(_ step: String) {
        Task {
            do {
                try await PulseAPI.sendTest(step: step)
                message = "Envoyé ✅ : la Live Activity se met à jour d'ici quelques secondes."
            } catch {
                message = error.localizedDescription
            }
        }
    }
}
