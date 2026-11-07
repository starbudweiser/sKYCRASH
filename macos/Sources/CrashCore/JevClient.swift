// Client Jev (TypeSafe System One) : jugements typés sur un état donné (src/jev_client.py).
// La clé est lue dans le Trousseau macOS ou la variable d'environnement TYPESAFE_API_KEY ; jamais écrite dans la config.

import Foundation

public struct JevError: Error, CustomStringConvertible {
    public let description: String
    public init(_ d: String) { description = d }
}

public enum JevClient {
    public static let ENDPOINT = "https://api.typesafe.ai/v1/systemone"
    public static let MODEL = "jev-latest"
    public static let KEYRING_USER = "typesafe_api_key"
    public static let TIMEOUT_S = 30.0
    public static let CONSOLE_URL = "https://console.typesafe.ai/"

    static func month() -> String { Wall(timestamp: Date().timeIntervalSince1970).format("%Y-%m") }

    public struct Usage { public var month: String; public var requests: Int; public var inputTokens: Int; public var outputTokens: Int }

    /// Requêtes et jetons Jev du mois en cours (zéro au changement de mois).
    public static func monthUsage() -> Usage {
        var u: J = .obj([])
        if let t = PyFS.readText(AppPaths.jevUsageFile), let j = J.parse(t), j.object != nil { u = j }
        if u["month"]?.string != month() { u = .obj([]) }
        return Usage(month: month(), requests: u["requests"]?.intValue ?? 0, inputTokens: u["input_tokens"]?.intValue ?? 0,
                     outputTokens: u["output_tokens"]?.intValue ?? 0)
    }

    public static func recordUsage(input: Int, output: Int) {
        var u = monthUsage()
        u.requests += 1; u.inputTokens += input; u.outputTokens += output
        let j: J = .obj([("month", .str(u.month)), ("requests", .int(u.requests)),
                         ("input_tokens", .int(u.inputTokens)), ("output_tokens", .int(u.outputTokens))])
        try? FileManager.default.createDirectory(atPath: AppPaths.appDir, withIntermediateDirectories: true)
        try? j.dump(compact: false).write(toFile: AppPaths.jevUsageFile, atomically: false, encoding: .utf8)
    }

    /// (clé, source). Le trousseau prime sur l'environnement.
    public static func apiKeySource() -> (String?, String) {
        if let k = KeyStore.get(KEYRING_USER) { return (k, N_("trousseau")) }
        if let e = ProcessInfo.processInfo.environment["TYPESAFE_API_KEY"], !e.pyStrip.isEmpty {
            return (e.pyStrip, N_("variable d'environnement TYPESAFE_API_KEY"))
        }
        return (nil, N_("aucune"))
    }
    public static func apiKey() -> String? { apiKeySource().0 }
    /// Une clé est-elle enregistrée ? Sans lire sa valeur (aucune demande du Trousseau).
    public static func hasKey() -> Bool {
        KeyStore.exists(KEYRING_USER) || !(ProcessInfo.processInfo.environment["TYPESAFE_API_KEY"] ?? "").pyStrip.isEmpty
    }

    public static func setApiKey(_ key: String) throws {
        do {
            if key.isEmpty { try KeyStore.delete(KEYRING_USER) } else { try KeyStore.set(KEYRING_USER, key) }
        } catch { throw JevError(L("Trousseau inaccessible : {e}", ["e": "\(error)"])) }
    }

    /// Corps de la requête (testable sans envoi).
    public static func requestBody(state: J, questions: J, model: String = MODEL) -> J {
        .obj([("model", .str(model)), ("state", state), ("questions", questions)])
    }

    /// Pose `questions` sur `state` ; renvoie l'objet `answers` (mêmes ids que les questions).
    public static func systemOne(state: J, questions: J, model: String = MODEL, key: String? = nil) throws -> J {
        guard let key = key ?? apiKey() else { throw JevError(L("Aucune clé TypeSafe (Jev).")) }
        var req = URLRequest(url: URL(string: ENDPOINT)!)
        req.httpMethod = "POST"
        req.httpBody = Data(requestBody(state: state, questions: questions, model: model).dump(compact: true).utf8)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        do {
            let r = try HTTP.send(req, timeout: TIMEOUT_S)
            guard let body = J.parse(data: r.body), body.object != nil else { throw JevError(L("Jev : réponse illisible.")) }
            recordUsage(input: body["usage"]?["input_tokens"]?.intValue ?? 0, output: body["usage"]?["output_tokens"]?.intValue ?? 0)
            return body["answers"] ?? .obj([])
        } catch let e as HTTPFailure {
            switch e.kind {
            case .status(let c, _): throw JevError(L("Jev : erreur HTTP {code}.", ["code": c]))
            case .connection(let m), .timeout(let m): throw JevError(L("Jev : connexion impossible ({e}).", ["e": m]))
            }
        }
    }
}
