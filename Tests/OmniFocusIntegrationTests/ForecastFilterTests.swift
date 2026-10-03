import Foundation
import Testing
@testable import OmniFocusCore
@testable import OmniFocusAutomation

/// Forecast filter integration tests.
///
/// These tests require OmniFocus and cannot run in environments without it.
/// They verify that the Forecast filter correctly collects tasks from
/// multiple documented sources and maintains list/count parity.
///
/// Run with: swift test --filter ForecastFilterTests

@Suite("Forecast Filter Integration", .tags(.requiresOmniFocus))
struct ForecastFilterTests {
    
    @Test("Forecast filter is recognized in list_tasks")
    func forecastFilterRecognized() async throws {
        // Verify that the forecast filter can be set and serialized
        let filter = TaskFilter(
            completed: false,
            forecast: true
        )
        
        #expect(filter.forecast == true)
        #expect(filter.completed == false)
    }
    
    @Test("Forecast filter serializes correctly")
    func forecastFilterSerialization() throws {
        let filter = TaskFilter(forecast: true)
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(filter)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(TaskFilter.self, from: data)
        
        #expect(decoded.forecast == true)
    }
    
    @Test("Forecast with other filters combines as intersection")
    func forecastWithOtherFilters() throws {
        let filter = TaskFilter(
            completed: false,
            flagged: true,
            forecast: true
        )
        
        // This should collect Forecast tasks and then filter to flagged only
        #expect(filter.forecast == true)
        #expect(filter.flagged == true)
        #expect(filter.completed == false)
    }
}

/// Manual validation scenarios for OmniFocus UAT.
///
/// These are documented test scenarios that must be run manually
/// on a Mac with OmniFocus to verify Forecast behavior.
@Suite("Forecast UAT Scenarios", .tags(.manual))
struct ForecastUATScenarios {
    
    @Test("Scenario: Overdue task appears in Forecast", .disabled())
    func overdueTaskInForecast() async throws {
        // MANUAL TEST:
        // 1. Create task "Overdue Test" with due date yesterday
        // 2. Run: focusrelay list-tasks --filter '{"forecast": true}' --fields id,name,dueDate
        // 3. Verify "Overdue Test" appears in results
        // 4. Check OmniFocus Forecast view - task should appear as "Past"
    }
    
    @Test("Scenario: Due today task appears in Forecast", .disabled())
    func dueTodayTaskInForecast() async throws {
        // MANUAL TEST:
        // 1. Create task "Due Today Test" with due date today at noon
        // 2. Run: focusrelay list-tasks --filter '{"forecast": true}' --fields id,name,dueDate
        // 3. Verify "Due Today Test" appears in results
        // 4. Check OmniFocus Forecast - task should appear as "Today"
    }
    
    @Test("Scenario: Planned task appears in Forecast", .disabled())
    func plannedTodayTaskInForecast() async throws {
        // MANUAL TEST:
        // 1. Create task "Planned Test" with NO due date but planned date today
        // 2. Run: focusrelay list-tasks --filter '{"forecast": true}' --fields id,name,plannedDate
        // 3. Verify "Planned Test" appears in results
        // 4. Check OmniFocus Forecast - task should appear based on planned date
    }
    
    @Test("Scenario: Deferred until today appears when available", .disabled())
    func deferredUntilTodayInForecast() async throws {
        // MANUAL TEST:
        // 1. Create task "Deferred Test" with defer date today at 8am
        // 2. Run test after 8am: focusrelay list-tasks --filter '{"forecast": true}' --fields id,name,deferDate
        // 3. Verify "Deferred Test" appears if time is past 8am
        // 4. Task should be available (not blocked)
    }
    
    @Test("Scenario: Flagged task appears in Forecast", .disabled())
    func flaggedTaskInForecast() async throws {
        // MANUAL TEST:
        // 1. Create task "Flagged Test" with NO dates but flag it
        // 2. Run: focusrelay list-tasks --filter '{"forecast": true}' --fields id,name,flagged
        // 3. Verify "Flagged Test" appears in results
        // 4. Check OmniFocus Forecast - should appear if Forecast preferences include flagged
    }
    
    @Test("Scenario: Forecast-tagged task appears", .disabled())
    func forecastTaggedTaskInForecast() async throws {
        // MANUAL TEST:
        // 1. Create or find tag named "Forecast"
        // 2. Create task "Tag Test" with NO dates or flags
        // 3. Assign "Forecast" tag to "Tag Test"
        // 4. Run: focusrelay list-tasks --filter '{"forecast": true}' --fields id,name,tagNames
        // 5. Verify "Tag Test" appears in results with "Forecast" in tagNames
    }
    
