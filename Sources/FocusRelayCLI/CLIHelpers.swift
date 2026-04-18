import ArgumentParser
import Foundation
import OmniFocusCore

extension MutationCompletionState: ExpressibleByArgument {}
extension MutationMoveDestinationKind: ExpressibleByArgument {}
extension MutationProjectStatus: ExpressibleByArgument {}

enum FieldList {
    static func parse(_ raw: String?) -> [String] {
        guard let raw, !raw.isEmpty else { return [] }
        return raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

enum ISO8601DateParser {
    static func parseOptional(_ raw: String?, argumentName: String) throws -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        return try parse(raw, argumentName: argumentName)
    }

    static func parse(_ raw: String, argumentName: String) throws -> Date {
        if let date = parseFractional(raw) ?? parseStandard(raw) {
            return date
        }
        throw ValidationError("Invalid date for \(argumentName): \(raw). Expected ISO8601 like 2026-02-04T12:00:00Z.")
    }

    private static func parseStandard(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }

    private static func parseFractional(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: raw)
    }
}

struct PageOptions: ParsableArguments {
    @Option(help: "Page size limit.")
    var limit: Int? = nil

    @Option(help: "Cursor for pagination.")
    var cursor: String? = nil

    func makePageRequest(defaultLimit: Int) -> PageRequest {
        PageRequest(limit: limit ?? defaultLimit, cursor: cursor)
    }
}

struct TaskFilterOptions: ParsableArguments {
    @Option(help: "Filter by completion status (true/false).")
    var completed: Bool? = nil

    @Option(help: "Filter flagged tasks (true/false).")
    var flagged: Bool? = nil

    @Option(name: .customLong("available-only"), help: "Only show available tasks (true/false).")
    var availableOnly: Bool? = nil

    @Option(name: .customLong("inbox-view"), help: "Inbox view: available, remaining, or everything.")
    var inboxView: String? = nil

    @Option(help: "Filter by project ID or name.")
    var project: String? = nil

    @Option(help: "Comma-separated tag IDs or names.")
    var tags: String? = nil

    @Option(name: .customLong("due-before"), help: "ISO8601 datetime. Tasks due before this time.")
    var dueBefore: String? = nil

    @Option(name: .customLong("due-after"), help: "ISO8601 datetime. Tasks due after this time.")
    var dueAfter: String? = nil

    @Option(name: .customLong("planned-before"), help: "ISO8601 datetime. Tasks planned before this time.")
    var plannedBefore: String? = nil

    @Option(name: .customLong("planned-after"), help: "ISO8601 datetime. Tasks planned after this time.")
    var plannedAfter: String? = nil

    @Option(name: .customLong("defer-before"), help: "ISO8601 datetime. Tasks deferred until before this time.")
    var deferBefore: String? = nil

    @Option(name: .customLong("defer-after"), help: "ISO8601 datetime. Tasks deferred until after this time.")
    var deferAfter: String? = nil

    @Option(name: .customLong("completed-before"), help: "ISO8601 datetime. Tasks completed before this time.")
    var completedBefore: String? = nil

    @Option(name: .customLong("completed-after"), help: "ISO8601 datetime. Tasks completed after this time.")
    var completedAfter: String? = nil

    @Option(help: "Search tasks by name or note content.")
    var search: String? = nil

    @Option(name: .customLong("inbox-only"), help: "Only show inbox tasks (true/false).")
    var inboxOnly: Bool? = nil

    @Option(name: .customLong("project-view"), help: "Project view filter: active, onHold, dropped, done, etc.")
    var projectView: String? = nil

    @Option(name: .customLong("max-estimated-minutes"), help: "Maximum estimated minutes.")
    var maxEstimatedMinutes: Int? = nil

    @Option(name: .customLong("min-estimated-minutes"), help: "Minimum estimated minutes.")
    var minEstimatedMinutes: Int? = nil

    @Flag(name: .customLong("include-total-count"), help: "Include total count of all matching tasks.")
    var includeTotalCount: Bool = false

    func makeTaskFilter() throws -> TaskFilter {
        let tagList = FieldList.parse(tags)
        return TaskFilter(
            completed: completed,
            flagged: flagged,
            availableOnly: availableOnly,
            inboxView: inboxView,
            project: project,
            tags: tagList.isEmpty ? nil : tagList,
            dueBefore: try ISO8601DateParser.parseOptional(dueBefore, argumentName: "--due-before"),
            dueAfter: try ISO8601DateParser.parseOptional(dueAfter, argumentName: "--due-after"),
            deferBefore: try ISO8601DateParser.parseOptional(deferBefore, argumentName: "--defer-before"),
            deferAfter: try ISO8601DateParser.parseOptional(deferAfter, argumentName: "--defer-after"),
            plannedBefore: try ISO8601DateParser.parseOptional(plannedBefore, argumentName: "--planned-before"),
            plannedAfter: try ISO8601DateParser.parseOptional(plannedAfter, argumentName: "--planned-after"),
            completedBefore: try ISO8601DateParser.parseOptional(completedBefore, argumentName: "--completed-before"),
            completedAfter: try ISO8601DateParser.parseOptional(completedAfter, argumentName: "--completed-after"),
            search: search,
            inboxOnly: inboxOnly,
            projectView: projectView,
            maxEstimatedMinutes: maxEstimatedMinutes,
            minEstimatedMinutes: minEstimatedMinutes,
            includeTotalCount: includeTotalCount
        )
    }
}

