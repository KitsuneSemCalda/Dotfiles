---
name: software-project-analysis
description: Analyze an existing software project as an engineered computational system across computer science, software engineering, architecture, systems, security, reliability, data, and product concerns. Use for a broad, evidence-based technical assessment and prioritized improvement plan. For a narrower performance audit, repository-health audit, or product-readiness review, use the corresponding focused skill.
---

# Software Project Analysis

Explain what the project does, how it works, where its real constraints lie, and which changes create the greatest justified engineering and product value. Apply bodies of knowledge as diagnostic tools, never as a compliance scorecard. A technically interesting change must produce a useful capability or improve a relevant quality at an acceptable cost.

## Boundary and evidence

The analysis is read-only unless the user separately requests implementation. Inspect source, tests, documentation, configuration, and available operational evidence. Run safe existing checks when useful; do not install dependencies, deploy, publish, or run destructive workloads merely to complete a review. Record the inspected revision and scope. Do not imply full coverage from sampled paths.

Classify claims as confirmed problem, probable problem, theoretical risk, architectural risk, maintainability concern, or preference. Cite exact code locations, measurements, commands, or observed behavior for material findings. State assumptions and missing data. Never invent benchmarks, market demand, vulnerabilities, or production guarantees.

## Build the project model

Classify the project by actual role: application, service, library, CLI, infrastructure, low-level system, data or AI system, prototype, or a combination. Identify users, primary use cases, critical execution paths, architecture, deployment environment, expected lifetime, and rate of change. Determine or explicitly mark unknown workload, scale, latency, throughput, memory, storage, reliability, security, and portability requirements. Trace representative input through computation, storage or external calls, and output.

Do not assume hyperscale. Do not excuse a harmful algorithm solely because today's input is small. Evaluate current and credible future constraints separately.

## Analyze from five core perspectives

1. **Computer science:** Derive important time and auxiliary-space bounds from code. Name independent input variables and distinguish best, worst, average, expected, and amortized cases where useful. Check invariants, termination, data structures, memory layout, I/O, concurrency, and theoretical limits. O(1) is not a universal goal; include constants, preprocessing, output size, allocations, locality, contention, and workload distribution. Separate inferred scaling risk from a measured bottleneck.
2. **Software engineering:** Examine requirements, contracts, error handling, boundaries, APIs, dependency management, build and release, and tests around invariants, failure cases, and regressions. Treat coverage as execution evidence, not proof of correctness. Judge code clarity by whether a maintainer can change behavior safely, not by line-count rules.
3. **Software architecture:** Map components, relationships, data ownership, failure domains, deployment units, and dependency direction. Turn desired qualities into concrete scenarios, then assess coupling, change propagation, scalability, reliability, security, operability, and tradeoffs. Prefer minimum sufficient architecture.
4. **Systems engineering:** Consider interactions with users, hardware, operating systems, external services, and operational processes. Check end-to-end failure paths, resource and lifecycle constraints, and whether local decisions preserve system-level behavior.
5. **Product engineering:** Trace installation through first and repeated successful use. Assess user value, defaults, usability, documentation, updates, compatibility, diagnostics, support cost, and operational economics. Distinguish technical readiness from evidence of demand.

Read [references/conditional-lenses.md](references/conditional-lenses.md) for domain-specific questions and named practices. Apply only lenses relevant to the project's type and risks. Explain why a lens applies before recommending a change.

## Decide what to improve

For each significant recommendation answer: What observed problem or credible constraint does it address? Why is the current approach insufficient? What benefit is expected and at what workload? What complexity, risk, and migration cost does it add? What simpler alternative exists? How would success be checked? If these cannot be answered, leave it as a hypothesis or omit it.

Seek whole-class improvements such as eliminating repeated work, improving an algorithm, batching I/O, strengthening an invariant, or removing an avoidable failure mode. Consider differentiated capabilities only when they create visible user or operator value. Preserve sound existing choices. Do not recommend fashionable technology, speculative abstractions, or a full rewrite to satisfy a pattern.

Prioritize correctness, data loss, security, and reliability risks according to actual domain impact; then rank other work by expected benefit, effort, confidence, and change risk. Use coarse judgments rather than invented precision. Mark experimental opportunities as requiring validation.

## Report

Use [references/reporting.md](references/reporting.md). Include positive findings, relevant complexity analysis, applicable bodies of knowledge, productization gaps, and a prioritized plan. Keep categories concise when the project provides little evidence; mark them not assessed rather than manufacturing findings. The final recommendations must make the project better for its actual purpose, not more compliant with this skill.
