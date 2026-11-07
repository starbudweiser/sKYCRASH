// Fonctions qui se comportent comme celles de Python (str, re, collections, datetime, os.path) :
// la traduction du moteur reste ligne à ligne et les résultats identiques à la version d'origine.

import Darwin
import Foundation

// MARK: - Texte

/// Espaces au sens de `str.isspace()` / `str.strip()` de Python.
@inline(__always) func pyIsSpace(_ s: Unicode.Scalar) -> Bool {
    switch s.value {
    case 0x09...0x0D, 0x1C...0x20, 0x85, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000: return true
    default: return false
    }
}

extension String {
    /// `str.strip()`
    var pyStrip: String { pyRStrip.pyLStrip }
    var pyLStrip: String {
        let u = unicodeScalars
        var i = u.startIndex
        while i < u.endIndex, pyIsSpace(u[i]) { i = u.index(after: i) }
        return String(u[i...])
    }
    var pyRStrip: String {
        let u = unicodeScalars
        var j = u.endIndex
        while j > u.startIndex {
            let p = u.index(before: j)
            if pyIsSpace(u[p]) { j = p } else { break }
        }
        return String(u[..<j])
    }
    func pyStrip(_ chars: String) -> String { pyLStrip(chars).pyRStrip(chars) }
    func pyLStrip(_ chars: String) -> String {
        let set = Set(chars.unicodeScalars)
        let u = unicodeScalars
        var i = u.startIndex
        while i < u.endIndex, set.contains(u[i]) { i = u.index(after: i) }
        return String(u[i...])
    }
    func pyRStrip(_ chars: String) -> String {
        let set = Set(chars.unicodeScalars)
        let u = unicodeScalars
        var j = u.endIndex
        while j > u.startIndex {
            let p = u.index(before: j)
            if set.contains(u[p]) { j = p } else { break }
        }
        return String(u[..<j])
    }
    /// `str.isspace()` du premier caractère (`s[:1].isspace()`).
    var firstIsSpace: Bool { unicodeScalars.first.map(pyIsSpace) ?? false }
    var pyIsBlank: Bool { pyStrip.isEmpty }
    /// `str.splitlines()` : \n, \r, \r\n, \v, \f, \x1c-\x1e, \x85,  ,  .
    var pyLines: [String] {
        var out: [String] = []
        var cur = String.UnicodeScalarView()
        var prevCR = false
        for s in unicodeScalars {
            if prevCR {
                prevCR = false
                if s == "\n" { continue }
            }
            switch s.value {
            case 0x0A, 0x0B, 0x0C, 0x1C, 0x1D, 0x1E, 0x85, 0x2028, 0x2029:
                out.append(String(cur)); cur = String.UnicodeScalarView()
            case 0x0D:
                out.append(String(cur)); cur = String.UnicodeScalarView(); prevCR = true
            default: cur.append(s)
            }
        }
        if !cur.isEmpty { out.append(String(cur)) }
        return out
    }
    /// Lignes d'un fichier texte ouvert en mode texte (retours à la ligne universels : \n, \r\n, \r seulement).
    var pyFileLines: [String] {
        var out: [String] = []
        var cur = String.UnicodeScalarView()
        var prevCR = false
        for s in unicodeScalars {
            if prevCR { prevCR = false; if s == "\n" { continue } }
            if s == "\n" { out.append(String(cur)); cur = String.UnicodeScalarView() }
            else if s == "\r" { out.append(String(cur)); cur = String.UnicodeScalarView(); prevCR = true }
            else { cur.append(s) }
        }
        if !cur.isEmpty { out.append(String(cur)) }
        return out
    }
    /// `s[:n]` (en caractères Unicode, comme Python).
    func pyPrefix(_ n: Int) -> String {
        if n <= 0 { return "" }
        let u = unicodeScalars
        guard u.count > n else { return self }
        return String(u[u.startIndex..<u.index(u.startIndex, offsetBy: n)])
    }
    var pyLen: Int { unicodeScalars.count }
    func pyLower() -> String { lowercased() }
    func hasSuffixAny(_ suffixes: [String]) -> Bool { suffixes.contains { hasSuffix($0) } }
    func hasPrefixAny(_ prefixes: [String]) -> Bool { prefixes.contains { hasPrefix($0) } }
    func pyContains(_ s: String) -> Bool { s.isEmpty || range(of: s, options: .literal) != nil }
    /// `str.split(sep)` avec un séparateur non vide.
    func pySplit(_ sep: String) -> [String] { components(separatedBy: sep) }
}

