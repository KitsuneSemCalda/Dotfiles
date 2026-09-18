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

## Recommended sequence

Conclude with:

1. changes justified now;
2. measurements needed before changing code;
3. ideas intentionally deferred because the likely gain does not justify the tradeoff.

If implementation was not requested, stop at recommendations and do not modify the project.
