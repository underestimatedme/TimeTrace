import Foundation

/// Shared JSON coders: snake_case keys, RFC3339 dates (fractional seconds accepted).
enum JSONCoding {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(ISO8601.string(from: date))
        }
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let raw = try c.decode(String.self)
            if let date = ISO8601.date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unrecognized date: \(raw)")
        }
        return d
    }()
}

enum ISO8601 {
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// JS `toISOString()` style: `2026-09-04T02:00:00.000Z`.
    static func string(from date: Date) -> String { fractional.string(from: date) }

    static func date(from raw: String) -> Date? {
        if let d = fractional.date(from: raw) { return d }
        if let d = plain.date(from: raw) { return d }
        // Go RFC3339Nano may carry 4-9 fractional digits; trim to 3.
        if let range = raw.range(of: #"\.\d+"#, options: .regularExpression) {
            let digits = raw[range].dropFirst()
            let trimmed = raw.replacingCharacters(in: range, with: "." + String(digits.prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0))
            if let d = fractional.date(from: trimmed) { return d }
        }
        if raw.count == 10, let d = dateOnly.date(from: raw) { return d }
        return nil
    }
}
