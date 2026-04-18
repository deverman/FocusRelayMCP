# Mutation Change Checklist

Use this before changing any production mutation path in FocusRelay.

Scope:
- Future mutation logic in `Plugin/FocusRelayBridge.omnijs/Resources/BridgeLibrary.js`
- Future mutation logic in `Sources/OmniFocusAutomation/OmniFocusAutomation.swift`
- Future shared mutation models and services
- Future CLI and MCP mutation command wiring

## 1. Freeze The Contract First

Before coding, write down:
- the documented Omni Automation write APIs the change is allowed to use
- the exact public tool or CLI shape being introduced or modified
- whether the mutation is a patch, lifecycle transition, or move
- the validation and failure semantics
- whether cache invalidation is required after success

Reference:
- [`docs/omni-automation-write-contract.md`](./omni-automation-write-contract.md)

Minimum invariant list:
- v1 writes are homogeneous bulk only
- v1 writes target IDs only
- `update_*` is field patch only
- `set_*_completion` owns completion lifecycle
- `set_projects_status` owns project active/on-hold/dropped transitions
- `move_*` owns structural location changes
- successful writes invalidate cached `list_projects` and `list_tags`

## 2. Confirm The Official API Surface

Before implementation, verify that every production write API used by the change is documented on the official Omni Automation site.

Examples of approved v1 references:
- task fields such as `name`, `note`, `flagged`, `estimatedMinutes`, `dueDate`, `deferDate`
- task functions such as `appendStringToNote(...)`, `addTag(...)`, `addTags(...)`, `removeTag(...)`, `markComplete(...)`, `markIncomplete()`
- project fields such as `name`, `flagged`, `containsSingletonActions`, `sequential`, `status`, `reviewInterval`, `dueDate`, `deferDate`
- project functions such as `appendStringToNote(...)`, `addTag(...)`, `addTags(...)`, `removeTag(...)`, `markComplete(...)`, `markIncomplete()`
- database functions such as `moveTasks(...)` and `moveSections(...)`

If the docs are ambiguous:
- keep it out of scope
- document the ambiguity
- do not ship a speculative production path

## 3. Add Semantic Tripwire Tests

Add tests for the exact boundary or contract risk introduced by the mutation change.

Minimum categories:
- valid mutation success
- invalid ID handling
- preview-only behavior
- verify readback behavior
- CLI and MCP parity for request/response semantics

Add focused coverage when applicable:
- repeating task completion
- repeating project completion
- move destination validation
- task tag add/remove/set behavior
- project status transitions between `active`, `on_hold`, and `dropped`
- cache invalidation after a successful write

## 4. Validate Safety Boundaries

Before merge, verify:
- bulk writes remain homogeneous
- no name-based mutation targeting was introduced
- no hidden mixed-operation batch behavior was added
- preview paths do not mutate data
- verify paths do not silently hide mutation failures
- error responses remain structured and actionable

For bulk writes:
- require explicit user-facing confirmation behavior at the tool layer when the later implementation issue adds it
- do not add partial-success semantics casually

## 5. Keep CLI And MCP On One Shared Core

Before merge, verify:
- request models are shared
- validation rules are shared
- result semantics are shared
- cache invalidation is triggered from the shared mutation layer, not duplicated in frontends

Do not:
- implement one behavior for CLI and a different one for MCP
- duplicate mutation logic in separate transports unless a later issue explicitly isolates that experiment

## 6. Verify The Read-After-Write Contract

For every mutation tool, define the post-write readback rule up front:
- what fields are returned by default
- what fields are returned only when `returnFields` is set
- when `verify=true` is required or recommended
- which read path is used to confirm the mutation

Minimum readback invariants:
- the target ID remains stable after non-repeating updates and moves
- completion/status tools report the final lifecycle state accurately
- repeating completion tools document and verify the returned object identity behavior
- cache invalidation prevents stale `list_projects` and `list_tags` responses after success

## 7. Update Docs Before Shipping

Before merge, make sure:
- public docs reflect the exact tool names and schemas
- examples show both single-item and homogeneous-bulk usage
- docs explain the split between patch vs lifecycle vs move tools
- docs state what is intentionally out of scope for v1

If the change alters install, approval, or restart behavior:
- validate the full user-facing flow in plain language docs

## 8. Define The Acceptance Rule Up Front

A mutation change is not done because the code compiles.

Write down the acceptance rule before implementation:
- `swift test` passes
- mutation tripwire tests cover the new boundary
- preview and verify semantics are correct
- CLI and MCP parity holds
- cache invalidation behaves correctly after success
- docs and examples match the shipped schema

If any of those fail:
- revert the change
- narrow the scope
- or split the work into a smaller issue
