import Foundation
import OmniFocusCore

enum QueryBoundCursor {
    private struct Envelope: Codable {
        let version: Int
        let offset: String
        let queryKey: String
    }

    private static let version = 1

    static func queryKey<Input: Encodable>(tool: String, input: Input) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let inputData = try encoder.encode(input)
        return tool + ":" + inputData.base64EncodedString()
    }

    static func bridgePage(from page: PageRequest, queryKey: String) throws -> PageRequest {
        guard let cursor = page.cursor else { return page }
        let envelope: Envelope
        do {
            envelope = try decode(cursor)
        } catch {
            throw cursorError("malformed or unsupported")
        }
        guard envelope.version == version else {
            throw cursorError("from an unsupported version")
        }
        guard envelope.queryKey == queryKey else {
            throw cursorError("for a different query")
        }
        return PageRequest(limit: page.limit, cursor: envelope.offset)
    }

    static func publicPage<Item>(
        from page: Page<Item>,
        queryKey: String
    ) throws -> Page<Item> where Item: Codable & Sendable {
        let nextCursor = try page.nextCursor.map { offset in
            try encode(Envelope(version: version, offset: offset, queryKey: queryKey))
        }
        return Page(
            items: page.items,
            nextCursor: nextCursor,
            returnedCount: page.returnedCount,
            totalCount: page.totalCount,
            warnings: page.warnings
        )
    }

    private static func encode(_ envelope: Envelope) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(envelope)
        return data.base64URLEncodedString()
    }

    private static func decode(_ value: String) throws -> Envelope {
        guard let data = Data(base64URLString: value) else {
            throw cursorError("malformed")
        }
        return try JSONDecoder().decode(Envelope.self, from: data)
    }

    private static func cursorError(_ reason: String) -> AutomationError {
        .executionFailed(
            "Pagination cursor is \(reason). Restart pagination from the first page."
        )
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLString: String) {
        var base64 = base64URLString
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        self.init(base64Encoded: base64)
    }
}
