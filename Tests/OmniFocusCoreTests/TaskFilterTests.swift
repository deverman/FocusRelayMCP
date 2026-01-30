import Foundation
import Testing
@testable import OmniFocusCore

@Test
func taskFilterWithDateRanges() throws {
    let now = Date()
    let yesterday = now.addingTimeInterval(-86400)
    let tomorrow = now.addingTimeInterval(86400)
    
    let filter = TaskFilter(
        completed: false,
        dueBefore: tomorrow,
        dueAfter: yesterday,
        deferBefore: tomorrow,
        deferAfter: yesterday,
        completedBefore: now,
        completedAfter: yesterday,
        maxEstimatedMinutes: 60,
        minEstimatedMinutes: 15
    )
    
    #expect(filter.completed == false)
    #expect(filter.dueBefore == tomorrow)
    #expect(filter.dueAfter == yesterday)
    #expect(filter.deferBefore == tomorrow)
    #expect(filter.deferAfter == yesterday)
    #expect(filter.completedBefore == now)
    #expect(filter.completedAfter == yesterday)
    #expect(filter.maxEstimatedMinutes == 60)
    #expect(filter.minEstimatedMinutes == 15)
}

@Test
func taskFilterJSONRoundTrip() throws {
    let now = Date()
    let filter = TaskFilter(
        flagged: true,
        dueBefore: now,
        maxEstimatedMinutes: 30
    )
    
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(filter)
    
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(TaskFilter.self, from: data)
    
    #expect(decoded.flagged == true)
    #expect(decoded.maxEstimatedMinutes == 30)
    
    // Use timeInterval comparison for date to handle precision differences
    if let decodedDueBefore = decoded.dueBefore {
        let timeDifference = abs(decodedDueBefore.timeIntervalSince(now))
        #expect(timeDifference < 1.0, "Due dates should match within 1 second tolerance")
    } else {
        Issue.record("decoded.dueBefore should not be nil")
    }
}
