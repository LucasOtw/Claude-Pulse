import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Serveur", value: PulseConfig.isConfigured ? host : "non configuré")
                    LabeledContent("Jeton", value: PulseConfig.isConfigured ? "••••" + String(PulseConfig.token.suffix(4)) : "non configuré")
                } header: {
                    Text("Backend")
                } footer: {
                    Text("Pour changer : relance ios/setup.sh sur le Mac, puis recompile depuis Xcode.")
                }
                .listRowBackground(PulseStyle.card)

                Section {
                    demoButton("Tâche en cours", symbol: "sparkle", step: "start")
                    demoButton("Attente de validation", symbol: "hand.raised.fill", step: "waiting")
                    demoButton("Tâche terminée", symbol: "checkmark", step: "end")
                    if let message {
                        Text(message).font(.footnote).foregroundStyle(PulseStyle.textSecondary)
                    }
                } header: {
                    Text("Démo")
                } footer: {
                    Text("Crée une fausse session « Démo » sur le backend. Lance la surveillance avant, puis verrouille l'iPhone pour voir la Live Activity changer.")
                }
                .listRowBackground(PulseStyle.card)

                Section {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                } footer: {
                    Text("Installée avec un Apple ID gratuit : l'app expire au bout de 7 jours. Rebranche l'iPhone et relance-la depuis Xcode (⌘R) chaque semaine.")
                }
                .listRowBackground(PulseStyle.card)
            }
            .scrollContentBackground(.hidden)
            .background(PulseStyle.background.ignoresSafeArea())
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
        .tint(PulseStyle.accent)
    }

    private var host: String {
        URL(string: PulseConfig.baseURL)?.host ?? PulseConfig.baseURL
    }

    private func demoButton(_ title: String, symbol: String, step: String) -> some View {
        Button {
            Task {
                do {
                    try await PulseAPI.sendTest(step: step)
                    message = "Envoyé ✅ : la Live Activity se met à jour d'ici quelques secondes."
                } catch {
                    message = error.localizedDescription
                }
            }
        } label: {
            Label(title, systemImage: symbol)
                .foregroundStyle(PulseStyle.textPrimary)
        }
    }
}
