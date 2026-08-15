/// A reusable user-controlled workflow exposed through both MCP prompts and
/// the command line.
public struct FocusRelayWorkflowDefinition: Sendable, Equatable {
    public let name: String
    public let title: String
    public let description: String
    public let instructions: String

    public init(name: String, title: String, description: String, instructions: String) {
        self.name = name
        self.title = title
        self.description = description
        self.instructions = instructions
    }
}

extension FocusRelayServer {
    static let processInboxWorkflow = FocusRelayWorkflowDefinition(
        name: "process_inbox",
        title: "Process OmniFocus Inbox",
        description: "Safely process a bounded batch of unresolved OmniFocus inbox items.",
        instructions: """
        Help the user clarify and organize their OmniFocus inbox safely and incrementally.

        1. Establish scope first. Use get_task_counts when only a count is needed.
        2. Read unresolved inbox captures with list_tasks using filter.inboxOnly=true and filter.inboxView="remaining".
        3. Work in one 10–20 item decision batch. Initially request only id and name.
        4. Fetch note or other verbose fields only for selected captures whose meaning is ambiguous.
        5. Finish recommending actions for the current page before following nextCursor. Never respond to trouble by requesting an unbounded or substantially larger page, loading a full catalog, or writing a local script to classify ordinary output.

        Use this GTD-informed clarification path for each selected capture:

        6. Clarify what the capture means before organizing it. Describe only title and note evidence that is actually present. Ambiguity is not evidence that an item should be dropped. Ask the user what they intended or leave the item unchanged when the available evidence is insufficient.
        7. Decide whether the capture is actionable. For actionable work, identify the desired outcome when it requires more than one step, then propose a concrete physical, visible next action with a verb-led name.
        8. If the next action appears to take under two minutes, suggest that the user do it now, but never mark it complete without explicit approval.
        9. For delegated work, propose an existing user-selected Waiting For destination or tag and make the person or expected result clear. Do not invent a destination.
        10. For non-actionable captures, recommend drop only when the capture or user affirmatively identifies the item as unwanted, obsolete, duplicated, cancelled, or intentionally discarded. Offer an existing Someday/Maybe or reference destination only when the evidence supports it or the user selects it.
        11. Reserve due dates for genuine deadlines or date-specific commitments. Do not invent dates or treat every intended work date as a deadline. FocusRelay does not manage calendar events, so explain that limitation rather than claiming an item was filed on a calendar. Ask when date intent is unclear.
        12. Do not impose a project or tag taxonomy. Reuse the user's existing organization and ask when multiple plausible destinations remain.

        Apply the approved organization safely:

        Use FocusRelay tools only for this workflow (typically focusrelay_*); never substitute another OmniFocus server. For moves, pass FocusRelay IDs to edit_tasks operation=move with verify=true. Report failures instead of switching tools or retrying by name.

        13. When expanding selected inbox items, use one list_tasks request with filter.ids and the same inboxOnly=true and inboxView="remaining" scope. Use get_task only for IDs still unresolved after that correctly scoped batch, and explain the fallback.
        14. Resolve credible candidate destinations with list_projects.searches and list_tags.searches instead of loading broad project or tag catalogs. Do not launch a large parallel fan-out of project, tag, or task-detail requests. If there is no credible candidate, ask the user rather than guessing.
        15. Present a bounded proposal before changing OmniFocus. Separate recommendations from writes and obtain explicit approval for the exact batch. Keep ambiguous items out of the mutation batch until the user approves a clarified action.
        16. Resolve approved project and tag destinations to stable IDs before writing. If multiple matching paths remain, ask the user to choose.
        17. Group targets that share one operation, patch, state, or destination into the fewest supported calls. Never run mutation calls concurrently. Preview, apply, and verify one mutation group before starting the next.
        18. Recount after the approved mutation groups finish, then continue only if the user wants another batch.
        19. Do not delegate broad classification or mutation unless the user approved that exact scope.
        20. FocusRelay cannot yet create tasks, subtasks, or projects. Do not promise creation or conversion; explain that limit and use only currently supported edits, moves, status changes, and completion changes.
        """
    )

    /// All workflows available through the MCP prompt and CLI workflow adapters.
    public static let workflows = [processInboxWorkflow]

    /// Returns an exact workflow-name match without guessing or aliases.
    public static func workflow(named name: String) -> FocusRelayWorkflowDefinition? {
        workflows.first { $0.name == name }
    }
}
