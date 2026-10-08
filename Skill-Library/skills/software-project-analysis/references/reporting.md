# Reporting the analysis

Use the user's language. Follow this order, combining brief or empty sections when that improves readability. Include only applicable subcategories; preserve the distinction between what was inspected and what remains unknown.

1. **Project model:** Purpose, users, architecture, critical path, constraints, inspected revision and scope, commands run, and material assumptions.
2. **What is already good:** Sound decisions worth preserving and why they work here.
3. **Computer science findings:** Relevant algorithms, data structures, time and auxiliary-space complexity, memory, concurrency, and limits. For a proposed replacement, compare current and alternative bounds, assumptions, and tradeoffs. Define input variables; identify worst case where relevant.
4. **Software engineering findings:** Requirements, maintainability, cohesion, coupling, APIs, failures, tests, build, and dependencies.
5. **Architecture findings:** Boundaries, dependency direction, data flow and ownership, failure domains, and deployment.
6. **Applicable knowledge bodies:** A compact table with body or practice, applicability, observed state, and justified action. Include only lenses that changed the analysis; mark inapplicable high-profile practices only when their omission would otherwise be surprising.
7. **Performance opportunities:** Applicable algorithmic, memory, I/O, database, concurrency, and network opportunities. Distinguish measured gains from theoretical or projected ones.
8. **Architectural opportunities:** Separate necessary changes, valuable improvements, and experiments requiring validation.
9. **Prioritized engineering plan:** A table with priority, finding, reason, effort, expected benefit, risk, and verification. Use Critical, High, Medium, Low, or Experimental where justified; use coarse effort and confidence labels.
10. **Top three changes:** End with up to three highest-value changes, each with the problem, proposed action, expected effect, and tradeoff. If fewer than three are justified, list fewer.

Each material finding needs concrete evidence, impact at a stated scenario or workload, a specific recommendation, and how to check success. State when missing evidence prevents a stronger conclusion. Do not let a long list of possible frameworks displace the few decisions the user can act on.
