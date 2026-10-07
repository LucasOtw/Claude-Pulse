import Foundation

enum PulseAPIError: LocalizedError {
    case notConfigured
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Renseigne l'URL du backend et le jeton dans les réglages."
        case .http(401, _): return "Jeton refusé par le backend."
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

    /// kind : "start" (jeton push-to-start) ou "activity" (jeton d'une Live Activity).
    static func registerToken(kind: String, token: Data, sessionId: String? = nil) async throws {
        var body: [String: String] = ["kind": kind, "token": token.map { String(format: "%02x", $0) }.joined()]
        if let sessionId { body["sid"] = sessionId }
        _ = try await request("POST", "/api/device", body: body)
    }

    /// Démo de bout en bout : step = "start", "waiting" ou "end". Renvoie un résumé lisible.
    static func sendTest(step: String) async throws -> String {
        let data = try await request("POST", "/api/test", body: ["step": step])
        let body = String(data: data, encoding: .utf8) ?? ""
        if body.contains("\"skipped\"") || body.contains("\"error\"") {
            return "⚠️ Rien n'a été envoyé : \(body)"
        }
        if body.contains("\"reason\"") {
            return "⚠️ Apple a refusé la push : \(body)"
        }
        return "Envoyé ✅"
    }

    private static func request(_ method: String, _ path: String, body: [String: String]? = nil) async throws -> Data {
        guard PulseConfig.isConfigured, let url = URL(string: PulseConfig.baseURL + path) else {
            throw PulseAPIError.notConfigured
        }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = method
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