/// Comparaison par points de code, comme le tri des `str` de Python.
@inline(__always) func pyLess(_ a: String, _ b: String) -> Bool {
    var i = a.unicodeScalars.makeIterator(), j = b.unicodeScalars.makeIterator()
    while true {
        let x = i.next(), y = j.next()
        switch (x, y) {
        case (nil, nil): return false
        case (nil, _): return true
        case (_, nil): return false
        case let (x?, y?):
            if x.value != y.value { return x.value < y.value }
        }
    }
}

func pySorted(_ a: [String]) -> [String] { a.sorted(by: pyLess) }

extension Sequence {
    /// Tri stable (Python `sorted`) sur une clé numérique décroissante.
    func stableSorted(by less: (Element, Element) -> Bool) -> [Element] {
        enumerated().sorted { a, b in
            if less(a.element, b.element) { return true }
            if less(b.element, a.element) { return false }
            return a.offset < b.offset
        }.map(\.element)
    }
}

/// `dict.fromkeys(seq)` / liste sans doublons en gardant l'ordre.
func uniqueKeepingOrder<T: Hashable>(_ a: [T]) -> [T] {
    var seen = Set<T>(), out: [T] = []
    for x in a where seen.insert(x).inserted { out.append(x) }
    return out
}

// MARK: - Counter

/// `collections.Counter` : ordre d'insertion, `most_common` stable.
struct Counter {
    private(set) var keys: [String] = []
    private var counts: [String: Int] = [:]
    init() {}
    init(_ items: [String]) { for x in items { self[x] += 1 } }
    subscript(_ k: String) -> Int {
        get { counts[k] ?? 0 }
        set {
            if counts[k] == nil { keys.append(k) }
            counts[k] = newValue
        }
    }
    var isEmpty: Bool { keys.isEmpty }
    var items: [(String, Int)] { keys.map { ($0, counts[$0]!) } }
    var total: Int { counts.values.reduce(0, +) }
    func mostCommon(_ n: Int? = nil) -> [(String, Int)] {
        let s = items.stableSorted { $0.1 > $1.1 }
        if let n { return Array(s.prefix(n)) }
        return s
    }
    func contains(_ k: String) -> Bool { counts[k] != nil }
}

// MARK: - Expressions régulières

struct RxMatch {
    let ns: NSString
    let result: NSTextCheckingResult
    /// Groupe `i` (0 = tout), nil s'il n'a pas participé.
    func group(_ i: Int) -> String? {
        guard i < result.numberOfRanges else { return nil }
        let r = result.range(at: i)
        return r.location == NSNotFound ? nil : ns.substring(with: r)
    }
    func group(_ name: String) -> String? {
        let r = result.range(withName: name)
        return r.location == NSNotFound ? nil : ns.substring(with: r)
    }
    var groups: [String?] { (1..<result.numberOfRanges).map { group($0) } }
    var start: Int { result.range.location }
    var end: Int { result.range.location + result.range.length }
    /// Position en UTF-16 : à convertir avec `ns` si besoin.
    var range: NSRange { result.range }
}

