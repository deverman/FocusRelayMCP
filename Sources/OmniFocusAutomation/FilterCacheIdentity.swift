import CryptoKit
import Foundation
import OmniFocusCore

/// Derives a cache identity from a filter's own encoding, so a cached page can
/// never satisfy a different query.
///
/// The previous key listed its fields by hand and stayed correct only because a
/// separate `shouldBypassCache` list happened to name every field the key
/// omitted. Nothing connected the two. #88 nearly shipped a `rootOnly`
/// omission that would have served filed projects to a request for unfiled
/// ones — no error, no warning, a plausible-looking answer. #171 then added
/// `searches` to both filters, which the hand-written key also does not name.
///
/// Deriving from the encoded filter removes the class: a new filter field
/// changes the identity automatically, because it changes the encoding.
enum FilterCacheIdentity {
    /// Filter fields whose presence means the result must not be cached at all.
    /// These are time-relative or intentionally live, so a five-minute entry
    /// would be wrong rather than merely stale.
    ///
    /// Kept as an explicit list because "do not cache" is a judgement about
    /// semantics, not something derivable from the encoding — but it is now
    /// checked against the encoded filter, so a renamed field cannot silently
    /// stop matching.
    static let uncacheableProjectFields: Set<String> = [
        "reviewDueBefore", "reviewDueAfter", "reviewPerspective",
        "completed", "completedBefore", "completedAfter",
        "searches"
    ]

    static let uncacheableTagFields: Set<String> = ["searches"]

    /// True when the filter carries any field that makes caching unsafe.
    static func isCacheable<Filter: Encodable>(
        _ filter: Filter,
        uncacheableFields: Set<String>
    ) throws -> Bool {
        let present = try presentFieldNames(of: filter)
        return present.isDisjoint(with: uncacheableFields)
    }

    /// Names of the filter's non-nil fields. Absent fields do not encode, so
    /// this reflects what the caller actually asked for.
    static func presentFieldNames<Filter: Encodable>(of filter: Filter) throws -> Set<String> {
        let data = try encoder().encode(filter)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        return Set(object.keys)
    }

    /// Stable fingerprint of the filter's full encoded content.
    static func fingerprint<Filter: Encodable>(_ filter: Filter) throws -> String {
        let data = try encoder().encode(filter)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        // Sorted keys so identical filters always encode identically.
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