struct TaskPatchOptions: ParsableArguments {
    @Option(help: "New task name.")
    var name: String? = nil

    @Option(help: "Replace the task note with this value.")
    var note: String? = nil

    @Option(name: .customLong("note-append"), help: "Append this string to the task note.")
    var noteAppend: String? = nil

    @Option(help: "Set flagged state (true/false).")
    var flagged: Bool? = nil

    @Option(name: .customLong("estimated-minutes"), help: "Set estimated minutes.")
    var estimatedMinutes: Int? = nil

    @Option(name: .customLong("due-date"), help: "Set due date as ISO8601.")
    var dueDate: String? = nil

    @Flag(name: .customLong("clear-due-date"), help: "Clear the due date.")
    var clearDueDate: Bool = false

    @Option(name: .customLong("defer-date"), help: "Set defer date as ISO8601.")
    var deferDate: String? = nil

    @Flag(name: .customLong("clear-defer-date"), help: "Clear the defer date.")
    var clearDeferDate: Bool = false

    @Option(name: .customLong("tag-add"), help: "Comma-separated tag IDs to add.")
    var tagAdd: String? = nil

    @Option(name: .customLong("tag-remove"), help: "Comma-separated tag IDs to remove.")
    var tagRemove: String? = nil

    @Option(name: .customLong("tag-set"), help: "Comma-separated tag IDs to set exactly.")
    var tagSet: String? = nil

    @Flag(name: .customLong("tag-clear"), help: "Clear all tags from the task.")
    var tagClear: Bool = false

    func makeTaskPatchMutation() throws -> TaskPatchMutation {
        let add = FieldList.parse(tagAdd)
        let remove = FieldList.parse(tagRemove)
        let set = FieldList.parse(tagSet)
        let tagMutation: TagMutation? = (add.isEmpty && remove.isEmpty && set.isEmpty && !tagClear)
            ? nil
            : TagMutation(
                add: add.isEmpty ? nil : add,
                remove: remove.isEmpty ? nil : remove,
                set: set.isEmpty ? nil : set,
                clear: tagClear
            )

        let patch = TaskPatchMutation(
            name: name,
            note: note,
            noteAppend: noteAppend,
            flagged: flagged,
            estimatedMinutes: estimatedMinutes,
            dueDate: try ISO8601DateParser.parseOptional(dueDate, argumentName: "--due-date"),
            clearDueDate: clearDueDate,
            deferDate: try ISO8601DateParser.parseOptional(deferDate, argumentName: "--defer-date"),
            clearDeferDate: clearDeferDate,
            tags: tagMutation
        )
        try patch.validate()
        return patch
    }
}

struct ProjectPatchOptions: ParsableArguments {
    @Option(help: "New project name.")
    var name: String? = nil

    @Option(help: "Replace the project note with this value.")
    var note: String? = nil

    @Option(name: .customLong("note-append"), help: "Append this string to the project note.")
    var noteAppend: String? = nil

    @Option(help: "Set flagged state (true/false).")
    var flagged: Bool? = nil

    @Option(name: .customLong("due-date"), help: "Set due date as ISO8601.")
    var dueDate: String? = nil

    @Flag(name: .customLong("clear-due-date"), help: "Clear the due date.")
    var clearDueDate: Bool = false

    @Option(name: .customLong("defer-date"), help: "Set defer date as ISO8601.")
    var deferDate: String? = nil

    @Flag(name: .customLong("clear-defer-date"), help: "Clear the defer date.")
    var clearDeferDate: Bool = false

    @Option(help: "Set sequential state (true/false).")
    var sequential: Bool? = nil

    @Option(name: .customLong("review-steps"), help: "Set review interval step count.")
    var reviewSteps: Int? = nil

    @Option(name: .customLong("review-unit"), help: "Set review interval unit: days, weeks, months, years.")
    var reviewUnit: String? = nil

    func makeProjectPatchMutation() throws -> ProjectPatchMutation {
        let reviewInterval: ReviewInterval?
        switch (reviewSteps, reviewUnit) {
        case (nil, nil):
            reviewInterval = nil
        case let (steps?, unit?):
            reviewInterval = ReviewInterval(steps: steps, unit: unit)
        default:
            throw ValidationError("Project review interval requires both --review-steps and --review-unit.")
        }

        let patch = ProjectPatchMutation(
            name: name,
            note: note,
            noteAppend: noteAppend,
            flagged: flagged,
            dueDate: try ISO8601DateParser.parseOptional(dueDate, argumentName: "--due-date"),
            clearDueDate: clearDueDate,
            deferDate: try ISO8601DateParser.parseOptional(deferDate, argumentName: "--defer-date"),
            clearDeferDate: clearDeferDate,
            sequential: sequential,
            reviewInterval: reviewInterval
        )
        try patch.validate()
        return patch
    }
}