/// Expression régulière à la manière du module `re` de Python.
final class Rx: @unchecked Sendable {
    let re: NSRegularExpression
    let pattern: String
    init(_ pattern: String, i: Bool = false, m: Bool = false, s: Bool = false) {
        var o: NSRegularExpression.Options = [.useUnixLineSeparators]
        if i { o.insert(.caseInsensitive) }
        if m { o.insert(.anchorsMatchLines) }
        if s { o.insert(.dotMatchesLineSeparators) }
        self.pattern = pattern
        do { re = try NSRegularExpression(pattern: pattern, options: o) } catch { fatalError("motif invalide : \(pattern) (\(error))") }
    }
    /// `re.search`
    func search(_ s: String) -> RxMatch? {
        let ns = s as NSString
        return re.firstMatch(in: s, options: [], range: NSRange(location: 0, length: ns.length)).map { RxMatch(ns: ns, result: $0) }
    }
    func test(_ s: String) -> Bool { search(s) != nil }
    /// `re.match` : ancré au début.
    func match(_ s: String) -> RxMatch? {
        let ns = s as NSString
        return re.firstMatch(in: s, options: [.anchored], range: NSRange(location: 0, length: ns.length)).map { RxMatch(ns: ns, result: $0) }
    }
    /// `re.fullmatch`
    func fullmatch(_ s: String) -> RxMatch? {
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, options: [.anchored], range: NSRange(location: 0, length: ns.length)),
              m.range.length == ns.length else { return nil }
        return RxMatch(ns: ns, result: m)
    }
    /// `re.finditer`
    func finditer(_ s: String) -> [RxMatch] {
        let ns = s as NSString
        return re.matches(in: s, options: [], range: NSRange(location: 0, length: ns.length)).map { RxMatch(ns: ns, result: $0) }
    }
    /// `re.findall` avec un seul groupe (ou aucun : le texte entier).
    func findall(_ s: String) -> [String] {
        finditer(s).map { $0.group(re.numberOfCaptureGroups >= 1 ? 1 : 0) ?? "" }
    }
    /// `re.sub` avec un modèle de remplacement à la manière de NSRegularExpression (`$1`).
    func sub(_ template: String, _ s: String) -> String {
        let ns = s as NSString
        return re.stringByReplacingMatches(in: s, options: [], range: NSRange(location: 0, length: ns.length), withTemplate: template)
    }
    /// `re.sub` avec une fonction.
    func sub(_ s: String, _ f: (RxMatch) -> String) -> String {
        let ns = s as NSString
        var out = "", last = 0
        for m in re.matches(in: s, options: [], range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            out += f(RxMatch(ns: ns, result: m))
            last = m.range.location + m.range.length
        }
        return out + ns.substring(from: last)
    }
    /// `re.split` sans groupes capturants.
    func split(_ s: String) -> [String] {
        let ns = s as NSString
        var out: [String] = [], last = 0
        for m in re.matches(in: s, options: [], range: NSRange(location: 0, length: ns.length)) {
            if m.range.length == 0 { continue }
            out.append(ns.substring(with: NSRange(location: last, length: m.range.location - last)))
            last = m.range.location + m.range.length
        }
        out.append(ns.substring(from: last))
        return out
    }
}

/// `re.escape` pour un motif simple (le texte est cherché tel quel).
func reEscape(_ s: String) -> String { NSRegularExpression.escapedPattern(for: s) }

// MARK: - Dates (sans fuseau, comme les `datetime` naïfs de Python)

public struct PyValueError: Error, CustomStringConvertible {
    public let description: String
    init(_ m: String) { description = m }
}

/// Date et heure « murales » : secondes depuis 1970 comptées comme si l'heure locale était UTC.
public struct Wall: Comparable, Hashable {
    public var secs: Int
    public static func < (a: Wall, b: Wall) -> Bool { a.secs < b.secs }

    public struct Parts { public var y, mo, d, h, mi, s: Int }

    public init(secs: Int) { self.secs = secs }

    public init(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int) throws {
        guard (1...9999).contains(y), (1...12).contains(mo), (1...Wall.daysIn(y, mo)).contains(d),
              (0...23).contains(h), (0...59).contains(mi), (0...59).contains(s)
        else { throw PyValueError("valeur de date hors limites") }
        secs = Wall.daysFromCivil(y, mo, d) * 86400 + h * 3600 + mi * 60 + s
    }

    /// `datetime.fromtimestamp(ts)` (heure locale du Mac).
    public init(timestamp ts: Double) {
        var t = time_t(ts.rounded(.down))
        var tmv = tm()
        localtime_r(&t, &tmv)
        let y = Int(tmv.tm_year) + 1900
        secs = Wall.daysFromCivil(y, Int(tmv.tm_mon) + 1, Int(tmv.tm_mday)) * 86400
            + Int(tmv.tm_hour) * 3600 + Int(tmv.tm_min) * 60 + Int(tmv.tm_sec)
    }

    /// `datetime.timestamp()` d'une date naïve : interprétée en heure locale.
    public var timestamp: Double {
        let p = parts
        var tmv = tm()
        tmv.tm_year = Int32(p.y - 1900); tmv.tm_mon = Int32(p.mo - 1); tmv.tm_mday = Int32(p.d)
        tmv.tm_hour = Int32(p.h); tmv.tm_min = Int32(p.mi); tmv.tm_sec = Int32(p.s); tmv.tm_isdst = -1
        return Double(mktime(&tmv))
    }

