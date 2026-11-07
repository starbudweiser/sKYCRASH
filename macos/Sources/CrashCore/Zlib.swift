// zlib du système : décompression (zlib, gzip) avec limite de sortie.

import CZlib
import Foundation

enum Zlib {
    /// Décompresse `input`. `windowBits` : 15 = zlib, 31 = gzip, 47 = détection automatique.
    /// `limit` : nombre maximal d'octets en sortie (on s'arrête proprement une fois atteint). nil si les données sont invalides.
    static func inflate(_ input: [UInt8], windowBits: Int32 = 15, limit: Int = Int.max) -> [UInt8]? {
        var strm = z_stream()
        guard inflateInit2_(&strm, windowBits, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { return nil }
        defer { inflateEnd(&strm) }
        var out: [UInt8] = []
        var buf = [UInt8](repeating: 0, count: 64 * 1024)
        var ok = true
        input.withUnsafeBufferPointer { inp in
            strm.next_in = UnsafeMutablePointer(mutating: inp.baseAddress)
            strm.avail_in = UInt32(inp.count)
            while out.count < limit {
                let want = min(buf.count, limit - out.count)
                let rc: Int32 = buf.withUnsafeMutableBufferPointer { b in
                    strm.next_out = b.baseAddress
                    strm.avail_out = UInt32(want)
                    return CZlib.inflate(&strm, Z_NO_FLUSH)
                }
                let produced = want - Int(strm.avail_out)
                out.append(contentsOf: buf[0..<produced])
                if rc == Z_STREAM_END { break }
                if rc != Z_OK && rc != Z_BUF_ERROR { ok = false; break }
                if rc == Z_BUF_ERROR && produced == 0 { break }  // données tronquées : on garde ce qui est décodé
            }
        }
        return ok ? out : nil
    }
}
