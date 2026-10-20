import Foundation
import CryptoKit

/// Every tool listed in the sidebar, with its presentation metadata and optional modes.
enum Tool: String, CaseIterable, Identifiable {
    case json, base64, url, jwt, hash, timestamp, uuid, textCase

    var id: String { rawValue }

    var title: String {
        switch self {
        case .json: return "JSON Formatter"
        case .base64: return "Base64"
        case .url: return "URL Encoding"
        case .jwt: return "JWT Decoder"
        case .hash: return "Hash Generator"
        case .timestamp: return "Unix Timestamp"
        case .uuid: return "UUID Generator"
        case .textCase: return "Text Case"
        }
    }

    var symbol: String {
        switch self {
        case .json: return "curlybraces"
        case .base64: return "textformat.abc"
        case .url: return "link"
        case .jwt: return "key"
        case .hash: return "number"
        case .timestamp: return "clock"
        case .uuid: return "dice"
        case .textCase: return "textformat"
        }
    }

    var modes: [String] {
        switch self {
        case .json: return ["Format", "Minify"]
        case .base64, .url: return ["Encode", "Decode"]
        case .uuid: return ["lowercase", "UPPERCASE"]
        case .textCase: return ["camelCase", "snake_case", "kebab-case", "UPPERCASE"]
        default: return []
        }
    }

    /// Whether swapping output into input should also flip encode/decode.
    var isTwoWay: Bool { self == .base64 || self == .url }

    var hint: String {
        switch self {
        case .json: return "Paste JSON to validate, pretty-print or minify it."
        case .base64: return "Paste text to encode, or a Base64 string to decode."
        case .url: return "Paste text to percent-encode, or an encoded URL to decode."
        case .jwt: return "Paste a JSON Web Token (xxxxx.yyyyy.zzzzz) to inspect it."
        case .hash: return "Type text, or drop / choose a file to hash it."
        case .timestamp: return "Paste a Unix timestamp (seconds or ms) or an ISO 8601 date."
        case .uuid: return "Enter how many UUIDs to generate (1–10000)."
        case .textCase: return "Paste words or identifiers, one per line, to convert their case."
        }
    }
}

/// A user-facing conversion failure, optionally pinned to a line/column in the input.
struct ToolError: Error, Equatable {
    var message: String
    var line: Int? = nil
    var column: Int? = nil

    var description: String {
        if let line, let column { return "\(message) — line \(line), column \(column)" }
        return message
    }
}

/// The result of running a tool: displayable text plus raw bytes when the output is not UTF-8.
struct ToolOutput {
    var text: String = ""
    var binary: Data? = nil
}

/// Pure, thread-safe implementations of every converter; safe to call off the main thread.
enum Converters {
    static func run(_ tool: Tool, mode: Int, input: String) -> Result<ToolOutput, ToolError> {
        switch tool {
        case .json: return json(input, minify: mode == 1)
        case .base64: return mode == 0 ? .success(ToolOutput(text: Data(input.utf8).base64EncodedString())) : base64Decode(input)
        case .url: return urlCoding(input, decode: mode == 1)
        case .jwt: return jwt(input)
        case .hash: return .success(ToolOutput(text: hashes(of: Data(input.utf8))))
        case .timestamp: return timestamp(input)
        case .uuid: return uuids(input, uppercase: mode == 1)
        case .textCase: return .success(ToolOutput(text: convertCase(input, mode: mode)))
        }
    }

    // MARK: JSON

    static func json(_ input: String, minify: Bool) -> Result<ToolOutput, ToolError> {
        let data = Data(input.utf8)
        do {
            let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            var options: JSONSerialization.WritingOptions = [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes]
            if !minify { options.insert(.prettyPrinted) }
            let out = try JSONSerialization.data(withJSONObject: object, options: options)
            return .success(ToolOutput(text: String(decoding: out, as: UTF8.self)))
        } catch let error as NSError {
            return .failure(jsonError(error, data: data))
        }
    }

