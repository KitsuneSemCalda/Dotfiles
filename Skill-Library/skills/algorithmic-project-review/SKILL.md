---
name: algorithmic-project-review
description: Audit a software project or selected execution path for implementation quality, algorithms, data structures, asymptotic time and space complexity, and evidence-backed opportunities for improvement. Use when the user wants a performance-oriented code review, complexity analysis, scalability assessment, or better algorithmic design. The review is read-only unless the user separately asks to implement changes; do not use as a substitute for a general architecture, security, or repository-health audit.
---

# Algorithmic Project Review

Explain how the project transforms its inputs, where work and memory grow, and which changes would
materially improve it. Judge implementation choices in the context of the actual workload rather
than treating lower Big-O notation as an automatic win.

## Operating boundary

The audit is read-only. Inspect source, configuration, tests, documentation, and version history;
run safe existing tests, benchmarks, profilers, or representative commands when proportionate. Do
not edit code, install dependencies, generate persistent project artifacts, or execute untrusted or
production-affecting workloads unless the user separately authorizes that action.

Avoid turning this into an exhaustive style review. Mention naming, abstraction, or architecture
only when they obscure algorithmic behavior, duplicate work, prevent measurement, or materially
increase implementation risk. Treat security and correctness issues as important when discovered,
but recommend a dedicated review if either becomes the dominant concern.

## Establish the model

1. Identify the project's purpose, important entry points, execution model, and expected workload.
2. Define the independent input variables before using asymptotic notation. For example, distinguish
   records `n`, edges `m`, query count `q`, payload bytes `b`, and concurrency `c` rather than hiding
   them all inside `n`.
3. Trace the critical data flow from input through transformations, storage, and output. Include
   database, filesystem, network, serialization, and framework work when they dominate the path.
4. State material unknowns such as data distribution, maximum size, latency target, memory budget,
   mutation frequency, or deployment constraints. Use scenarios instead of inventing requirements.

For a large project, prioritize user-specified paths, hot paths supported by evidence, core domain
algorithms, and operations whose cost scales with external input. Explain the inspected scope; do
not imply complete coverage from a sample.

## Analyze implementation

Read [references/analysis-method.md](references/analysis-method.md) and apply the relevant checks.

For each important operation:

- describe the algorithm in plain language;
- identify the data structures and the invariants they maintain;
- derive time and auxiliary-space complexity from the code, naming all relevant variables;
- distinguish worst-case, expected, average, amortized, and output-sensitive bounds when the
  distinction matters;
- include preprocessing, allocation, copies, recursion depth, retained memory, and result size;
- note assumptions required for the bound, such as hash behavior, balanced trees, sorted inputs,
  cache policy, or bounded key size;
- connect the analysis to concrete file and line evidence.

Analyze composition rather than labeling isolated loops. Sequential phases add, nested dependent
work multiplies, early exits change best-case behavior, and calls hidden behind library or ORM APIs
still have costs. Do not drop meaningful variables or constants merely to make the expression look
simpler.

## Validate likely bottlenecks

Separate three claims:

- **theoretical risk:** growth rate or pathological behavior inferred from the implementation;
- **observed bottleneck:** measured cost under a described workload;
- **projected bottleneck:** likely future constraint based on an explicit scale assumption.

Use existing performance evidence first. When safe and useful, run a representative benchmark or
profiler with controlled inputs, note the environment and command, repeat enough to detect obvious
noise, and avoid presenting microbenchmark results as end-to-end behavior. Never claim that a code
path is “slow” solely because its asymptotic bound looks unfavorable at input sizes the project will
not encounter.

## Find improvements

Consider changes in this order:

1. eliminate unnecessary work, repeated scans, duplicate queries, conversions, copies, or
   recomputation;
2. choose a better algorithm or exploit a domain constraint;
3. choose a data structure matching lookup, update, ordering, and memory needs;
4. batch, stream, index, cache, precompute, or parallelize where the workload supports it;
5. tune low-level constants only when measurement shows they matter.

For every recommendation, explain the current behavior, proposed change, expected complexity or
operational effect, supporting evidence, and tradeoffs. Include memory, correctness, determinism,
maintainability, concurrency, invalidation, and dependency costs where relevant. Prefer a smaller,
safer change when it captures most of the benefit.

Do not recommend optimization that lacks a plausible workload, preserves no required invariant, or
merely exchanges one bottleneck for another. Do not describe speculative improvements as measured
gains. When the current implementation is already appropriate, say so.

## Report

Use [references/reporting.md](references/reporting.md). Lead with the execution paths and variables
that dominate scaling, then rank findings by likely impact, evidence strength, and effort. Keep
correctness defects separate from performance improvements so urgency is not confused with speed.

## Completion standard

The audit is complete when the user can see what was inspected, how the core implementation works,
which input dimensions determine time and memory, where conclusions are derived versus measured,
which current choices are sound, and which few improvements have the strongest evidence and best
tradeoff. If missing workload information prevents meaningful prioritization, return the valid
complexity analysis and a concrete measurement plan rather than fabricating a bottleneck.
