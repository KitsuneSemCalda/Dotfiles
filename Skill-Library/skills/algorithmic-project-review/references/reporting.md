# Reporting the audit

Scale the report to the project and inspected scope. Prefer a small number of well-supported
findings over an inventory of every loop and container.

## Scope and workload model

State the revision or working tree inspected, entry points and paths analyzed, input variables,
assumed workloads, commands run, and important limitations.

## Implementation map

Summarize the important flow of data and control. Identify the algorithms, structures, persistence
or external calls, and invariants that determine cost. Include positive choices that should be
preserved.

## Execution graph and timeline

Show the meaningful stages and their dependency, transfer, and synchronization edges. Annotate
measurable nodes with wall/CPU time and relevant RAM, I/O, GPU, or wait costs. Mark unavailable data
as unknown. Add a timeline when concurrent branches, queueing, or idle gaps matter. Keep the graph
small enough to expose the latency-determining path.

State the critical path and each measured stage's contribution to end-to-end latency. Do not add
parallel branch times together. Identify the workload and environment before comparing percentages.

## Complexity table

For each material operation, report:

| Operation | Input variables | Time | Auxiliary space | Basis and assumptions |
|---|---|---|---|---|

Use precise multi-variable expressions where useful. Do not force Big-O onto fixed-size or
I/O-dominated work when a plain operational description is more informative.

## Findings

Order findings by expected value. Each finding should include:

- **Evidence:** exact code location, measurement, or observed call pattern.
- **Current behavior:** algorithm, data movement, queries, allocations, or coordination involved.
- **Impact:** affected workload and the scale at which it matters.
- **Improvement:** smallest credible change and why it helps.
- **After:** expected complexity or operational effect, clearly labeled as derived or projected.
- **Tradeoffs:** memory, maintenance, correctness, concurrency, dependencies, or migration cost.
- **Confidence and validation:** evidence strength and the benchmark, profile, or test that would
  confirm the result.

Classify each as correctness risk, demonstrated bottleneck, scalability risk, or maintainability
barrier to optimization. Do not use severity labels without explaining the impact model.

For a measured bottleneck, name its node, resource classification, supporting metrics, impact on the
critical path, and confidence. Report CPU, RAM, GPU/VRAM when applicable, I/O, and synchronization
in a compact resource summary. Separate observed wasted work from suspected unnecessary work.
Discuss parallelism only when the graph shows independent work and its scheduling or transfer costs
are plausible. Do not propose GPU work solely because an algorithm is parallelizable.

For an optimization candidate, estimate its end-to-end effect using the measured baseline and the
dependency graph; label assumptions and expected next bottleneck. If no baseline exists, give a
measurement plan rather than a numeric speedup. If a change was separately authorized and made,
record before, after, variance, workload, and environment.

## Recommended sequence

Conclude with:

1. changes justified now;
2. measurements needed before changing code;
3. ideas intentionally deferred because the likely gain does not justify the tradeoff.

Finish with a concise diagnosis: primary and secondary bottlenecks, critical path, most promising
change, projected impact if calculable, and confidence. If profiling was unavailable, explicitly
state that the bottleneck and impact are unknown; preserve the useful graph and complexity analysis.

If implementation was not requested, stop at recommendations and do not modify the project.
