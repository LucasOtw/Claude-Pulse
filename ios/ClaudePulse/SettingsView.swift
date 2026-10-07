import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var activities: ActivityManager

    @State private var baseURL = PulseConfig.baseURL
    @State private var token = PulseConfig.token
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://claude-pulse-xxx.vercel.app", text: $baseURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("PULSE_TOKEN", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Backend")
                } footer: {
                    Text("Le même jeton que la variable PULSE_TOKEN sur Vercel et dans ~/.claude/claude-pulse/config.")
                }

                Section {
                    LabeledContent("Push à distance", value: activities.startTokenRegistered ? "Prêt ✅" : "En attente…")
                    if let error = activities.lastError {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                    Button("Tester : démarrer") { test("start") }
                    Button("Tester : attente de validation") { test("waiting") }
                    Button("Tester : terminer") { test("end") }
                    Button("Fermer toutes les Live Activities", role: .destructive) {
                        Task { await activities.endAll() }
                    }
                } header: {
                    Text("Live Activities")
                } footer: {
                    Text("Verrouille l'iPhone après « Tester : démarrer » pour voir l'activité.")
                }

                if let message {
                    Section { Text(message) }
                }
            }
            .navigationTitle("Réglages")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") {
                        save()
                        Task { await activities.resendTokens() }
                        dismiss()
                    }
                }
            }
        }
    }

    private func save() {
        PulseConfig.baseURL = baseURL
        PulseConfig.token = token
    }

    private func test(_ step: String) {
        save()
        Task {
            do {
                // Le jeton push-to-start doit être connu du backend avant la démo.
                await activities.resendTokens()
                message = try await PulseAPI.sendTest(step: step)
            } catch {
                message = error.localizedDescription
            }
        }
    }
}