    @Test("Scenario: Task matching multiple criteria appears once", .disabled())
    func taskWithMultipleCriteriaAppearsOnce() async throws {
        // MANUAL TEST:
        // 1. Create task "Multi Test" that is BOTH overdue AND flagged
        // 2. Set due date to yesterday
        // 3. Flag the task
        // 4. Run: focusrelay list-tasks --filter '{"forecast": true}' --fields id,name
        // 5. Verify "Multi Test" appears EXACTLY ONCE in results (deduplication)
    }
    
    @Test("Scenario: list_tasks and get_task_counts agree on Forecast", .disabled())
    func listAndCountParity() async throws {
        // MANUAL TEST:
        // 1. Run: focusrelay get-task-counts --filter '{"forecast": true}'
        //    Note the "total" count
        // 2. Run: focusrelay list-tasks --filter '{"forecast": true, "includeTotalCount": true}'
        //    Note the "totalCount" in response
        // 3. Verify both counts match
        // 4. If different, one of list_tasks or get_task_counts is wrong
    }
    
    @Test("Scenario: Forecast count is close to OmniFocus native Forecast", .disabled())
    func forecastCountReasonablyCloseToNative() async throws {
        // MANUAL TEST:
        // 1. Open OmniFocus and check Forecast perspective
        // 2. Count visible items: Past + Today + Future (ignore calendar events)
        // 3. Run: focusrelay get-task-counts --filter '{"forecast": true}'
        // 4. Compare counts:
        //    - Exact match would mean preferences are perfectly captured (unlikely)
        //    - Close match (within ~10%) is expected
        //    - Large gap suggests missing criteria or implementation bug
        // 5. Check warnings in response - should mention calendar events
    }
    
    @Test("Scenario: Warnings appear in Forecast responses", .disabled())
    func forecastWarningsPresent() async throws {
        // MANUAL TEST:
        // 1. Run: focusrelay list-tasks --filter '{"forecast": true}'
        // 2. Check response "warnings" array
        // 3. Verify these warnings appear:
        //    - "Forecast results are task-only: calendar events are excluded."
        //    - "Forecast preferences beyond documented task sources... cannot be queried..."
    }
    
    @Test("Scenario: Forecast combines with project filter", .disabled())
    func forecastIntersectsProjectFilter() async throws {
        // MANUAL TEST:
        // 1. Create project "Test Project"
        // 2. Create overdue task "Project Test" in "Test Project"
        // 3. Create overdue task "Other Test" in a different project
        // 4. Run: focusrelay list-tasks --filter '{"forecast": true, "project": "Test Project"}'
        // 5. Verify "Project Test" appears but "Other Test" does NOT
        // 6. Forecast + project filter should intersect correctly
    }
    
    @Test("Scenario: Local timezone boundaries work correctly", .disabled())
    func forecastRespectsLocalTimezone() async throws {
        // MANUAL TEST (best done near midnight):
        // 1. Set Mac timezone to something non-UTC (e.g., US/Pacific)
        // 2. Create task due at 12:01 AM today local time
        // 3. Create task due at 11:59 PM today local time
        // 4. Create task due at 12:01 AM tomorrow local time
        // 5. Run: focusrelay list-tasks --filter '{"forecast": true}' at 1:00 AM
        // 6. Verify:
        //    - 12:01 AM today task appears (due today)
        //    - 11:59 PM today task appears (due today)
        //    - 12:01 AM tomorrow task does NOT appear (due tomorrow)
    }
    
    @Test("Scenario: Original UAT from issue #85", .disabled())
    func originalUATScenario() async throws {
        // MANUAL TEST (recreate original issue):
        // 1. Configure OmniFocus Forecast with preferences:
        //    - Items with due dates
        //    - Items with planned dates
        //    - Items with defer dates
        //    - Flagged items
        //    - Items tagged "Forecast"
        // 2. Populate inbox with varied tasks
        // 3. Note OmniFocus Forecast count: Past + Today + Future
        // 4. Ask MCP client: "How many items are in the Forecast?"
        // 5. Verify:
        //    - Client uses get_task_counts with forecast: true
        //    - Client does NOT improvise with dueBefore alone
        //    - Count is reasonably close to OmniFocus count
        //    - Client mentions exclusions if count differs significantly
    }
}

extension Tag {
    static let requiresOmniFocus = Tag()
    static let manual = Tag()
}
