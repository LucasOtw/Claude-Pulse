import Foundation

enum PulseAPIError: LocalizedError {
    case notConfigured
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Backend non configuré : lance ios/setup.sh puis recompile."
        case .http(401, _): return "Jeton refusé par le backend (PULSE_TOKEN)."
        case let .http(code, body): return "Erreur \(code) : \(body)"
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

    /// Démo de bout en bout : step = "start", "waiting" ou "end".
    static func sendTest(step: String) async throws {
        _ = try await request("POST", "/api/test", body: ["step": step])
    }

    private static func request(_ method: String, _ path: String, body: [String: String]? = nil) async throws -> Data {
        guard PulseConfig.isConfigured, let url = URL(string: PulseConfig.baseURL + path) else {
            throw PulseAPIError.notConfigured
        }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = method
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("Bearer \(PulseConfig.token)", forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw PulseAPIError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }
}
