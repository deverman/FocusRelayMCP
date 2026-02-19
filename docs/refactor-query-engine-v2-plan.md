# Refactor Plan: Query Engine V2

Date: 2026-02-19
Status: Draft for implementation
Target: Long-term branch (no immediate release tag)

## Purpose

This plan documents a full refactor program to reduce complexity in task querying/counting, remove ambiguous filter semantics, and improve maintainability/SOLID alignment across the bridge, MCP schema, and Swift layers.

It contains two versions of the same program:

1. Plan A (Human-Readable): product/roadmap view.
2. Plan B (Implementation Runbook): file-level, decision-complete execution plan.

---

## Plan A (Human-Readable)

### What We Keep

1. OmniFocus-native status semantics (`task.taskStatus`, `project.status`).
2. Existing availability policy (`isTaskAvailable` with project + parent guardrails).
3. Read-only MCP tool model and current integration-test approach.

### What We Change

1. Replace ambiguous task-scope filters with explicit contract.
- Current confusion: `inboxView` controls mode but `inboxOnly` controls scope.
- New model: explicit scope + explicit view.

2. Unify list and count behavior through one query engine.
- `list_tasks` and `get_task_counts` should be two outputs of the same pipeline.
- Goal: no behavior drift between count and list.

3. Move to contract-first API discipline.
- Schema/tool descriptions, Swift model types, and runtime behavior must match.
- Eliminate "works in runtime but not advertised in schema" gaps.

4. Add deterministic validation errors.
- Invalid filter combinations should return clear `INVALID_FILTER` responses.
- No implicit coercion for ambiguous combinations.

5. Improve operability under load.
- Use native OmniFocus collections as fast paths.
- Keep fallback scan for advanced cases.
- Add better timeout/retry policy separately.

### Why This Refactor

1. The bridge op handler is monolithic and difficult to reason about.
2. Similar filtering logic exists in multiple paths, creating regression risk.
3. Ambiguous filter contract causes incorrect LLM usage and user confusion.
4. Transport and heavy-query behavior still has intermittent fragility.

### Delivery Strategy

1. Incremental PRs only.
2. Breaking contract cleanup is intentional.
3. Work on a long-term branch and release after migration docs + parity tests are complete.

---

## Plan B (Implementation Runbook)

## Locked Decisions

1. Refactor style: incremental PRs.
2. Contract strategy: breaking cleanup (no legacy compatibility mode).
3. Release target: long-term branch first, then later beta tag.
4. Availability semantics remain policy-compatible with current behavior.

## Branch and PR Model

1. Create branch `refactor/query-engine-v2` from `master`.
2. Land PRs in order listed below.
3. Merge to `master` only after all acceptance criteria pass.

## PR-01: Typed Filter Contract + Validation Layer

### Files

1. `Sources/OmniFocusCore/OmniFocusCore.swift`
2. `Sources/FocusRelayServer/FocusRelayServer.swift`
3. `Sources/OmniFocusAutomation/BridgeModels.swift` (if bridge request structs need updates)

### Changes

1. Add typed enums:
- `TaskScope`: `all`, `inbox`, `project`
- `TaskView`: `available`, `remaining`, `everything`
- `ProjectStatusView`: `active`, `onHold`, `dropped`, `done`, `all`

2. Replace legacy task filter fields:
- Remove: `inboxOnly`, `inboxView`, `projectView`
- Add: `scope`, `view`, `projectStatus`

3. Add centralized filter validator:
- `scope=project` requires `project`.
- `project` is invalid unless `scope=project`.
- `completed=true` with `view=available` is invalid.
- Any unknown enum value fails validation.

4. Surface validation errors as deterministic MCP error payloads.

### Acceptance

1. Unit tests for each validation rule.
2. MCP returns actionable error messages for invalid combinations.

## PR-02: Bridge Query Engine Extraction

### Files

1. `Plugin/FocusRelayBridge.omnijs/Resources/BridgeLibrary.js`

### Changes

1. Introduce internal query pipeline functions:
- `normalizeFilter(rawFilter)`
- `validateFilter(filter)`
- `selectTaskPool(filter)`
- `taskMatchesFilter(task, filter, context)`
- `runTaskQuery(filter, options)` returning `{tasks, totalCount, counts}`

