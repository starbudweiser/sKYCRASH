// Lecture de l'en-tête d'une sauvegarde Skyrim SE (.ess) : traduction de src/savegame.py.
// Lecture seule ; la partie compressée (LZ4 bloc ou zlib) n'est décompressée que sur les premiers kilo-octets.

import Foundation

public struct SaveInfo {
    public var path: String
    public var player = ""
    public var level = 0
    public var location = ""
    public var savedAt = 0.0
    public var plugins: [String] = []
    public var light: [String] = []
    public var allPlugins: [String] { plugins + light }
}

public struct SaveError: Error, CustomStringConvertible {
    public let description: String
    init(_ d: String) { description = d }
}

public enum SaveGame {
    static let MAGIC = Array("TESV_SAVEGAME".utf8)
    static let NEEDED = 256 * 1024

    struct Reader {
        let d: [UInt8]
        var p = 0
        init(_ d: [UInt8], _ p: Int = 0) { self.d = d; self.p = p }
        mutating func take(_ n: Int) throws -> ArraySlice<UInt8> {
            if n < 0 || p + n > d.count { throw SaveError("sauvegarde tronquée") }
            defer { p += n }
            return d[p..<(p + n)]
        }
        mutating func u8() throws -> Int { Int(try take(1).first!) }
        mutating func u16() throws -> Int { let b = try take(2); return Int(b[b.startIndex]) | Int(b[b.startIndex + 1]) << 8 }
        mutating func u32() throws -> Int {
            let b = try take(4); let s = b.startIndex
            return Int(b[s]) | Int(b[s + 1]) << 8 | Int(b[s + 2]) << 16 | Int(b[s + 3]) << 24
        }
        mutating func u64() throws -> UInt64 {
            let b = try take(8); var v: UInt64 = 0
            for (i, x) in b.enumerated() { v |= UInt64(x) << (8 * UInt64(i)) }
            return v
        }
        mutating func wstr() throws -> String {
            let raw = try take(try u16())
            if let s = String(bytes: raw, encoding: .utf8) { return s }
            return decodeCP1252Replace(raw)
        }
    }

    /// Décompresse un bloc LZ4 jusqu'à obtenir au moins `want` octets (ou la fin du bloc).
    static func lz4BlockPrefix(_ src: [UInt8], _ want: Int) throws -> [UInt8] {
        var out: [UInt8] = []
        var i = 0
        let n = src.count
        func at(_ k: Int) throws -> Int { if k >= n { throw SaveError("bloc LZ4 tronqué") }; return Int(src[k]) }
        while i < n && out.count < want {
            let token = try at(i); i += 1
            var lit = token >> 4
            if lit == 15 {
                while true { let b = try at(i); i += 1; lit += b; if b != 255 { break } }
            }
            out.append(contentsOf: src[i..<min(i + lit, n)])
            i += lit
            if i >= n { break }
            let offset = try at(i) | (try at(i + 1) << 8)
            i += 2
            var mlen = token & 15
            if mlen == 15 {
                while true { let b = try at(i); i += 1; mlen += b; if b != 255 { break } }
            }
            mlen += 4
            if offset == 0 || offset > out.count { throw SaveError("bloc LZ4 invalide") }
            let start = out.count - offset
            for k in 0..<mlen { out.append(out[start + k]) }
        }
        return out
    }

    /// Lit l'en-tête et la liste des plugins d'un .ess. Lève une erreur si le format est inconnu.
    public static func readSave(_ path: String) throws -> SaveInfo {
        guard let data = PyFS.read(path) else { throw SaveError("lecture impossible") }
        var r = Reader(data)
        if !Array(try r.take(MAGIC.count)).elementsEqual(MAGIC) { throw SaveError("pas une sauvegarde Skyrim") }
        _ = try r.u32()
        let version = try r.u32()
        _ = try r.u32()
        var info = SaveInfo(path: path)
        info.player = try r.wstr()
        info.level = try r.u32()
        info.location = try r.wstr()
        _ = try r.wstr()
        _ = try r.wstr()
        _ = try r.u16()
        _ = try r.take(8)
        let filetime = try r.u64()
        let width = try r.u32(), height = try r.u32()
        let compression = version >= 12 ? try r.u16() : 0
        _ = try r.take(width * height * (version >= 12 ? 4 : 3))
        let ts = -11644473600.0 + Double(filetime) / 1e7
        info.savedAt = (946684800 < ts && ts < 4102444800) ? ts : (PyFS.mtime(path) ?? 0)

        var b: Reader
        if compression != 0 {
            _ = try r.u32()
            let size = try r.u32()
            let packed = Array(try r.take(min(size, data.count - r.p)))
            let body: [UInt8]
            if compression == 2 { body = try lz4BlockPrefix(packed, NEEDED) }
            else if compression == 1 {
                guard let z = Zlib.inflate(packed, windowBits: 15, limit: NEEDED) else { throw SaveError("zlib invalide") }
                body = z
            } else { throw SaveError("compression inconnue (\(compression))") }
            b = Reader(body)
        } else { b = r }
        let formVersion = try b.u8()
        _ = try b.u32()
        let count = try b.u8()
        for _ in 0..<count { info.plugins.append(try b.wstr()) }
        if formVersion >= 78 {
            let lc = try b.u16()
            for _ in 0..<lc { info.light.append(try b.wstr()) }
        }
        return info
    }

    /// Chemins des .ess les plus récents (éventuellement antérieurs à `before`), du plus récent au plus ancien.
    public static func latestSaves(_ savesDir: String, before: Double? = nil, limit: Int = 5) -> [String] {
        guard let names = PyFS.listdir(savesDir) else { return [] }
        var items: [(Double, String)] = []
        for n in names where n.lowercased().hasSuffix(".ess") {
            let p = PyFS.join(savesDir, n)
            guard let m = PyFS.mtime(p) else { continue }
            if before == nil || m <= before! { items.append((m, p)) }
        }
        items.sort { $0.0 != $1.0 ? $0.0 > $1.0 : pyLess($1.1, $0.1) }
        return items.prefix(limit).map { $0.1 }
    }
}