    public var parts: Parts {
        let days = Int((Double(secs) / 86400).rounded(.down))
        let rem = secs - days * 86400
        let (y, m, d) = Wall.civilFromDays(days)
        return Parts(y: y, mo: m, d: d, h: rem / 3600, mi: (rem % 3600) / 60, s: rem % 60)
    }

    public func adding(_ seconds: Int) -> Wall { Wall(secs: secs + seconds) }

    /// `strftime` pour les formats utilisés par l'appli (%Y %m %d %H %M %S, texte libre autour).
    public func format(_ fmt: String) -> String {
        let p = parts
        func z(_ n: Int, _ w: Int = 2) -> String { let s = String(n); return String(repeating: "0", count: max(0, w - s.count)) + s }
        var out = "", it = fmt.makeIterator()
        while let c = it.next() {
            guard c == "%", let k = it.next() else { out.append(c); continue }
            switch k {
            case "Y": out += z(p.y, 4)
            case "m": out += z(p.mo)
            case "d": out += z(p.d)
            case "H": out += z(p.h)
            case "M": out += z(p.mi)
            case "S": out += z(p.s)
            case "%": out += "%"
            default: out += "%" + String(k)
            }
        }
        return out
    }

    /// `datetime.strptime(s, "%Y-%m-%d %H:%M:%S")`
    public static func parse(_ s: String) throws -> Wall {
        guard let m = Rx(#"^(\d{4})-(\d{1,2})-(\d{1,2}) (\d{1,2}):(\d{1,2}):(\d{1,2})$"#).search(s) else {
            throw PyValueError("time data '\(s)' does not match format '%Y-%m-%d %H:%M:%S'")
        }
        let n = m.groups.map { Int($0!)! }
        do { return try Wall(n[0], n[1], n[2], n[3], n[4], n[5]) } catch {
            throw PyValueError("unconverted data or out of range: \(s)")
        }
    }

    static func daysIn(_ y: Int, _ m: Int) -> Int {
        switch m {
        case 2: return (y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)) ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }
    static func daysFromCivil(_ y0: Int, _ m: Int, _ d: Int) -> Int {
        let y = m <= 2 ? y0 - 1 : y0
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }
    static func civilFromDays(_ z0: Int) -> (Int, Int, Int) {
        let z = z0 + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (m <= 2 ? y + 1 : y, m, d)
    }
}

// MARK: - Fichiers

