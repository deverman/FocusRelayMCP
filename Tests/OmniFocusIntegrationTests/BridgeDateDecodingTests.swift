import Foundation
import Testing
@testable import OmniFocusAutomation
@testable import OmniFocusCore

@Test
func taskPayloadDecodesStandardISO8601Dates() throws {
    let decoder = BridgeDateDecoding.makeJSONDecoder()
    let data = Data(
        """
        {
          "items": [
            {
              "id": "task-1",
              "name": "Standard",
              "dueDate": "2026-04-04T12:00:00Z",
              "plannedDate": null,
              "deferDate": "2026-04-05T08:30:00Z",
              "completionDate": null,
              "completed": false,
              "flagged": false,
              "available": true
            }
          ],
          "nextCursor": null,
          "returnedCount": 1,
          "totalCount": 1
        }
        """.utf8
    )

    let page = try decoder.decode(Page<TaskItemPayload>.self, from: data)
    let item = try #require(page.items.first)

    #expect(page.items.count == 1)
    expectDate(item.dueDate, equals: 1_775_304_000.0)
    expectDate(item.deferDate, equals: 1_775_377_800.0)
    #expect(item.plannedDate == nil)
    #expect(item.completionDate == nil)
}

@Test
func taskPayloadDecodesFractionalISO8601Dates() throws {
    let decoder = BridgeDateDecoding.makeJSONDecoder()
    let data = Data(
        """
        {
          "items": [
            {
              "id": "task-2",
              "name": "Fractional",
              "dueDate": "2026-04-04T12:00:00.000Z",
              "plannedDate": "2026-04-04T14:15:16.250Z",
              "deferDate": null,
              "completionDate": null,
              "completed": false,
              "flagged": true,
              "available": true
            }
          ],
          "nextCursor": null,
          "returnedCount": 1,
          "totalCount": 1
        }
        """.utf8
    )

    let page = try decoder.decode(Page<TaskItemPayload>.self, from: data)
    let item = try #require(page.items.first)

    #expect(page.items.count == 1)
    expectDate(item.dueDate, equals: 1_775_304_000.0)
    expectDate(item.plannedDate, equals: 1_775_312_116.25)
    #expect(item.deferDate == nil)
}

@Test
func projectPayloadDecodesStandardISO8601Dates() throws {
    let decoder = BridgeDateDecoding.makeJSONDecoder()
    let data = Data(
        """
        {
          "items": [
            {
              "id": "project-1",
              "name": "Standard",
              "status": "active",
              "flagged": false,
              "lastReviewDate": "2026-04-04T12:00:00Z",
              "nextReviewDate": "2026-04-11T12:00:00Z",
              "completionDate": null
            }
          ],
          "nextCursor": null,
          "returnedCount": 1,
          "totalCount": 1
        }
        """.utf8
    )

    let page = try decoder.decode(Page<ProjectItemPayload>.self, from: data)
    let item = try #require(page.items.first)

    #expect(page.items.count == 1)
    expectDate(item.lastReviewDate, equals: 1_775_304_000.0)
    expectDate(item.nextReviewDate, equals: 1_775_908_800.0)
    #expect(item.completionDate == nil)
}

@Test
func projectPayloadDecodesFractionalISO8601Dates() throws {
    let decoder = BridgeDateDecoding.makeJSONDecoder()
    let data = Data(
        """
        {
          "items": [
            {
              "id": "project-2",
              "name": "Fractional",
              "status": "done",
              "flagged": true,
              "lastReviewDate": "2026-04-04T12:00:00.125Z",
              "nextReviewDate": "2026-04-11T12:00:00.500Z",
              "completionDate": "2026-04-12T09:45:30.000Z"
            }
          ],
          "nextCursor": null,
          "returnedCount": 1,
          "totalCount": 1
        }
        """.utf8
    )

    let page = try decoder.decode(Page<ProjectItemPayload>.self, from: data)
    let item = try #require(page.items.first)

    #expect(page.items.count == 1)
    expectDate(item.lastReviewDate, equals: 1_775_304_000.125)
    expectDate(item.nextReviewDate, equals: 1_775_908_800.5)
    expectDate(item.completionDate, equals: 1_775_987_130.0)
}

@Test
func bridgeDateDecodingRejectsUnsupportedFormats() {
    let decoder = BridgeDateDecoding.makeJSONDecoder()
    let invalidPayloads = [
        """
        {
          "items": [{ "id": "task-3", "name": "Date Only", "dueDate": "2026-04-04" }],
          "nextCursor": null,
          "returnedCount": 1,
          "totalCount": 1
        }
        """,
        """
        {
          "items": [{ "id": "task-4", "name": "No TZ", "dueDate": "2026-04-04T12:00:00" }],
          "nextCursor": null,
          "returnedCount": 1,
          "totalCount": 1
        }
        """
    ]

    for payload in invalidPayloads {
        var didThrow = false
        do {
            _ = try decoder.decode(Page<TaskItemPayload>.self, from: Data(payload.utf8))
        } catch {
            didThrow = true
        }
        #expect(didThrow)
    }
}

private func expectDate(
    _ date: Date?,
    equals expected: TimeInterval,
    tolerance: TimeInterval = 0.000_001
) {
    guard let date else {
        Issue.record("Expected date to be present")
        return
    }

    let delta = abs(date.timeIntervalSince1970 - expected)
    #expect(delta <= tolerance, "Expected \(expected), got \(date.timeIntervalSince1970)")
}
