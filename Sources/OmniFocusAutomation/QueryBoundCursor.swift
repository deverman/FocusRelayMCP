import CryptoKit
import Foundation
import OmniFocusCore

enum QueryBoundCursor {
    private struct Envelope: Codable {
        let version: Int
        let offset: String
        let tool: String?
        let queryFingerprint: String?
        let dimensionFingerprints: [String: String]?
    }

    struct QueryIdentity: Equatable, Sendable {
        let tool: String
        let fingerprint: String
        let dimensionFingerprints: [String: String]
    }

    private static let version = 2

    static func taskIdentity(for filter: TaskFilter) throws -> QueryIdentity {
        try queryIdentity(
            tool: "list_tasks",
            input: TaskFilter(
                ids: filter.ids,
                completed: filter.completed,
                flagged: filter.flagged,
                availableOnly: filter.availableOnly,
                inboxView: filter.inboxView ?? "available",
                project: filter.project,
                tags: filter.tags,
                dueBefore: filter.dueBefore,
                dueAfter: filter.dueAfter,
                deferBefore: filter.deferBefore,
                deferAfter: filter.deferAfter,
                plannedBefore: filter.plannedBefore,
                plannedAfter: filter.plannedAfter,
                completedBefore: filter.completedBefore,
                completedAfter: filter.completedAfter,
                search: filter.search,
                inboxOnly: filter.inboxOnly ?? false,
                projectView: filter.projectView,
                maxEstimatedMinutes: filter.maxEstimatedMinutes,
                minEstimatedMinutes: filter.minEstimatedMinutes,
                includeTotalCount: filter.includeTotalCount ?? false
            )
        )
    }

    static func queryIdentity<Input: Encodable>(
        tool: String,
        input: Input
    ) throws -> QueryIdentity {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let inputData = try encoder.encode(input)
        let fingerprint = sha256(Data(tool.utf8) + Data([0]) + inputData)
        let dimensions = try dimensionFingerprints(from: inputData)
        return QueryIdentity(
            tool: tool,
            fingerprint: fingerprint,
            dimensionFingerprints: dimensions
        )
    }

    static func bridgePage(
        from page: PageRequest,
        identity: QueryIdentity
    ) throws -> PageRequest {
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
        guard let cursorTool = envelope.tool,
              let cursorFingerprint = envelope.queryFingerprint,
              let cursorDimensions = envelope.dimensionFingerprints else {
            throw cursorError("malformed or unsupported")
        }
        guard cursorTool == identity.tool,
              cursorFingerprint == identity.fingerprint else {
            let changedDimensions = changedDimensions(
                cursorTool: cursorTool,
                cursorDimensions: cursorDimensions,
                current: identity
            )
            throw cursorError(
                """
                for a different query \
                (cursorVersion=\(version), tool=\(identity.tool), \
                cursorFingerprint=\(shortFingerprint(cursorFingerprint)), \
                currentFingerprint=\(shortFingerprint(identity.fingerprint)), \
                changedDimensions=\(changedDimensions.joined(separator: ",")))
                """
            )
        }
        return PageRequest(limit: page.limit, cursor: envelope.offset)
    }

    static func publicPage<Item>(
        from page: Page<Item>,
        identity: QueryIdentity
    ) throws -> Page<Item> where Item: Codable & Sendable {
        let nextCursor = try page.nextCursor.map { offset in
            try encode(
                Envelope(
                    version: version,
                    offset: offset,
                    tool: identity.tool,
                    queryFingerprint: identity.fingerprint,
                    dimensionFingerprints: identity.dimensionFingerprints
                )
            )
        }
        return Page(
            items: page.items,
            nextCursor: nextCursor,
            returnedCount: page.returnedCount,
            totalCount: page.totalCount,
            warnings: page.warnings,
            unresolvedIDs: page.unresolvedIDs
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

    private static func dimensionFingerprints(from inputData: Data) throws -> [String: String] {
        let object = try JSONSerialization.jsonObject(
            with: inputData,
            options: [.fragmentsAllowed]
        )
        guard let dictionary = object as? [String: Any] else {
            return ["input": sha256(inputData)]
        }

        return try dictionary.reduce(into: [:]) { result, element in
            let data = try JSONSerialization.data(
                withJSONObject: element.value,
                options: [.sortedKeys, .fragmentsAllowed, .withoutEscapingSlashes]
            )
            result[element.key] = sha256(data)
        }
    }

    private static func changedDimensions(
        cursorTool: String,
        cursorDimensions: [String: String],
        current: QueryIdentity
    ) -> [String] {
        guard cursorTool == current.tool else { return ["tool"] }
        return Set(cursorDimensions.keys)
            .union(current.dimensionFingerprints.keys)
            .filter {
                cursorDimensions[$0] != current.dimensionFingerprints[$0]
            }
            .sorted()
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func shortFingerprint(_ value: String) -> String {
        String(value.prefix(12))
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
