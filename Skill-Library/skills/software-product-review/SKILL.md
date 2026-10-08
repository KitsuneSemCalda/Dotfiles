---
name: software-product-review
description: Review whether an existing software project solves a worthwhile problem for identifiable users and what would make it usable and viable as a product. Use for product readiness, adoption, onboarding, distribution, and a prioritized path to real use. For broad technical analysis, use software-project-analysis; for performance or repository health, use the focused review.
---

# Software Product Review

Assess the project's path from a user's problem to repeated successful use. Judge technical work by its effect on that path and the cost of delivering and supporting it. Match the depth to the project's maturity and risk.

## Scope

This is a read-only review unless the user separately requests implementation. Inspect code, documentation, tests, release paths, and available usage evidence; run safe existing checks when proportionate. Do not present source review as proof of demand, security, or production readiness. For a large project, sample representative user journeys and state the inspected scope.

## Product model

Identify intended users, the task they want done, the current alternative, deployment context, and evidence of use or demand. Trace at least one path from discovery and installation through first success and repeated use. Include external services, storage, updates, and support when they affect the journey. Mark missing audience, workload, and business facts as unknown rather than inventing them.

Distinguish a working prototype, a useful internal tool, and a product ready for outside users. The user may want a personal tool to remain personal; do not prescribe commercialization or growth without a reason.

## Review questions

Select only the questions that can change a product decision:

- Can a new user understand the promise, obtain the software, complete the main task, and recover from common errors?
- Does the software behave dependably enough for that task, including relevant correctness, privacy, security, accessibility, data handling, and compatibility?
- Can its maintainers build, release, update, diagnose, and support it at the expected level of use?
- What evidence shows repeat value or demand? If none exists, what is the cheapest credible validation?
- What does the next level of use cost in time, infrastructure, maintenance, or support? If income is a goal, what evidence supports pricing, distribution, and viability?

Investigate implementation details only as far as they explain a material user or operator consequence. Use architecture or engineering practices when a concrete quality goal requires them; avoid a general code audit or checklist of named frameworks.

## Report

Lead with a conditional readiness judgment tied to the intended user and use case. Name the strongest existing assets and a few gaps that block or limit the main journey. For each gap, give exact evidence, the likely consequence, the smallest useful improvement, tradeoffs, and a way to verify success. Separate observed behavior from inference and unknowns. Prioritize steps by user impact and confidence; if the project already fits its intended use, say so.
