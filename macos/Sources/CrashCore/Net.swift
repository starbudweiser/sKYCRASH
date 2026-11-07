// Réseau et Trousseau : HTTP bloquant (utilisé hors du thread d'interface) et clés dans le Trousseau macOS.

import Foundation
import Security

public enum AppPaths {
    /// Dossier des données : ~/Library/Application Support/SkyrimCrashAnalyzer (SKYRIM_CA_APPDIR pour les essais isolés).
    public static var appDir: String {
        if let o = ProcessInfo.processInfo.environment["SKYRIM_CA_APPDIR"], !o.isEmpty { return o }
        return NSHomeDirectory() + "/Library/Application Support/SkyrimCrashAnalyzer"
    }
    public static var configFile: String { PyFS.join(appDir, "config.json") }
    public static var knowledgeDir: String { PyFS.join(appDir, "knowledge") }
    public static var skillsDir: String { PyFS.join(appDir, "skills") }
    public static var jevUsageFile: String { PyFS.join(appDir, "jev_usage.json") }
}

public struct HTTPFailure: Error {
    public enum Kind { case status(Int, Data), connection(String), timeout(String) }
    public let kind: Kind
}

public enum HTTP {
    public struct Response { public let status: Int; public let body: Data; public let headers: [String: String]; public let finalURL: URL? }

    /// Motif technique en anglais, indépendant de la langue du système (comme le motif d'erreur de la version Python).
    static func reason(_ e: URLError) -> String {
        switch e.code {
        case .cannotConnectToHost: return "connection refused"
        case .cannotFindHost, .dnsLookupFailed: return "host not found"
        case .notConnectedToInternet: return "no internet connection"
        case .networkConnectionLost: return "connection lost"
        case .timedOut: return "timed out"
        case .secureConnectionFailed, .serverCertificateUntrusted: return "TLS error"
        default: return "network error (\(e.errorCode))"
        }
    }

    /// Requête synchrone (ne jamais appeler depuis le thread principal). Les statuts ≥ 400 lèvent `HTTPFailure.status`.
    public static func send(_ req: URLRequest, timeout: TimeInterval, maxBytes: Int = Int.max) throws -> Response {
        var r = req
        r.timeoutInterval = timeout
        let sem = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: (Data?, URLResponse?, Error?) = (nil, nil, nil)
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = timeout
        cfg.timeoutIntervalForResource = timeout * 2
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: cfg)
        session.dataTask(with: r) { d, resp, err in result = (d, resp, err); sem.signal() }.resume()
        sem.wait()
        session.finishTasksAndInvalidate()
        if let e = result.2 as? URLError {
            let reason = Self.reason(e)
            if e.code == .timedOut { throw HTTPFailure(kind: .timeout(reason)) }
            throw HTTPFailure(kind: .connection(reason))
        }
        if let e = result.2 { throw HTTPFailure(kind: .connection(e.localizedDescription)) }
        guard let http = result.1 as? HTTPURLResponse else { throw HTTPFailure(kind: .connection("réponse invalide")) }
        let body = result.0 ?? Data()
        var headers: [String: String] = [:]
        for (k, v) in http.allHeaderFields { headers["\(k)".lowercased()] = "\(v)" }
        if http.statusCode >= 400 || http.statusCode == 304 { throw HTTPFailure(kind: .status(http.statusCode, body)) }
        if body.count > maxBytes { throw HTTPFailure(kind: .status(-1, Data())) }
        return Response(status: http.statusCode, body: body, headers: headers, finalURL: http.url)
    }
}

/// Clés API dans le Trousseau macOS (service « SkyrimCrashAnalyzer », comme la version Python via `keyring`).
public enum KeyStore {
    public static var service: String {
        ProcessInfo.processInfo.environment["SKYRIM_CA_KEYCHAIN_SERVICE"].flatMap { $0.isEmpty ? nil : $0 } ?? "SkyrimCrashAnalyzer"
    }
    /// SKYRIM_CA_NO_KEYCHAIN=1 : le Trousseau n'est jamais interrogé (essais automatiques).
    static var disabled: Bool { ProcessInfo.processInfo.environment["SKYRIM_CA_NO_KEYCHAIN"] == "1" }

    static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    /// Lit la clé (peut déclencher la demande d'autorisation du Trousseau pour un élément créé par une autre appli).
    public static func get(_ account: String) -> String? {
        if disabled { return nil }
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        let s = String(decoding: d, as: UTF8.self).pyStrip
        return s.isEmpty ? nil : s
    }

    /// La clé existe-t-elle ? Lit seulement les attributs : aucune demande d'autorisation, la valeur n'est jamais lue.
    public static func exists(_ account: String) -> Bool {
        if disabled { return false }
        var q = query(account)
        q[kSecReturnAttributes as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        return SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess
    }

    public static func set(_ account: String, _ value: String) throws {
        let data = Data(value.pyStrip.utf8)
        let st = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if st == errSecSuccess { return }
        if st == errSecItemNotFound {
            var q = query(account)
            q[kSecValueData as String] = data
            let add = SecItemAdd(q as CFDictionary, nil)
            if add == errSecSuccess { return }
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(add))
        }
        throw NSError(domain: NSOSStatusErrorDomain, code: Int(st))
    }

    public static func delete(_ account: String) throws {
        let st = SecItemDelete(query(account) as CFDictionary)
        if st != errSecSuccess && st != errSecItemNotFound { throw NSError(domain: NSOSStatusErrorDomain, code: Int(st)) }
    }
}
