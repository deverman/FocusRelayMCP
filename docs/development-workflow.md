# Development And Validation Workflow

This runbook applies the Kaizen decisions in
[#95](https://github.com/deverman/FocusRelayMCP/issues/95). Its goal is fast
feedback at the correct boundary, followed by one trustworthy release proof.

## 1. Define The Change Before Coding

Record these in the issue or PR:

- the user problem and expected outcome;
- one bounded vertical slice;
- the validation impact;
- one end-to-end acceptance journey;
- affected tools and production paths;
- whether the plugin, MCP wire contract, or Homebrew package changes.

### Validation impacts

| Impact | Use when | Required validation |
|---|---|---|
| `docs` | Markdown and non-executable text only | diff and documentation links |
| `package` | dependencies, versioning, packaging, or release workflow | tests, clean release build, packaging/version checks |
| `server-wire` | MCP SDK, schemas, handlers, content, or annotations | tests, release build, direct MCP success/error probes |
| `mutation` | task/project writes or mutation bridge behavior | server-wire checks plus reversible live write/verify/restore |
| `query` | task/project data, filtering, counts, status, or cache semantics | tests, native semantic oracle, list/count parity, canary |
| `performance` | intended latency, throughput, or memory improvement | query checks plus targeted 10-minute smoke |
| `transport-reliability` | IPC, dispatch, timeout, retry, or recovery logic | all semantic gates, targeted smoke, final release suite |

Mixed changes use the highest applicable impact. An explicit impact may narrow
an automatically conservative classification only when the issue explains why
the higher-risk path is unaffected.

## 2. Shift-Left Acceptance

Validate in this order:

1. Pure models and validation.
2. MCP schema, sparse arguments, and response wire shape.
3. Service behavior with a deterministic fake.
4. JavaScript syntax and deterministic JavaScriptCore behavior when applicable.
5. Native OmniFocus semantic truth.
6. Bridge health and targeted live behavior.
7. Actual MCP-client UAT.
8. Performance measurement only after correctness is green.

Every headline release claim needs a matching acceptance journey. For example,
“AI can update tasks” requires at least one real MCP sparse field update,
persistence verification, and restoration—not only a CLI write.

## 3. Benchmark Profiles

- `canary`: run semantic gates and one complete scenario rotation. Target under
  five minutes.
- `smoke`: run the affected tool for 10 minutes. Use only for performance or
  reliability changes.
- `release`: run the realistic 1.5-hour suite once on a frozen production
  fingerprint.
- `stress`: run three hours only when an issue names the diagnostic question.

Any production query/transport change after a release certificate invalidates
the certificate. Documentation-only changes do not. Raw output is written to
`.build/benchmarks`.

## 4. Release Flow

1. Merge independently validated vertical PRs.
2. Run release-claim UAT before freezing the candidate.
3. Generate the release plan and production fingerprint.
4. Run the required final validation once.
5. Tag the exact certified commit and let GitHub build/package it.
6. Verify the release asset, checksum, embedded version, plugin health, and
   Homebrew installation.
7. Run one explicit `brew update`; use `HOMEBREW_NO_AUTO_UPDATE=1` afterward.

Late documentation fixes keep the certificate when the production fingerprint
is unchanged. Late code/plugin changes require only the gates selected by their
impact, plus a new release suite if they alter the certified production path.

## 5. Command And Evidence Discipline

- Each external step records start, first output, completion, exit status, and
  elapsed time.
- A running silent step emits a heartbeat every 30 seconds.
- Network retries are bounded and identify the transient error.
- Do not hide unrelated `gh`, `brew`, build, or audit commands in one timed
  batch.
- Store machine reports under `.build/focusrelay-validation` and attach the
  concise summary to the issue or PR.
- When invoked inside Codex's macOS seatbelt, `focusrelay-dev` disables only
  SwiftPM's nested sandbox; SwiftPM keeps its normal sandbox in a terminal or CI.
- A reusable report is keyed to Git commit, working-tree production hash,
  Swift version, plugin hash, and validation profile.

## 6. Work-In-Progress And Cleanup

- Maximum active work: one product branch and one process/docs branch.
- Do not create a new worktree when the change fits the current branch.
- After merge, inspect whether every worktree branch is merged into the target.
- Cleanup is report-only by default and requires an explicit apply flag.
- GitHub issues hold current evidence; the local roadmap holds only priority and
  dependency decisions.