2. Refactor handlers:
- `list_tasks` calls `runTaskQuery` for list output.
- `get_task_counts` calls `runTaskQuery` for count output.

3. Keep status policy functions as canonical behavior:
- `taskStatus`, `isRemainingStatus`, `isAvailableStatus`
- `projectMatchesView`, `isTaskAvailable`

4. Query planner fast-path order:
- Inbox scope collection
- Project scope collection
- Native global collections (`availableTasks`, `remainingTasks`, `completedTasks`)
- Full `flattenedTasks` fallback

### Acceptance

1. No duplicated filter logic between list and count paths.
2. Existing integration tests continue passing.

## PR-03: MCP Schema Breaking Cleanup

### Files

1. `Sources/FocusRelayServer/FocusRelayServer.swift`
2. `README.md`
3. `IPC-SPEC.md`

### Changes

1. Update `list_tasks` and `get_task_counts` schemas to only expose new filter contract fields.
2. Remove legacy params from documented schema examples.
3. Add explicit examples for scope/view/projectStatus combinations.

### Acceptance

1. Tool schema and runtime behavior fully aligned.
2. Docs contain no references to removed legacy fields.

## PR-04: CLI Migration

### Files

1. `Sources/FocusRelayCLI/CLIHelpers.swift`
2. `Sources/FocusRelayCLI/FocusRelayCLI.swift`
3. `README.md` CLI examples

### Changes

1. Replace legacy flags with explicit flags:
- `--scope`
- `--view`
- `--project-status`

2. Remove or reject old flags with clear migration error text.

### Acceptance

1. `focusrelay` help text reflects new model.
2. CLI tests updated for new flags.

## PR-05: Parity and Contract Regression Tests

### Files

1. `Tests/OmniFocusCoreTests/*`
2. `Tests/OmniFocusIntegrationTests/OmniFocusIntegrationTests.swift`
3. `Tests/FocusRelayServerTests/*` (as needed for schema + error mapping)

### Required Scenarios

1. `scope=all` with each `view` parity: list totalCount == get_task_counts total.
2. `scope=inbox` parity for all views.
3. `scope=project` parity with project status filters.
4. Completed date range parity and sorting behavior.
5. Validation error scenarios for invalid combinations.

### Acceptance

1. Test suite catches any list/count drift.
2. Breaking changes are explicitly tested and documented.

## PR-06: Transport Hardening Follow-up

### Files

1. `Sources/OmniFocusAutomation/BridgeClient.swift`
2. `docs/timeout-concurrency-investigation-2026-02-19.md`

### Changes

1. Add per-operation timeout policy (not one fixed timeout for all ops).
2. Add retry policy for idempotent read operations.
3. Add structured diagnostics for timeout/open/interrupted-system-call errors.

### Acceptance

1. Repeated live bridge runs show materially lower timeout/interruption failures.

## PR-07: Final Migration Docs and Release Preparation

### Files

1. `README.md`
2. `CHANGELOG.md`
3. `NEXT-STEPS.md`
4. `docs/mcp-best-practices.md`

### Changes

1. Add migration mapping table:
- old -> new filter fields and examples.
2. Add explicit release notes section for breaking API changes.
3. Remove completed backlog items; retain follow-ups.

### Acceptance

1. Migration docs are sufficient for external MCP client updates.
2. Ready for next breaking beta cut.

---

## Public Interface Changes (Expected)

1. `TaskFilter` breaking change:
- Remove `inboxOnly`, `inboxView`, `projectView`
- Add `scope`, `view`, `projectStatus`

2. MCP tool schema changes:
- `list_tasks` and `get_task_counts` use only new fields.
- Invalid/legacy usage returns `INVALID_FILTER`.

3. CLI changes:
- Introduce explicit scope/view flags and remove legacy flag semantics.

---

## Program-Level Acceptance Criteria

1. One shared query pipeline powers both list and count behavior.
2. Filter contract is explicit, typed, and validated.
3. Integration tests prove parity across major scope/view combinations.
4. Docs/schemas/runtime behavior stay synchronized.
5. Transport resiliency improvements are measured and documented.