    /// Builds a readable error with line/column from NSDebugDescription or the error index.
    private static func jsonError(_ error: NSError, data: Data) -> ToolError {
        let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError
        let debug = (error.userInfo[NSDebugDescriptionErrorKey] as? String)
            ?? (underlying?.userInfo[NSDebugDescriptionErrorKey] as? String)
            ?? error.localizedDescription
        var result = ToolError(message: "Invalid JSON: \(debug)")
        if let match = debug.firstMatch(of: #/line (\d+), column (\d+)/#) {
            result.line = Int(match.1)
            result.column = Int(match.2)
        } else if let index = (error.userInfo["NSJSONSerializationErrorIndex"] as? Int)
                    ?? (underlying?.userInfo["NSJSONSerializationErrorIndex"] as? Int) {
            var line = 1, column = 1
            for byte in data.prefix(index) {
                if byte == 0x0A { line += 1; column = 1 } else if byte & 0xC0 != 0x80 { column += 1 }
            }
            result.line = line
            result.column = column
        }
        return result
    }

    // MARK: Base64 & URL

    static func base64URLDecode(_ string: String) -> Data? {
        var s = string.filter { !$0.isWhitespace }
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s.append("=") }
        return Data(base64Encoded: s)
    }

    static func base64Decode(_ input: String) -> Result<ToolOutput, ToolError> {
        guard let data = base64URLDecode(input) else {
            return .failure(ToolError(message: "Not valid Base64: only A–Z, a–z, 0–9, +, /, - , _ and = padding are allowed."))
        }
        if let text = String(data: data, encoding: .utf8) { return .success(ToolOutput(text: text)) }
        return .success(ToolOutput(text: "Binary data (\(data.count) bytes, not UTF-8) — hex preview:\n\n" + hexPreview(data), binary: data))
    }

    static func hexPreview(_ data: Data, limit: Int = 1024) -> String {
        let bytes = Array(data.prefix(limit))
        var lines: [String] = []
        for start in stride(from: 0, to: bytes.count, by: 16) {
            let row = bytes[start..<min(start + 16, bytes.count)]
            let hex = row.map { String(format: "%02x", $0) }.joined(separator: " ")
            let ascii = String(row.map { (0x20...0x7E).contains($0) ? Character(UnicodeScalar($0)) : "." })
            lines.append(String(format: "%08x  ", start) + hex.padding(toLength: 48, withPad: " ", startingAt: 0) + "  " + ascii)
        }
        if data.count > limit { lines.append("… \(data.count - limit) more bytes") }
        return lines.joined(separator: "\n")
    }

    static func urlCoding(_ input: String, decode: Bool) -> Result<ToolOutput, ToolError> {
        if decode {
            guard let out = input.replacingOccurrences(of: "+", with: " ").removingPercentEncoding else {
                return .failure(ToolError(message: "Malformed percent-encoding (each % must be followed by two hex digits forming valid UTF-8)."))
            }
            return .success(ToolOutput(text: out))
        }
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return .success(ToolOutput(text: input.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""))
    }

    // MARK: JWT

    static func jwt(_ input: String) -> Result<ToolOutput, ToolError> {
        let parts = input.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else {
            return .failure(ToolError(message: "A JWT has 3 dot-separated segments; found \(parts.count)."))
        }
        let names = ["header", "payload"]
        var sections: [String] = []
        var payload: [String: Any] = [:]
        for index in 0..<2 {
            guard let data = base64URLDecode(String(parts[index])) else {
                return .failure(ToolError(message: "Segment \(index + 1) (\(names[index])) is not valid base64url."))
            }
            guard let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let pretty = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else {
                return .failure(ToolError(message: "Segment \(index + 1) (\(names[index])) does not decode to a JSON object."))
            }
            if index == 1 { payload = dict }
            sections.append(names[index].uppercased() + "\n" + String(decoding: pretty, as: UTF8.self))
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        let relative = RelativeDateTimeFormatter()
        var claims: [String] = []
        for key in ["exp", "iat", "nbf"] {
            guard let value = (payload[key] as? NSNumber)?.doubleValue else { continue }
            let date = Date(timeIntervalSince1970: value)
            var line = "\(key): \(formatter.string(from: date)) (\(relative.localizedString(for: date, relativeTo: Date())))"
            if key == "exp" && date < Date() { line += " — EXPIRED" }
            claims.append(line)
        }
        if !claims.isEmpty { sections.append("CLAIMS\n" + claims.joined(separator: "\n")) }
        sections.append("SIGNATURE\n" + (parts[2].isEmpty ? "none (unsigned token)" : "\(parts[2]) — NOT verified"))
        return .success(ToolOutput(text: sections.joined(separator: "\n\n")))
    }

    // MARK: Hashes

    static func hashes(of data: Data) -> String {
        format(md5: Insecure.MD5.hash(data: data), sha1: Insecure.SHA1.hash(data: data),
               sha256: SHA256.hash(data: data), sha512: SHA512.hash(data: data))
    }

    /// Streams a file through all four hashers in 1 MB chunks so large files never load fully.
    static func hashFile(at url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var md5 = Insecure.MD5(), sha1 = Insecure.SHA1(), sha256 = SHA256(), sha512 = SHA512()
        var total = 0
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            md5.update(data: chunk); sha1.update(data: chunk); sha256.update(data: chunk); sha512.update(data: chunk)
            total += chunk.count
        }
        let size = ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file)
        return "File: \(url.lastPathComponent) (\(size))\n\n" +
            format(md5: md5.finalize(), sha1: sha1.finalize(), sha256: sha256.finalize(), sha512: sha512.finalize())
    }

    private static func format<A: Digest, B: Digest, C: Digest, D: Digest>(md5: A, sha1: B, sha256: C, sha512: D) -> String {
        func hex<T: Digest>(_ d: T) -> String { d.map { String(format: "%02x", $0) }.joined() }
        return "MD5     \(hex(md5))\nSHA1    \(hex(sha1))\nSHA256  \(hex(sha256))\nSHA512  \(hex(sha512))"
    }

    // MARK: Timestamps

    static func timestamp(_ input: String) -> Result<ToolOutput, ToolError> {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let local = DateFormatter()
        local.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS zzz"
        let utc = DateFormatter()
        utc.timeZone = TimeZone(identifier: "UTC")
        utc.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS 'UTC'"
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let relative = RelativeDateTimeFormatter()

        func describe(_ date: Date, header: String) -> ToolOutput {
            ToolOutput(text: """
            \(header)
            Local     \(local.string(from: date))
            UTC       \(utc.string(from: date))
            ISO 8601  \(iso.string(from: date))
            Relative  \(relative.localizedString(for: date, relativeTo: Date()))
            Seconds   \(Int64(date.timeIntervalSince1970.rounded(.down)))
            Millis    \(Int64((date.timeIntervalSince1970 * 1000).rounded()))
            """)
        }

        if let number = Double(s) {
            let isMillis = abs(number) >= 100_000_000_000
            let date = Date(timeIntervalSince1970: isMillis ? number / 1000 : number)
            return .success(describe(date, header: "Interpreted as \(isMillis ? "milliseconds" : "seconds") since 1970\n"))
        }
        let plainISO = ISO8601DateFormatter()
        let dateOnly = ISO8601DateFormatter()
        dateOnly.formatOptions = [.withFullDate]
        let spaced = DateFormatter()
        spaced.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = iso.date(from: s) ?? plainISO.date(from: s) ?? spaced.date(from: s) ?? dateOnly.date(from: s) {
            return .success(describe(date, header: "Parsed date\n"))
        }
        return .failure(ToolError(message: "Enter a Unix timestamp (10 or 13 digits) or an ISO 8601 date like 2026-01-31T12:00:00Z."))
    }

    // MARK: UUID & text case

    static func uuids(_ input: String, uppercase: Bool) -> Result<ToolOutput, ToolError> {
        guard let count = Int(input.trimmingCharacters(in: .whitespacesAndNewlines)), (1...10_000).contains(count) else {
            return .failure(ToolError(message: "Enter a whole number between 1 and 10000."))
        }
        let list = (0..<count).map { _ in uppercase ? UUID().uuidString : UUID().uuidString.lowercased() }
        return .success(ToolOutput(text: list.joined(separator: "\n")))
    }

    /// Splits identifiers on separators and lower→upper camel boundaries.
    static func words(_ s: String) -> [String] {
        var words: [String] = [], current = ""
        var previous: Character?
        for ch in s {
            if ch.isLetter || ch.isNumber {
                if let p = previous, ch.isUppercase, p.isLowercase || p.isNumber, !current.isEmpty {
                    words.append(current); current = ""
                }
                current.append(ch)
            } else if !current.isEmpty {
                words.append(current); current = ""
            }
            previous = ch
        }
        if !current.isEmpty { words.append(current) }
        return words.map { $0.lowercased() }
    }

    static func convertCase(_ input: String, mode: Int) -> String {
        input.components(separatedBy: "\n").map { line in
            let w = words(line)
            switch mode {
            case 0: return (w.first ?? "") + w.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
            case 1: return w.joined(separator: "_")
            case 2: return w.joined(separator: "-")
            default: return line.uppercased()
            }
        }.joined(separator: "\n")
    }
}
