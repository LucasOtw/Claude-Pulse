import SwiftUI

/// Feuille de réglages, comme « Add to Chat » dans l'app Claude :
/// bouton rond de fermeture, titre centré, groupes de lignes.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                RowGroup {
                    InfoRow(symbol: "server.rack", title: "Serveur", value: PulseConfig.isConfigured ? host : "Non configuré")
                    RowDivider()
                    InfoRow(symbol: "key", title: "Jeton", value: PulseConfig.isConfigured ? "••••" + String(PulseConfig.token.suffix(4)) : "Non configuré")
                }
                Footnote("Pour changer : relance ios/setup.sh sur le Mac, puis ⌘R dans Xcode.")

                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(title: "Démo")
                    RowGroup {
                        DemoRow(symbol: "sparkle", title: "Tâche en cours", step: "start", message: $message)
                        RowDivider()
                        DemoRow(symbol: "hand.raised", title: "Attente de validation", step: "waiting", message: $message)
                        RowDivider()
                        DemoRow(symbol: "checkmark.circle", title: "Tâche terminée", step: "end", message: $message)
                    }
                    Footnote(message ?? "Crée une fausse session « Démo ». Active la surveillance, puis verrouille l'iPhone pour voir la Live Activity changer.")
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(title: "À propos")
                    RowGroup {
                        InfoRow(symbol: "info.circle", title: "Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                    }
                    Footnote("Installée avec un Apple ID gratuit : l'app expire au bout de 7 jours. Lance ~/claude-pulse/update.sh puis ⌘R chaque semaine.")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            ZStack {
                Text("Réglages")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(PulseStyle.textPrimary)
                HStack {
                    CircleButton(symbol: "xmark", label: "Fermer") { dismiss() }
                    Spacer()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)
            .background(PulseStyle.background)
        }
        .background(PulseStyle.background.ignoresSafeArea())
        .presentationDragIndicator(.visible)
        .tint(PulseStyle.accent)
    }

    private var host: String {
        URL(string: PulseConfig.baseURL)?.host ?? PulseConfig.baseURL
    }
}

private struct DemoRow: View {
    let symbol: String
    let title: String
    let step: String
    @Binding var message: String?

    var body: some View {
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
            HStack(spacing: 12) {
                RowIcon(symbol: symbol)
                Text(title).foregroundStyle(PulseStyle.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(PulseStyle.textTertiary)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct Footnote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(PulseStyle.textSecondary)
            .padding(.horizontal, 4)
    }
}
