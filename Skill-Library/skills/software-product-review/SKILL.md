---
name: software-product-review
description: Analyze a software project through computer science, software engineering, architecture, and product viability. Use for a multidisciplinary review or a prioritized plan to turn an existing project into a usable product. This is a read-only assessment unless implementation is separately requested; use a focused performance or repository-health review for those narrower requests.
---

# Software Product Review

Evaluate whether a project solves a worthwhile problem for identifiable users and what would make it dependable, usable, maintainable, and economical as a product. Treat bodies of knowledge as lenses for asking better questions, not as certification checklists. Match the depth of the review to the project's size, maturity, domain, and risk.

## Boundary

The review is read-only. Inspect code, tests, documentation, configuration, and available usage evidence. Run safe existing checks when proportionate. Do not change code, install dependencies, deploy, publish, or create issues without a separate request. Never present a source review as proof of market demand, security, or production readiness.

## Establish the product context

Identify the project's current purpose, intended users, primary task, deployment environment, constraints, and maturity. Trace one or more representative journeys from user input to result, including data storage and external systems. If audience, workload, or business model is unknown, state assumptions and evaluate plausible scenarios; do not invent validation. Distinguish a working prototype, an internally useful tool, and a product ready for outside users.

For a large repository, sample the paths that support its core promise and explain what was inspected. Prioritize user-specified concerns and failures visible in real workflows.

## Assess the relevant disciplines

Choose the questions that affect this project. Use [CS2023](https://csed.acm.org/knowledge-areas/) for computer-science topics, [SWEBOK](https://www.computer.org/education/bodies-of-knowledge/software-engineering) for engineering work, [SEBoK](https://sebokwiki.org/wiki/Guide_to_the_Systems_Engineering_Body_of_Knowledge_(SEBoK)) when system boundaries and stakeholders matter, and [SEI's quality-attribute approach](https://insights.sei.cmu.edu/library/reasoning-about-software-quality-attributes/) for architecture. These are guides to select relevant concerns, not claims that the project must implement every area.

- **Computer science:** Explain important algorithms and data structures, correctness invariants, input dimensions, time and auxiliary-space costs, and limits imposed by I/O, storage, or network work. Separate best, worst, expected, and amortized cases where meaningful. Seek lower-cost polynomial algorithms, indexing, batching, streaming, or constant-time operations when the workload justifies them. Do not demand O(1) for work that must read or emit variable-sized data; account for preprocessing, memory, and maintenance costs. Label theoretical risks, measured bottlenecks, and projections separately.
- **Software engineering:** Check whether behavior and acceptance criteria are clear; whether failures and boundary inputs are handled; whether tests exercise important behavior; and whether builds, releases, dependencies, migrations, and maintenance are reproducible enough for the intended users. Include privacy, accessibility, and security when the product handles people, data, or trust boundaries. Prefer observed failure modes over generic process prescriptions.
- **Architecture:** Map components, data ownership, dependencies, interfaces, and external services. Derive quality goals from concrete scenarios such as latency at a stated load, recovery after a failure, or the effort to change a feature. Examine coupling, cohesion, deployment and data evolution, observability, and the tradeoffs among performance, reliability, security, and changeability. Recommend architectural change only when a current or credible near-term need warrants its cost.
- **Product use:** Identify the user problem and the shortest complete path to value. Check onboarding, defaults, error messages, documentation, distribution, support burden, licensing or integration constraints, and evidence of demand or repeat use when available. Separate technical readiness from value validation. State what evidence would confirm that the project is worth productizing.

## Apply named practices with judgment

Clean Code, SOLID, Clean Architecture, the JPL Power of Ten rules, Object Calisthenics, and the Twelve-Factor App are practices or design heuristics, not bodies of knowledge or automatic pass/fail standards. For each applicable practice, name the concrete problem it helps solve and the cost of applying it here.

- **Clean Code:** Look for misleading names, hidden side effects, avoidable duplication, and hard-to-follow control flow when they cause defects or slow changes. Do not reward small functions or extra abstractions by themselves.
- **SOLID:** Apply to object-oriented design where responsibilities, extension points, substitutability, interface size, or dependency direction are causing real friction. Do not add interfaces or dependency injection solely for conformance.
- **Clean Architecture:** Check boundary and dependency choices when domain behavior must survive changes in UI, persistence, or infrastructure. A simple project may need only clear modules; do not prescribe layers or ports and adapters without a concrete benefit.
- **JPL Power of Ten:** Consider the [original safety-critical C rules](https://spinroot.com/gerard/pdf/Power_of_Ten.pdf) for safety-critical or embedded C, or selectively transfer principles such as bounded execution, assertions, and analyzability to similar risk profiles. Do not impose C-specific rules on unrelated languages or imply that following them certifies safety.
- **Object Calisthenics:** Use its constraints as optional exercises for object-oriented code with poor encapsulation or tangled responsibilities. Do not treat arbitrary counts of indentation, fields, or methods as product quality metrics.
- **Twelve-Factor App:** For applications deployed as services, assess the [twelve factors](https://12factor.net/) against the actual deployment model: codebase, dependencies, config, backing services, build/release/run, processes, port binding, concurrency, disposability, dev/prod parity, logs, and admin processes. Identify which factors apply, which do not, and the concrete operational impact of any gap. For example, check reproducible releases, environment-specific configuration, persistent state, startup and shutdown behavior, and log collection. Do not force service-oriented conventions onto desktop tools, libraries, or embedded software, or require stateless processes when the product's state model makes that inappropriate.

Other frameworks may help if the domain warrants them. Explain their relevance and avoid stacking overlapping checklists.

## Turn analysis into decisions

For each material finding, provide: the affected user journey or quality goal; exact evidence (file and line, command result, or observed behavior); the underlying cause; impact at a stated workload or scenario; the smallest useful change; tradeoffs; and a way to verify success. Mark observations, inferences, and unknowns distinctly. Do not infer a vulnerability, bottleneck, or user demand from style alone.

Report in the user's language. Start with a brief product thesis and a conditional readiness judgment. Then give the strongest existing assets, the few highest-impact gaps, and a prioritized path from current state to a usable product. Separate **now**, **next**, and **later** only when sequencing helps; include a measurable success criterion for each proposed step. End with the missing evidence or user decision that would most change the plan. If the project is already appropriate for its intended use, say so without inventing work.
