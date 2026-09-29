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
- Safety, security, reliability, or product-readiness claims without a credible threat or failure model and a way to verify them.
- Long checklists, repeated caveats, and polished summaries that bury the decision or leave no actionable next step.

Also check for the opposite error: a terse answer that omits an essential invariant, migration step, error path, or proof of behavior. Do not penalize justified complexity or reward code deletion that breaks requirements.

## Replace polish with evidence

For each material gap, state the exact claim or artifact location, what evidence is missing or contradictory, why it affects the user, and the smallest correction. Verify with a meaningful test, trace, benchmark, or source citation when proportionate and authorized. Distinguish observed failure from hypothesis. Keep good parts and say why they work.

If the user asks for a critique, provide a short ranked list of substantive issues and a concrete revision path. If the user asks to fix the artifact, make the corrections within the authorized scope and verify the result. Do not create work just to make the artifact look more comprehensive. Stop when the promised outcome is demonstrably met or when the remaining uncertainty is stated plainly.