public enum PyFS {
    public static let fm = FileManager.default
    public static func isDir(_ p: String) -> Bool { var d: ObjCBool = false; return fm.fileExists(atPath: p, isDirectory: &d) && d.boolValue }
    public static func isFile(_ p: String) -> Bool { var d: ObjCBool = false; return fm.fileExists(atPath: p, isDirectory: &d) && !d.boolValue }
    public static func exists(_ p: String) -> Bool { fm.fileExists(atPath: p) }
    public static func isLink(_ p: String) -> Bool { (try? fm.destinationOfSymbolicLink(atPath: p)) != nil }
    public static func listdir(_ p: String) -> [String]? { try? fm.contentsOfDirectory(atPath: p) }
    public static func mtime(_ p: String) -> Double? {
        var st = stat()
        guard stat(p, &st) == 0 else { return nil }
        return Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) / 1e9
    }
    public static func size(_ p: String) -> Int? {
        var st = stat()
        guard stat(p, &st) == 0 else { return nil }
        return Int(st.st_size)
    }
    public static func read(_ p: String) -> [UInt8]? {
        guard let d = fm.contents(atPath: p) else { return nil }
        return [UInt8](d)
    }
    /// `open(p, encoding="utf-8", errors="ignore").read()` : octets invalides ignorés.
    public static func readText(_ p: String) -> String? { read(p).map { decodeUTF8Ignore($0[...]) } }
    /// `os.path.join`
    public static func join(_ parts: String...) -> String { joinList(parts) }
    public static func joinList(_ parts: [String]) -> String {
        var out = ""
        for p in parts {
            if p.hasPrefix("/") { out = p }
            else if out.isEmpty || out.hasSuffix("/") { out += p }
            else { out += "/" + p }
        }
        return out
    }
    public static func basename(_ p: String) -> String { p.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? p }
    public static func dirname(_ p: String) -> String {
        guard let i = p.lastIndex(of: "/") else { return "" }
        let head = String(p[..<i])
        // « /a » → « / » ; « a/b » → « a »
        if head.isEmpty { return "/" }
        return head.pyRStrip("/").isEmpty ? "/" : head.pyRStrip("/")
    }
    /// `os.path.splitext`
    public static func splitext(_ p: String) -> (String, String) {
        let base = basename(p)
        guard let dot = base.lastIndex(of: "."), dot != base.startIndex,
              base[..<dot].contains(where: { $0 != "." }) else { return (p, "") }
        let ext = String(base[dot...])
        return (String(p.dropLast(ext.count)), ext)
    }
    /// `os.path.normpath`
    public static func normpath(_ p: String) -> String {
        if p.isEmpty { return "." }
        let abs = p.hasPrefix("/")
        var out: [Substring] = []
        for c in p.split(separator: "/", omittingEmptySubsequences: true) {
            if c == "." { continue }
            if c == ".." {
                if let l = out.last, l != ".." { out.removeLast() }
                else if !abs { out.append(c) }
            } else { out.append(c) }
        }
        let j = out.joined(separator: "/")
        // POSIX : deux « / » initiaux sont conservés par Python, jamais trois ou plus ; ici un seul suffit
        if abs { return "/" + j }
        return j.isEmpty ? "." : j
    }
    public static func expanduser(_ p: String) -> String {
        if p == "~" { return NSHomeDirectory() }
        if p.hasPrefix("~/") { return NSHomeDirectory() + p.dropFirst(1) }
        return p
    }
    /// `glob.glob` limité à un « * » dans le dernier segment ou dans un segment intermédiaire.
    public static func glob(_ pattern: String) -> [String] {
        var gt = glob_t()
        defer { globfree(&gt) }
        guard Darwin.glob(pattern, 0, nil, &gt) == 0 else { return [] }
        var out: [String] = []
        for i in 0..<Int(gt.gl_pathc) { if let c = gt.gl_pathv[i] { out.append(String(cString: c)) } }
        return out
    }
    /// Parcours `os.walk` : appelle `visit(dossier, sous-dossiers (modifiables), fichiers)` en ordre descendant.
    public static func walk(_ top: String, _ visit: (String, inout [String], [String]) -> Bool) {
        guard let names = listdir(top) else { return }
        var dirs: [String] = [], files: [String] = []
        for n in names { if isDir(join(top, n)) { dirs.append(n) } else { files.append(n) } }
        if visit(top, &dirs, files) { return }
        for d in dirs { walk(join(top, d), visit) }
    }
}

/// `bytes.decode("utf-8", errors="ignore")`
public func decodeUTF8Ignore(_ b: ArraySlice<UInt8>) -> String {
    var out = String.UnicodeScalarView()
    var it = b.makeIterator()
    var dec = UTF8()
    loop: while true {
        switch dec.decode(&it) {
        case .scalarValue(let s): out.append(s)
        case .emptyInput: break loop
        case .error: continue
        }
    }
    return String(out)
}

/// `bytes.decode("utf-16", errors="ignore")` avec ou sans marque d'ordre des octets.
func decodeUTF16Ignore(_ b: ArraySlice<UInt8>) -> String {
    var bytes = Array(b)
    var little = true
    if bytes.count >= 2 {
        if bytes[0] == 0xFF && bytes[1] == 0xFE { bytes.removeFirst(2) }
        else if bytes[0] == 0xFE && bytes[1] == 0xFF { bytes.removeFirst(2); little = false }
    }
    var units: [UInt16] = []
    var i = 0
    while i + 1 < bytes.count {
        units.append(little ? UInt16(bytes[i]) | UInt16(bytes[i + 1]) << 8 : UInt16(bytes[i + 1]) | UInt16(bytes[i]) << 8)
        i += 2
    }
    var out = String.UnicodeScalarView()
    var it = units.makeIterator()
    var dec = UTF16()
    loop: while true {
        switch dec.decode(&it) {
        case .scalarValue(let s): out.append(s)
        case .emptyInput: break loop
        case .error: continue
        }
    }
    return String(out)
}

/// cp1252 avec remplacement, pour les noms de plugins de sauvegardes hors UTF-8.
func decodeCP1252Replace(_ b: ArraySlice<UInt8>) -> String {
    let table: [UInt32] = [0x20AC, 0xFFFD, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, 0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0xFFFD, 0x017D, 0xFFFD,
                           0xFFFD, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, 0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0xFFFD, 0x017E, 0x0178]
    var out = String.UnicodeScalarView()
    for x in b {
        let v: UInt32 = (x >= 0x80 && x < 0xA0) ? table[Int(x) - 0x80] : UInt32(x)
        out.append(Unicode.Scalar(v) ?? "\u{FFFD}")
    }
    return String(out)
}

