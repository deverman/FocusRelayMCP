import Foundation
import Testing
@testable import OmniFocusCore

@Test
func taskItemRoundTrip() throws {
    let task = TaskItem(
        id: "abc123",
        name: "Test Task",
        note: "Note",
        projectID: "proj1",
        projectName: "Project",
        tagIDs: ["tag1"],
        tagNames: ["Tag"],
        dueDate: Date(timeIntervalSince1970: 1_700_000_000),
        plannedDate: Date(timeIntervalSince1970: 1_700_000_100),
        deferDate: nil,
        completed: false,
        flagged: true,
        effectiveFlagged: true,
        estimatedMinutes: 30,
        available: true
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(task)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(TaskItem.self, from: data)

    #expect(decoded.id == task.id)
    #expect(decoded.name == task.name)
    #expect(decoded.plannedDate == task.plannedDate)
    #expect(decoded.flagged == task.flagged)
    #expect(decoded.effectiveFlagged == task.effectiveFlagged)
    #expect(decoded.estimatedMinutes == task.estimatedMinutes)
}

@Test
func pageDefaults() {
    let page = PageRequest()
    #expect(page.limit == 50)
    #expect(page.cursor == nil)
}

@Test
func pageWarningsRoundTripAndAbsenceTolerance() throws {
    let tagged = Page(
        items: [TagItem(id: "tag-1", name: "Home", status: "active")],
        returnedCount: 1,
        totalCount: 1,
        warnings: ["Invalid date filter value: not-a-date"]
    )
    let data = try JSONEncoder().encode(tagged)
    let decoded = try JSONDecoder().decode(Page<TagItem>.self, from: data)
    #expect(decoded.warnings == ["Invalid date filter value: not-a-date"])

    let withoutWarnings = #"{"items":[],"returnedCount":0}"#.data(using: .utf8)!
    let legacy = try JSONDecoder().decode(Page<TagItem>.self, from: withoutWarnings)
    #expect(legacy.warnings == nil)
}

@Test
func projectItemReviewRoundTrip() throws {
    let interval = ReviewInterval(steps: 2, unit: "weeks")
    let project = ProjectItem(
        id: "proj-1",
        name: "Review Project",
        note: nil,
        status: "active",
        flagged: false,
        lastReviewDate: Date(timeIntervalSince1970: 1_700_100_000),
        nextReviewDate: Date(timeIntervalSince1970: 1_700_200_000),
        reviewInterval: interval,
        availableTasks: nil,
        remainingTasks: nil,
        completedTasks: nil,
        droppedTasks: nil,
        totalTasks: nil,
        hasChildren: nil,
        nextTask: nil,
        containsSingletonActions: nil,
        isStalled: nil
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(project)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(ProjectItem.self, from: data)

    #expect(decoded.id == project.id)
    #expect(decoded.lastReviewDate == project.lastReviewDate)
    #expect(decoded.nextReviewDate == project.nextReviewDate)
    #expect(decoded.reviewInterval?.steps == interval.steps)
    #expect(decoded.reviewInterval?.unit == interval.unit)
}

@Test
func folderItemRoundTrip() throws {
    let folder = FolderItem(
        id: "folder-1",
        name: "Travel",
        parentID: "parent-1",
        parentName: "Personal",
        projectCount: 3,
        childFolderCount: 2
    )

    let data = try JSONEncoder().encode(folder)
    let decoded = try JSONDecoder().decode(FolderItem.self, from: data)

    #expect(decoded.id == folder.id)
    #expect(decoded.name == folder.name)
    #expect(decoded.parentID == folder.parentID)
    #expect(decoded.projectCount == folder.projectCount)
    #expect(decoded.childFolderCount == folder.childFolderCount)
}
