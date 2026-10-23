---
name: anti-ai-mediocrity
description: Critique or improve AI-generated software artifacts that sound polished but are generic, ungrounded, overengineered, or incomplete. Use when the user wants a rigorous second pass on generated code, designs, plans, tests, or technical reviews. For prose-only AI writing tells, use a writing-focused skill; for a full project audit, use a project-review skill.
---

# Anti-AI Mediocrity

Make a software artifact earn its claims. The target is a plan, design, implementation, test suite, or review that appears complete while leaving the user's actual problem unresolved. A short, ordinary solution can be excellent; sophistication is not a quality signal.

## Establish the real task

Read the user's request, constraints, and relevant project context before judging the artifact. Identify its promised outcome and the observable result that would demonstrate success. Trace the relevant execution path or decision path. If source context is missing, make a limited assessment and label assumptions; do not fill gaps with invented details.

## Find substance gaps

Check only for failures that matter to the requested outcome:

- Generic advice that could apply unchanged to any repository, unsupported praise or severity, or recommendations without a concrete code path, scenario, or user consequence.
- Plausible-looking code that does not integrate with callers, data shapes, errors, state, deployment, or existing conventions; TODOs and placeholders presented as finished work.
- Cargo-cult layers, interfaces, services, caches, concurrency, dependencies, patterns, or framework changes without a known need and cost comparison.
- Tests that merely mirror implementation, assert trivial behavior, skip boundaries and failure modes, or cannot detect the defect they claim to cover.
- Performance claims based only on Big-O labels, imagined scale, invented benchmarks, or optimization of a non-dominant path.
- Algorithm recommendations that overlook current alternatives or cite a paper's benchmark as proof of a gain on this workload. For material claims, search current primary sources and compare equivalent behavior and measured cost against the existing baseline when feasible; label untested gains as hypotheses.
- Safety, security, reliability, or product-readiness claims without a credible threat or failure model and a way to verify them.
- Long checklists, repeated caveats, and polished summaries that bury the decision or leave no actionable next step.

Also check for the opposite error: a terse answer that omits an essential invariant, migration step, error path, or proof of behavior. Do not penalize justified complexity or reward code deletion that breaks requirements.

## Apply independent engineering lenses

For meaningful implementation or architectural decisions, review the artifact through several independent engineering lenses. These are principles associated with publicly documented engineering work, not impersonations. Never invent quotes or claim that a named programmer would personally approve or reject the code.
Use [references/engineering-lenses.md](references/engineering-lenses.md) for the expanded checks and tradeoffs.

### John Carmack lens

Prioritize measurable runtime cost, data flow, latency, locality, memory movement, synchronization, and elimination of unnecessary work.

Ask:

- Is this work actually on a hot or critical path?
- Are allocations, conversions, copies, dispatch, or synchronization avoidable?
- Does the data layout fit the hardware and access pattern?
- Is an abstraction hiding a meaningful runtime cost?
- Is an optimization supported by profiling rather than intuition?

Reject speculative micro-optimization without evidence.

### Linus Torvalds lens

Prioritize appropriate data structures, small interfaces, explicit invariants, predictable control flow, and code that can be reviewed locally.

Ask:

- Is complexity caused by the wrong representation of data?
- Can a maintainer understand ownership and error paths without reconstructing the whole system?
- Is an abstraction clarifying behavior or merely moving it somewhere harder to see?
- Is cleverness replacing a better data structure or simpler control flow?

### DHH lens

Prioritize delivery, convention, boring solutions, and removal of accidental complexity.

Ask:

- Is this architecture solving a demonstrated problem?
- Is infrastructure being introduced before the project needs it?
- Does the abstraction reduce total complexity, or only move it?
- Is permanent complexity being purchased for a hypothetical future requirement?

### Dennis Ritchie lens

Prioritize small mechanisms, composable primitives, transparent abstractions, and sufficient control over the underlying system.

Ask:

- Are the fundamental primitives small and sufficient?
- Can complex behavior be composed from simpler pieces?
- Does the abstraction preserve the control needed by callers?
- Is policy being baked into a mechanism that should remain general?

### Ken Thompson lens

Prioritize minimalism, replaceable components, understandable systems, and deletion of unnecessary machinery.

Ask:

- What can be removed without losing required behavior?
- Has a small tool accidentally become a framework?
- Can independent pieces be replaced without rewriting the whole system?
- Will the design remain understandable after years of maintenance?

## Handle disagreement instead of averaging it away

The lenses are expected to conflict. Do not manufacture consensus.