// MARK: - JSON ordonné

/// Valeur JSON qui garde l'ordre des clés et s'écrit comme `json.dumps(..., ensure_ascii=False)`.
public indirect enum J {
    case null, bool(Bool), int(Int), double(Double), str(String), arr([J]), obj([(String, J)])

    public func dump(compact: Bool = true, indent: Int? = nil, ascii: Bool = false) -> String {
        var s = ""
        write(&s, compact: compact, indent: indent, level: 0, ascii: ascii)
        return s
    }
    private func write(_ o: inout String, compact: Bool, indent: Int?, level: Int, ascii: Bool) {
        let sepItem = compact ? "," : ", ", sepKey = compact ? ":" : ": "
        func nl(_ l: Int) -> String { indent.map { "\n" + String(repeating: " ", count: $0 * l) } ?? "" }
        switch self {
        case .null: o += "null"
        case .bool(let b): o += b ? "true" : "false"
        case .int(let i): o += String(i)
        case .double(let d): o += J.pyFloat(d)
        case .str(let s): o += J.quote(s, ascii: ascii)
        case .arr(let a):
            if a.isEmpty { o += "[]"; return }
            o += "["
            for (i, x) in a.enumerated() {
                if i > 0 { o += indent != nil ? "," : sepItem }
                o += nl(level + 1)
                x.write(&o, compact: compact, indent: indent, level: level + 1, ascii: ascii)
            }
            o += nl(level) + "]"
        case .obj(let a):
            if a.isEmpty { o += "{}"; return }
            o += "{"
            for (i, (k, v)) in a.enumerated() {
                if i > 0 { o += indent != nil ? "," : sepItem }
                o += nl(level + 1) + J.quote(k, ascii: ascii) + (indent != nil ? ": " : sepKey)
                v.write(&o, compact: compact, indent: indent, level: level + 1, ascii: ascii)
            }
            o += nl(level) + "}"
        }
    }
    /// Échappement de `json.dumps(ensure_ascii=False)`.
    public static func quote(_ s: String, ascii: Bool = false) -> String {
        var o = "\""
        for c in s.unicodeScalars {
            if ascii && c.value > 0x7E {
                if c.value == 0x7F { o += "\\u007f" }
                else if c.value > 0xFFFF {
                    let v = c.value - 0x10000
                    o += String(format: "\\u%04x\\u%04x", 0xD800 + (v >> 10), 0xDC00 + (v & 0x3FF))
                } else { o += String(format: "\\u%04x", c.value) }
                continue
            }
            switch c.value {
            case 0x22: o += "\\\""
            case 0x5C: o += "\\\\"
            case 0x0A: o += "\\n"
            case 0x0D: o += "\\r"
            case 0x09: o += "\\t"
            case 0x08: o += "\\b"
            case 0x0C: o += "\\f"
            case 0..<0x20, 0x7F...0x7F:
                if c.value == 0x7F { o.unicodeScalars.append(c) } else { o += String(format: "\\u%04x", c.value) }
            default: o.unicodeScalars.append(c)
            }
        }
        return o + "\""
    }
    public static func pyFloat(_ d: Double) -> String {
        if d == d.rounded(), abs(d) < 1e16 { return String(format: "%.1f", d) }
        return "\(d)"
    }
}

// MARK: - Lecture JSON ordonnée

extension J {
    /// Lit un document JSON en gardant l'ordre des clés ; nil si invalide.
    public static func parse(_ text: String) -> J? {
        var p = Parser(Array(text.unicodeScalars))
        p.ws()
        guard let v = p.value() else { return nil }
        p.ws()
        return p.i == p.s.count ? v : nil
    }
    public static func parse(data: Data) -> J? { String(data: data, encoding: .utf8).flatMap(parse) }

    public subscript(key: String) -> J? {
        if case .obj(let a) = self { return a.first { $0.0 == key }?.1 }
        return nil
    }
    public var string: String? { if case .str(let s) = self { return s }; return nil }
    public var intValue: Int? {
        switch self { case .int(let i): return i; case .double(let d): return Int(d); default: return nil }
    }
    public var doubleValue: Double? {
        switch self { case .int(let i): return Double(i); case .double(let d): return d; default: return nil }
    }
    public var array: [J]? { if case .arr(let a) = self { return a }; return nil }
    public var object: [(String, J)]? { if case .obj(let a) = self { return a }; return nil }
    public var isNull: Bool { if case .null = self { return true }; return false }

