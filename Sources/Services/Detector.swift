import Foundation

/// Guesses which tool (and mode) best fits a piece of clipboard text using simple heuristics.
enum Detector {
    static func detect(_ raw: String) -> (tool: Tool, mode: Int) {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("{") || s.hasPrefix("[") { return (.json, 0) }
        if s.wholeMatch(of: #/[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*/#) != nil,
           s.hasPrefix("eyJ") { // base64url of `{"`, how every JWT header starts
            return (.jwt, 0)
        }
        if s.wholeMatch(of: #/-?\d{10}(\d{3})?/#) != nil { return (.timestamp, 0) }
        if s.contains(#/%[0-9A-Fa-f]{2}/#) { return (.url, 1) }
        let compact = s.filter { !$0.isWhitespace }
        if compact.count >= 8, compact.count % 4 == 0,
           compact.wholeMatch(of: #/[A-Za-z0-9+\/]+={0,2}/#) != nil,
           compact.contains(where: { $0.isNumber || $0 == "=" || $0 == "+" || $0 == "/" }),
           Data(base64Encoded: compact) != nil {
            return (.base64, 1)
        }
        if s.count < 200, !s.contains("\n") { return (.textCase, 0) }
        return (.hash, 0)
    }
}