For each material disagreement:

1. identify the conflicting principles;
2. state the project constraint that makes the conflict relevant;
3. provide measured consequences where available;
4. distinguish evidence from preference;
5. choose the trade-off that best fits the actual project.

Authority is not evidence. A famous name never wins a technical dispute by itself.

## Evidence hierarchy

Prefer evidence in this order when the question permits it:

1. measurements from the actual application;
2. representative benchmarks and traces;
3. tests and observed behavior;
4. algorithmic analysis and language/runtime guarantees;
5. primary documentation and source code;
6. defensible engineering inference;
7. style or preference.

Never present a lower level as if it were a higher one.

## Replace polish with evidence

For each material gap, state the exact claim or artifact location, what evidence is missing or contradictory, why it affects the user, and the smallest correction. Verify with a meaningful test, trace, benchmark, or source citation when proportionate and authorized. Distinguish observed failure from hypothesis. Keep good parts and say why they work.

When making a recommendation, include when useful:

- **Problem**
- **Evidence**
- **Impact**
- **Proposed change**
- **Expected benefit**
- **Cost**
- **Risk**
- **Confidence**

Do not say that something "should be faster" when the real claim can be stated more precisely, such as removing a full buffer copy or reducing an O(n) traversal. If the gain is not measured, say so.

## Scheduled review mode with cron

Normal use is one-shot. Enter scheduled mode only when the user explicitly asks this skill to run repeatedly, periodically, automatically, continuously, on a schedule, or as a loop.

On Unix-like systems where `cron` and `crontab` are available, use the system cron scheduler rather than keeping an agent session, shell loop, terminal, tmux session, or long-lived process alive.

### Scheduling contract

A recurring review must behave as discrete executions:

```text
cron -> one review iteration -> persist state -> exit
```

Each scheduled invocation must terminate after one bounded pass. Never implement recurring execution with `while true`, repeated `sleep`, recursive self-invocation, or an AI process intentionally kept alive between runs.

When setting up scheduled mode:

1. Resolve the project path, target artifact or review scope, requested cron expression, and the agent CLI that will execute the skill non-interactively.
2. Verify `cron`/`crontab` availability and the CLI's actual non-interactive invocation before installing anything. Do not invent command-line flags.
3. Create a small per-task runner script outside the project, preferably under `~/.local/bin/` or an XDG data directory. Use absolute paths and establish `HOME`, `PATH`, working directory, and required configuration explicitly because cron does not inherit the interactive shell environment.
4. Store scheduler state under `~/.local/state/skills/anti-ai-mediocrity/<task-id>/` or the corresponding XDG state path.
5. Protect execution with `flock` when available so a slow review cannot overlap the next scheduled run.
6. Install a managed crontab block with stable markers such as:

```cron
# BEGIN skill-loop:anti-ai-mediocrity:<task-id>
<expression> <absolute-runner-path>
# END skill-loop:anti-ai-mediocrity:<task-id>
```

7. Read and preserve the user's unrelated crontab entries exactly. Updating the schedule must replace the existing managed block rather than append duplicates.
8. Capture stdout, stderr, exit status, start time, finish time, and the inspected revision in the task's state/log directory.
9. Provide an idempotent way to inspect, disable, update, and remove the managed cron entry.

If cron is unavailable, report that scheduled cron mode cannot be installed on the current system. Do not silently substitute another scheduler unless the user explicitly asks for one.

### Incremental scheduled reviews

For repository-backed work, persist the last successfully reviewed revision. On the next scheduled run:

- resolve the current revision;
- skip expensive review when nothing material changed;
- otherwise inspect the relevant diff plus any surrounding code needed to judge it correctly;
- periodically widen scope only if the configured task explicitly requires a full review.

Do not treat unchanged code as newly reviewed merely because the scheduler woke up.

Scheduled mode does not expand authorization. If the ordinary skill is read-only for the current task, the cron job remains read-only. Never turn an automated critique into an automated refactor, commit, merge, deployment, or dependency update without separate explicit authorization.

## Completion

If the user asks for a critique, provide a short ranked list of substantive issues and a concrete revision path. If the user asks to fix the artifact, make the corrections within the authorized scope and verify the result. Do not create work just to make the artifact look more comprehensive. Stop when the promised outcome is demonstrably met or when the remaining uncertainty is stated plainly.
For a substantial review, use [references/reporting.md](references/reporting.md) and scale the report to the decision.

For scheduled mode, one iteration is complete when the current scope has been reviewed, the result and revision have been persisted, logs are closed, and the process exits cleanly.
