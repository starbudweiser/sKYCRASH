import Foundation
import XCTest
@testable import CrashCore

class TempDirCase: XCTestCase {
    var tmp = ""
    override func setUp() {
        super.setUp()
        I18n.setLang("fr")
        setenv("SKYRIM_CA_NO_KEYCHAIN", "1", 1)
        tmp = NSTemporaryDirectory() + "skycrash-test-" + UUID().uuidString
        try? FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
    }
    override func tearDown() {
        try? FileManager.default.removeItem(atPath: tmp)
        I18n.setLang("fr")
        super.tearDown()
    }
    @discardableResult
    func write(_ rel: String, _ content: String) -> String {
        let p = rel.hasPrefix("/") ? rel : PyFS.join(tmp, rel)
        try? FileManager.default.createDirectory(atPath: PyFS.dirname(p), withIntermediateDirectories: true)
        try! content.write(toFile: p, atomically: true, encoding: .utf8)
        return p
    }
    @discardableResult
    func writeBytes(_ rel: String, _ b: [UInt8]) -> String {
        let p = PyFS.join(tmp, rel)
        try? FileManager.default.createDirectory(atPath: PyFS.dirname(p), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: p, contents: Data(b))
        return p
    }
    func setMtime(_ path: String, _ w: Wall) {
        try? FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: w.timestamp)], ofItemAtPath: path)
    }
}

func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)] }
func le32(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)] }
func le64(_ v: UInt64) -> [UInt8] { (0..<8).map { UInt8((v >> (8 * UInt64($0))) & 0xFF) } }
func wstr(_ s: String) -> [UInt8] { let b = Array(s.utf8); return le16(b.count) + b }
func titles(_ r: AuditReport) -> String { r.findings.map { $0.title }.joined(separator: " | ") }

/// Racine du dépôt (…/sKYCRASH), d'après l'emplacement de ce fichier.
let repoRoot: String = {
    var u = URL(fileURLWithPath: #filePath)
    for _ in 0..<4 { u.deleteLastPathComponent() }
    return u.path
}()
