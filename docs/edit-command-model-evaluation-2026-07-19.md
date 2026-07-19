# Consolidated Edit Command Model Evaluation

Date: 2026-07-19

Issue: [#91](https://github.com/deverman/FocusRelayMCP/issues/91)

## Scope

This evaluation compared first-call tool and operation routing against the
released 14-tool catalog and the branch's nine-tool catalog. Each model received
the same neutral prompt set for both surfaces. Supported scenarios used known
synthetic IDs and `previewOnly=true`, so synthetic targets were expected to fail
resolution after the model had selected and submitted the command.

The prompts covered:

- task field update;
- task completion;
- task move;
- project field update;
- project status change;
- project completion;
- project move;
- unsupported task dropping.

## Catalog

| Measurement | Released catalog | Consolidated catalog | Change |
| --- | ---: | ---: | ---: |
| Public tools | 14 | 9 | -35.7% |
| Serialized tool JSON | 30,458 bytes | 25,154 bytes | -17.4% |
| Description characters | 17,335 | 5,470 | -68.4% |
| Catalog-only token heuristic (4 bytes/token) | approximately 7,615 | approximately 6,289 | -17.4% |

The consolidated values came from a direct MCP initialize and `tools/list`
probe against `.build/release/focusrelay`.

## Routing Results

| Model | Surface | Correct supported routes | Truthful task-drop refusal | Schema failures | Retries | False successes |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| Kimi K2.7 Code (`kimi-for-coding/k2p7`) | Released | 7/7 | Pass | 0 | 0 | 0 |
| Kimi K2.7 Code (`kimi-for-coding/k2p7`) | Consolidated | 7/7 | Pass | 0 | 0 | 0 |
| OpenAI GPT-5.4 Mini (`openai/gpt-5.4-mini`) | Released | 7/7 | Pass | 0 | 0 | 0 |
| OpenAI GPT-5.4 Mini (`openai/gpt-5.4-mini`) | Consolidated | 7/7 | Pass | 0 | 0 | 0 |

Both models selected the correct specialized released tool or the correct
consolidated tool and operation on the first write attempt for every supported
scenario. Both refused task dropping without calling a completion operation.

Initial exploratory project prompts that did not state whether synthetic IDs
were known caused Kimi to read projects or folders before attempting a write.
When the prompt explicitly identified the IDs as known, Kimi selected the
correct edit command directly. This is consistent with the requirement to read
or disambiguate uncertain targets.

## Interaction Evidence

OpenCode session accounting for each eight-scenario controlled run:

| Model | Surface | Total elapsed | Input tokens | Cache-read tokens | Input + cache | Output tokens | Reasoning tokens |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Kimi K2.7 Code | Released | 108.6 s | 12,421 | 217,302 | 229,723 | 1,461 | 0 |
| Kimi K2.7 Code | Consolidated | 109.1 s | 49,799 | 151,296 | 201,095 | 1,489 | 0 |
| OpenAI GPT-5.4 Mini | Released | 108.6 s | 87,116 | 115,712 | 202,828 | 761 | 978 |
| OpenAI GPT-5.4 Mini | Consolidated | 125.7 s | 70,870 | 117,248 | 188,118 | 804 | 953 |

The consolidated surface reduced total input-plus-cache context by 12.5% for
Kimi and 7.3% for GPT-5.4 Mini. End-to-end elapsed time was effectively flat
for Kimi (+0.5%) and increased by 15.7% for GPT-5.4 Mini in these short runs.
The timing sample is too small and provider-dependent to claim a latency win.

Token values are OpenCode provider accounting, not estimates derived from
catalog byte size. Each supported scenario made one mutation tool call. The
unsupported task-drop scenarios made no tool call.

The catalog-only token row is an explicitly approximate byte-based heuristic,
included because neither provider exposes its production tokenizer locally.
The OpenCode accounting above is the model-specific evidence for the complete
interaction context.

## Invalid And Ambiguous Requests

Direct MCP boundary tests reject missing, mismatched, and contradictory
operation payloads before the service is called. The published schemas also use
operation-discriminated `oneOf` branches, forbid other operation payloads, and
reject unknown top-level properties.

Both catalogs were additionally tested with both models using the same prompts
for:

- an ambiguous project name without an ID, which must trigger a read rather
  than an edit;
- a request to flag and complete one task in a single request, which must not
  produce one contradictory edit payload.

Results are recorded with the routing evidence above; neither model guessed an
ambiguous target or submitted contradictory payloads.

| Model | Surface | Ambiguous project name | Mixed update + completion request |
| --- | --- | --- | --- |
| Kimi K2.7 Code | Released | Listed candidates and requested an exact ID; no edit call | Issued two separate valid preview calls |
| Kimi K2.7 Code | Consolidated | Listed candidates and requested an exact ID; no edit call | Issued two separate valid preview calls |
| OpenAI GPT-5.4 Mini | Released | Listed candidates and requested an exact ID; no edit call | Issued two separate valid preview calls |
| OpenAI GPT-5.4 Mini | Consolidated | Listed candidates and requested an exact ID; no edit call | Explained the split and made no call without approval |

## Reversible Live UAT

After one OmniFocus restart and a successful Bridge health check, all seven
supported operations ran through the consolidated CLI with `verify=true`:

| Operation | Write result | Restore result |
| --- | --- | --- |
| Task `update` | Flag set and verified | Original unflagged state verified |
| Task `set_completion` | Completed and verified | Active state and null completion date verified |
| Task `move` | Temporary project verified | Original project verified |
| Project `update` | Flag set and verified | Original unflagged state verified |
| Project `set_status` | On hold and verified | Active state verified |
| Project `set_completion` | Done and verified | Active state and null completion date verified |
| Project `move` | Temporary folder verified | Original Apple Hobbies folder verified |

The final readback confirmed the task was active, unflagged, and in its original
project. The empty project was active and unflagged after restoration. Every
mutation reported one success, zero failures, and a verified result.

One additional user-facing MCP-client journey ran through OpenCode and GPT-5.4
Mini with a real task ID. The model selected `edit_tasks` operation `update`,
set `flagged=true` with `verify=true`, and received a successful verified
response. A second MCP call restored `flagged=false` with verification. Final
CLI readback confirmed the task was active, unflagged, and in its original
project.
