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

    /// Dernier état reçu (propre à l'app ou au widget), pour afficher quelque chose hors ligne.
    static var cachedState: PulseState? {
        get { UserDefaults.standard.data(forKey: "cachedState").flatMap { try? JSONDecoder().decode(PulseState.self, from: $0) } }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "cachedState") }
    }
}