    /// Remplace ou ajoute `key` dans un objet (en gardant l'ordre).
    public func setting(_ key: String, _ v: J) -> J {
        guard case .obj(var a) = self else { return .obj([(key, v)]) }
        if let i = a.firstIndex(where: { $0.0 == key }) { a[i].1 = v } else { a.append((key, v)) }
        return .obj(a)
    }

    struct Parser {
        let s: [Unicode.Scalar]
        var i = 0
        init(_ s: [Unicode.Scalar]) { self.s = s }
        mutating func ws() { while i < s.count, s[i] == " " || s[i] == "\n" || s[i] == "\t" || s[i] == "\r" { i += 1 } }
        mutating func value() -> J? {
            guard i < s.count else { return nil }
            switch s[i] {
            case "{":
                i += 1; var items: [(String, J)] = []
                ws()
                if i < s.count, s[i] == "}" { i += 1; return .obj(items) }
                while true {
                    ws()
                    guard let k = string() else { return nil }
                    ws()
                    guard i < s.count, s[i] == ":" else { return nil }
                    i += 1; ws()
                    guard let v = value() else { return nil }
                    if let idx = items.firstIndex(where: { $0.0 == k }) { items[idx].1 = v } else { items.append((k, v)) }
                    ws()
                    guard i < s.count else { return nil }
                    if s[i] == "," { i += 1; continue }
                    if s[i] == "}" { i += 1; return .obj(items) }
                    return nil
                }
            case "[":
                i += 1; var items: [J] = []
                ws()
                if i < s.count, s[i] == "]" { i += 1; return .arr(items) }
                while true {
                    ws()
                    guard let v = value() else { return nil }
                    items.append(v)
                    ws()
                    guard i < s.count else { return nil }
                    if s[i] == "," { i += 1; continue }
                    if s[i] == "]" { i += 1; return .arr(items) }
                    return nil
                }
            case "\"": return string().map { .str($0) }
            case "t": return lit("true", .bool(true))
            case "f": return lit("false", .bool(false))
            case "n": return lit("null", .null)
            default: return number()
            }
        }
        mutating func lit(_ w: String, _ v: J) -> J? {
            let u = Array(w.unicodeScalars)
            guard i + u.count <= s.count, Array(s[i..<(i + u.count)]) == u else { return nil }
            i += u.count; return v
        }
        mutating func number() -> J? {
            let st = i
            while i < s.count, "+-0123456789.eE".unicodeScalars.contains(s[i]) { i += 1 }
            guard i > st else { return nil }
            let t = String(String.UnicodeScalarView(s[st..<i]))
            if let n = Int(t) { return .int(n) }
            if let d = Double(t) { return .double(d) }
            return nil
        }
        mutating func string() -> String? {
            guard i < s.count, s[i] == "\"" else { return nil }
            i += 1
            var out = String.UnicodeScalarView()
            while i < s.count {
                let c = s[i]; i += 1
                if c == "\"" { return String(out) }
                if c != "\\" { out.append(c); continue }
                guard i < s.count else { return nil }
                let e = s[i]; i += 1
                switch e {
                case "n": out.append("\n"); case "t": out.append("\t"); case "r": out.append("\r")
                case "b": out.append("\u{8}"); case "f": out.append("\u{c}")
                case "u":
                    guard let hi = hex4() else { return nil }
                    if (0xD800..<0xDC00).contains(hi), i + 1 < s.count, s[i] == "\\", s[i + 1] == "u" {
                        i += 2
                        guard let lo = hex4() else { return nil }
                        let cp = 0x10000 + ((hi - 0xD800) << 10) + (lo - 0xDC00)
                        guard let u = Unicode.Scalar(cp) else { return nil }
                        out.append(u)
                    } else {
                        out.append(Unicode.Scalar(hi) ?? "\u{FFFD}")
                    }
                default: out.append(e)
                }
            }
            return nil
        }
        mutating func hex4() -> UInt32? {
            guard i + 4 <= s.count else { return nil }
            var v: UInt32 = 0
            for k in 0..<4 {
                guard let d = Int(String(s[i + k]), radix: 16) else { return nil }
                v = v * 16 + UInt32(d)
            }
            i += 4; return v
        }
    }
}
