# MCP Workflow Prompt Research

Date: 2026-07-23

Issue: [#94](https://github.com/deverman/FocusRelayMCP/issues/94)

Validation impact: `docs`

## Acceptance Journey

An OmniFocus user opens a supporting MCP client's workflow picker, recognizes
an inbox-processing workflow without knowing its exact command, invokes it, and
receives a compact guided process that reads a small inbox page, recommends the
next decision, and requests approval before any write.

## Recommendation

Proceed to an instruction-first `process_inbox` technical prototype, but do not
ship a public prompt set yet. The protocol and pinned Swift SDK are ready; the
product names, workflow boundaries, client coverage, and reuse value are not
validated until the issue's five-participant discovery gate is complete.

Keep the first prototype static and data-free at `prompts/get` time. It should
instruct the model to call FocusRelay's existing compact tools after invocation,
one small inbox page at a time. Compare that against one bounded data-backed
variant only in the controlled evaluation. Do not preload a user's library into
the prompt response.

## What Is Proven

### Protocol

The MCP 2025-06-18 specification defines prompts as a user-controlled server
primitive. A supporting server advertises a `prompts` capability during
`initialize`; clients discover templates with `prompts/list` and retrieve a
selected template with `prompts/get`. Prompt arguments are strings. Slash
commands are an example client UI, not a protocol guarantee.

Primary source:
[MCP prompts specification](https://modelcontextprotocol.io/specification/2025-06-18/server/prompts).

### Pinned Swift SDK

FocusRelay pins `modelcontextprotocol/swift-sdk` 0.12.1 at revision
`a0ae212ebf6eab5f754c3129608bc5557637e605`. The checked-out SDK provides:

- `Server.Capabilities.Prompts`;
- `ListPrompts` and `GetPrompt` methods;
- prompt names, descriptions, string arguments, messages, and pagination;
- server handler examples and SDK round-trip tests.

No SDK upgrade is required for the spike.

### Current FocusRelay Baseline

A direct stdio probe sent `initialize`, `prompts/list`, `prompts/get`, and
`tools/list` to the current server:

- `initialize` advertised `tools.listChanged=true` and no prompt capability;
- both prompt requests returned JSON-RPC `-32601 Method not found`;
- `tools/list` returned the existing nine public tools.

This gives the implementation spike three exact regression assertions:

1. initialization adds only the prompt capability;
2. prompt methods become available with deterministic responses;
3. tool names and tool count remain unchanged.

## Client Compatibility Evidence

| Client | Current documented evidence | Research conclusion |
| --- | --- | --- |
| Claude Code | Anthropic documents dynamically discovered MCP prompts as `/mcp__servername__promptname`, including positional arguments. | Suitable for the first discovery UAT, but invocation still needs a live FocusRelay test. |
| OpenCode | Current public MCP docs describe local/remote MCP tools and automatic tool availability. They do not document `prompts/list`, `prompts/get`, or MCP prompt discovery. | Unsupported until a versioned live protocol/UI test proves otherwise. Do not describe OpenCode slash-command support. |
| Codex | Current official Codex material documents configuring MCP servers and consuming MCP tools. It does not document MCP prompt discovery or invocation. | Unsupported until a versioned live test proves otherwise. Codex custom prompts/skills are not evidence of MCP server-prompt support. |

Primary sources:

- [Claude Code MCP documentation](https://docs.anthropic.com/en/docs/claude-code/mcp)
- [OpenCode MCP servers](https://opencode.ai/docs/mcp-servers/)
- [Codex MCP configuration](https://developers.openai.com/codex/mcp)

Absence from documentation is not proof that a client cannot issue the
protocol methods. Record client name, exact version, initialization capability
exchange, prompt requests, and visible UI behavior during live testing.

## Prototype Contract

Working prompt name: `process_inbox`

Arguments: none for the first comparison

`prompts/get` payload: one user message containing workflow instructions only

The instruction-first variant should tell the model to:

1. call `get_task_counts` with `inboxOnly=true` before listing data;
2. call `list_tasks` with `inboxOnly=true`, a small page, and only fields needed
   to decide the current item;
3. handle one item or a user-approved small batch at a time;
4. ask what the item means when intent cannot be inferred safely;
5. recommend a destination or field change before writing;
6. use `edit_tasks` preview and verification for supported updates;
7. state current creation limits until #82 and #83 land;
8. stop cleanly when the user wants to defer the remaining inbox.

The bounded data-backed comparison may embed only the first small page and its
total count. Its maximum item count and byte budget must be declared before the
run. It must not fetch hundreds of tasks inside `prompts/get`.

## Evaluation Matrix

For each variant and client, capture:

| Measure | Collection rule |
| --- | --- |
| Discovery | User finds the workflow without receiving its exact command name. |
| Retrieval latency | Time only `prompts/get`; keep client startup separate. |
| Prompt bytes | UTF-8 byte count of the serialized `GetPrompt.Result`. |
| Tool catalog | Names and serialized bytes before and after prompt support. |
| Tool use | Calls, Bridge round trips, fields, page sizes, and expansions. |
| Result quality | Correct inbox scope, recommendation, clarification, and status semantics. |
| Write safety | Explicit approval, preview where broad/risky, verification, and failure handling. |
| Reuse intent | Participant says whether they would use it again and under what name. |

Use a seeded or participant-approved library. Never record task text in the
research summary. Record only library-size bands and aggregate measures.

## Decision Gates And Remaining Work

### Before implementation PR

- Complete at least five independent participant sessions across at least two
  MCP clients where possible.
- Reach the issue threshold: at least four participants discover a workflow and
  at least four would reuse one, or revise the discovery design.
- Publish disagreements, preferred names, and client-specific outcomes in #94.

### Technical spike

- Add Swift Testing protocol coverage for capability advertisement,
  `prompts/list`, `prompts/get`, invalid names, and arguments.
- Compare instruction-first and bounded data-backed `process_inbox` variants.
- Assert the nine public tool names and serialized tool catalog are unchanged.
- Record prompt payload bytes and retrieval latency separately from subsequent
  Bridge calls.

### Shipping

- Add only research-supported workflows.
- Document only clients proven by a versioned live test.
- Run semantic validation for every FocusRelay data path the final prompt text
  instructs models to use.

## Research Status

Gate 1 remains open: no new participant sessions were conducted for this
research branch. Protocol feasibility, SDK feasibility, the current server
baseline, the first prototype contract, and the measurement plan are complete.
Client UI compatibility beyond Claude Code's documented behavior remains a
live-test question.
