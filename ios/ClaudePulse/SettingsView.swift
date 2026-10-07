import SwiftUI

/// Feuille de réglages, comme « Add to Chat » dans l'app Claude :
/// bouton rond de fermeture, titre centré, groupes de lignes.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var monitor: LiveMonitor
    @State private var theme = PulseConfig.activityTheme

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
                    SectionLabel(title: "Live Activity")
                    RowGroup {
                        HStack(spacing: 12) {
                            RowIcon(symbol: "circle.lefthalf.filled")
                            Text("Apparence").foregroundStyle(PulseStyle.textPrimary)
                            Spacer()
                            Picker("Apparence", selection: $theme) {
                                ForEach(PulseConfig.ActivityTheme.allCases) { Text($0.label).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 190)
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                    }
                    Footnote("« Auto » suit le thème de l'écran verrouillé. Le changement s'applique tout de suite si la surveillance tourne.")
                }
                .onChange(of: theme) { _, newValue in
                    Task { await monitor.setTheme(newValue) }
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

struct Footnote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(PulseStyle.textSecondary)
            .padding(.horizontal, 4)
    }
}
