---
name: ponytail
description: Find the simplest solution that fully meets a coding request. Use when the user asks for minimal code, fewer dependencies, YAGNI, or a simpler design, or when an existing proposal appears overengineered. Do not use merely because the task involves code.
argument-hint: "[lite|full|ultra]"
license: MIT
---

# Ponytail

Reduce the solution's cost without reducing its required behavior. First understand the request, trace the affected code and callers, and identify the invariant the change must preserve. Then choose the smallest complete solution.

## Decision ladder

Consider, in order, whether the need is already met, whether existing project code can be reused, whether the standard library or platform provides the behavior, and whether a small local change is enough. Add a dependency or abstraction only when it solves a concrete problem better than those options. Do not turn this check into a separate research project.

For a bug, find the cause and inspect relevant callers before choosing where to fix it. A shared fix is useful when those callers share the same invariant; otherwise fix the affected path. Prefer a small diff, but include every change needed for correctness, integration, and safe failure handling.

## Modes

- **Lite:** Complete the requested design, then briefly identify a simpler option if it is materially useful.
- **Full (default):** Implement the simplest complete design supported by the evidence.
- **Ultra:** Challenge speculative requirements and delete unnecessary work, while still honoring explicit requirements.

Use the mode requested by the user. An explicitly requested mode can carry across related work in the session; a mode inferred from one task applies only to that task. The user can change or stop it at any time.

## Boundaries

- Preserve explicit requirements, trust-boundary validation, data integrity, security, accessibility, and error handling that prevents real failures.
- For hardware or external systems, keep necessary calibration and configuration based on observed variation.
- Verify a nontrivial change with the smallest meaningful check for its risk. Use existing tests when they cover the behavior; add a check only when it would catch a plausible regression. Do not mandate one test per branch or loop.
- Name a known limit when a deliberate simplification has a credible ceiling, and state the condition that would justify revisiting it. Add a code comment only when a future maintainer needs that context at the decision point.

Report what changed and how it was checked. Explain an omitted design or feature only when it was requested or its absence affects a decision.
