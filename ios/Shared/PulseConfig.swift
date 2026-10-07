import Foundation

/// Réglages partagés entre l'app et le widget (App Group).
enum PulseConfig {
    static let appGroup = "group.com.lucasotw.claudepulse"
    static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }

    static var baseURL: String {
        get { defaults.string(forKey: "baseURL") ?? "" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines).trimmingSuffix("/"), forKey: "baseURL") }
    }

    static var token: String {
        get { defaults.string(forKey: "token") ?? "" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "token") }
    }

    static var isConfigured: Bool { !baseURL.isEmpty && !token.isEmpty }

    /// Dernier état reçu, pour que le widget ait quelque chose à afficher hors ligne.
    static var cachedState: PulseState? {
        get { defaults.data(forKey: "cachedState").flatMap { try? JSONDecoder().decode(PulseState.self, from: $0) } }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "cachedState") }
    }
}

private extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        var s = self
        while s.hasSuffix(suffix) { s.removeLast(suffix.count) }
        return s
    }
}
