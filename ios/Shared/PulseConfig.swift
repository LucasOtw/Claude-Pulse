import Foundation

/// Réglages compilés dans l'app et le widget (voir PulseSecrets.example.swift et setup.sh).
/// Sans compte développeur payant, pas d'App Group pour partager des réglages saisis dans l'app.
enum PulseConfig {
    static let baseURL: String = {
        var url = PulseSecrets.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while url.hasSuffix("/") { url.removeLast() }
        return url
    }()

    static let token = PulseSecrets.token.trimmingCharacters(in: .whitespacesAndNewlines)

    static var isConfigured: Bool {
        baseURL.hasPrefix("http") && !baseURL.contains("xxx") && !token.isEmpty && !token.hasPrefix("colle-ici")
    }

    /// Apparence de la Live Activity, réglée dans l'app.
    enum ActivityTheme: String, CaseIterable, Identifiable {
        case dark, light, auto
        var id: String { rawValue }
        var label: String {
            switch self {
            case .dark: return "Noir"
            case .light: return "Blanc"
            case .auto: return "Auto"
            }
        }
    }

    static var activityTheme: ActivityTheme {
        get { ActivityTheme(rawValue: UserDefaults.standard.string(forKey: "activityTheme") ?? "") ?? .dark }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "activityTheme") }
    }

    /// Localisation en arrière-plan pour garder l'app éveillée (activée par défaut).
    static var backgroundLocation: Bool {
        get { UserDefaults.standard.object(forKey: "backgroundLocation") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "backgroundLocation") }
    }

    /// Dernier état reçu (propre à l'app ou au widget), pour afficher quelque chose hors ligne.
    static var cachedState: PulseState? {
        get { UserDefaults.standard.data(forKey: "cachedState").flatMap { try? JSONDecoder().decode(PulseState.self, from: $0) } }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "cachedState") }
    }
}
