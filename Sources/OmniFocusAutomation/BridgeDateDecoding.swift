import Foundation

enum BridgeDateDecoding {
    private static let fractionalISO8601Formatter = LockedISO8601Formatter(
        formatOptions: [.withInternetDateTime, .withFractionalSeconds]
    )

    private static let standardISO8601Formatter = LockedISO8601Formatter(
        formatOptions: [.withInternetDateTime]
    )

    static func makeJSONDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        configure(decoder)
        return decoder
    }

    static func configure(_ decoder: JSONDecoder) {
        decoder.dateDecodingStrategy = .custom { decoder in
            try decodeDate(from: decoder)
        }
    }

    private static func decodeDate(from decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)

        if let date = fractionalISO8601Formatter.date(from: string)
            ?? standardISO8601Formatter.date(from: string) {
            return date
        }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Expected ISO8601 date string with or without fractional seconds."
        )
    }
}

private final class LockedISO8601Formatter: @unchecked Sendable {
    private let lock = NSLock()
    private let formatter: ISO8601DateFormatter

    init(formatOptions: ISO8601DateFormatter.Options) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = formatOptions
        self.formatter = formatter
    }

    func date(from string: String) -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return formatter.date(from: string)
    }
}
