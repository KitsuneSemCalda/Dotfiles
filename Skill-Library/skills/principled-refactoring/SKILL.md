---
name: principled-refactoring
description: Refactor existing code using context-sensitive design principles while preserving required behavior. Use for requested structural improvements involving Clean Code, SOLID, Clean Architecture, patterns, algorithms, data structures, or JPL rules. Skip ordinary features, narrow fixes, and read-only audits.
---

# Principled Refactoring

Improve the code's ability to support a concrete change or quality goal. Principles are lenses for choosing a refactor, not requirements to make the code resemble a textbook.

## Decide what needs to change

1. Identify the requested outcome and scope. If the user asked only for recommendations, inspect and report without editing. Otherwise trace the affected path, callers, contracts, data ownership, and existing checks.
2. State the current friction or failure risk in observable terms: a change touches unrelated modules, an invariant is duplicated, a boundary leaks framework details, a structure makes common operations costly, or another specific problem.
3. Read the relevant sections of [decision lenses](references/decision-lenses.md). Select only principles that explain that problem. For each proposed change, compare the smallest viable refactor with leaving the code as it is. Name the benefit, added complexity, and condition under which the refactor pays off.
4. Preserve required behavior and public contracts unless the user requests a behavior change. Make the smallest coherent change at the right boundary. If behavior must change to meet the request, identify that separately rather than presenting it as a pure refactor.
5. Verify the affected behavior with existing checks or a focused new check that could catch a plausible regression. Inspect the diff for unintended interface, data, or performance changes. If verification is unavailable, state what was inspected and what remains unverified.

Do not introduce a layer, interface, pattern, dependency, or new data structure merely to satisfy a named principle. Do not move code solely to make a diagram cleaner. When the current design is suitable for the expected changes and workload, say so and avoid churn.

## Report

Explain the concrete pain, the chosen change, the reason it is smaller or safer for this context, and the evidence that behavior still works. Mention rejected alternatives only when the tradeoff matters to the user's decision. For read-only requests, rank a few justified opportunities by impact and implementation risk.
