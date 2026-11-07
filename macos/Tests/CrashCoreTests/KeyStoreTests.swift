import XCTest
@testable import CrashCore

/// Trousseau : service de test aléatoire (jamais « SkyrimCrashAnalyzer »), clé factice ; élément supprimé en fin d'essai.
final class KeyStoreTests: XCTestCase {
    func testRoundTripWithTestService() throws {
        let service = "SkyrimCrashAnalyzerTest-" + UUID().uuidString
        setenv("SKYRIM_CA_KEYCHAIN_SERVICE", service, 1)
        unsetenv("SKYRIM_CA_NO_KEYCHAIN")
        unsetenv("GEMINI_API_KEY")
        defer { try? KeyStore.delete(AIClient.KEYRING_USER); unsetenv("SKYRIM_CA_KEYCHAIN_SERVICE"); setenv("SKYRIM_CA_NO_KEYCHAIN", "1", 1) }
        XCTAssertEqual(KeyStore.service, service)
        XCTAssertFalse(AIClient.hasKey())
        do { try AIClient.setApiKey("  FAKE-KEY-123  ") } catch { throw XCTSkip("Trousseau indisponible : \(error)") }
        XCTAssertTrue(AIClient.hasKey())
        let (key, src) = AIClient.apiKeySource()
        XCTAssertEqual(key, "FAKE-KEY-123"); XCTAssertEqual(src, "trousseau")
        try AIClient.setApiKey("FAKE-2")   // mise à jour d'un élément existant
        XCTAssertEqual(AIClient.apiKey(), "FAKE-2")
        try AIClient.setApiKey("")         // vide : suppression
        XCTAssertFalse(AIClient.hasKey()); XCTAssertNil(AIClient.apiKey())
    }

    func testEnvironmentFallbackAndDisabledSwitch() {
        setenv("SKYRIM_CA_NO_KEYCHAIN", "1", 1)
        setenv("GEMINI_API_KEY", " ENV-FAKE ", 1)
        defer { unsetenv("GEMINI_API_KEY") }
        let (key, src) = AIClient.apiKeySource()
        XCTAssertEqual(key, "ENV-FAKE"); XCTAssertEqual(src, "variable d'environnement GEMINI_API_KEY")
        XCTAssertTrue(AIClient.hasKey())
        unsetenv("GEMINI_API_KEY")
        XCTAssertEqual(AIClient.apiKeySource().1, "aucune")
    }
}
