import Foundation

enum PulseAPIError: LocalizedError {
    case notConfigured
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Backend non configuré : lance ios/setup.sh puis recompile."
        case .http(401, _): return "Jeton refusé par le backend (PULSE_TOKEN)."
        case let .http(code, body):
            // Le serveur répond { "error": "…" } : on affiche ce message tel quel.
            if let data = body.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = json["error"] as? String {
                return message
            }
            return "Erreur \(code) : \(body)"
        }
    }
}

enum PulseAPI {
    static func fetchState() async throws -> PulseState {
        let data = try await request("GET", "/api/state")
        let state = try JSONDecoder().decode(PulseState.self, from: data)
        PulseConfig.cachedState = state
        return state
    }

    /// Tokens et équivalent en dollars au tarif de l'API (vue détaillée).
    static func fetchStats() async throws -> PulseStats {
        let data = try await request("GET", "/api/stats")
        return try JSONDecoder().decode(PulseStats.self, from: data)
    }

    /// Détail d'une session (étapes, sous-agents, journal, tokens).
    static func fetchSession(_ sid: String) async throws -> SessionDetail {
        let id = sid.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? sid
        let data = try await request("GET", "/api/session?sid=\(id)")
        return try JSONDecoder().decode(SessionDetail.self, from: data)
    }

    /// Répond à une demande d'autorisation (validation à distance).
    static func decide(id: String, allow: Bool) async throws {
        _ = try await request("POST", "/api/decide", json: ["id": id, "allow": allow])
    }

    /// Allume ou éteint la validation à distance (s'éteint seule au bout de 12 h).
    static func setRemote(_ on: Bool) async throws {
        _ = try await request("POST", "/api/remote", json: ["on": on])
    }

    private static func request(_ method: String, _ path: String, json: [String: Any]? = nil) async throws -> Data {
        guard PulseConfig.isConfigured, let url = URL(string: PulseConfig.baseURL + path) else {
            throw PulseAPIError.notConfigured
        }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = method
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("Bearer \(PulseConfig.token)", forHTTPHeaderField: "Authorization")
        if let json {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: json)
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw PulseAPIError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }
}
