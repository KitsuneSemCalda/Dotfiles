# Analysis method

Use this reference selectively. Follow the program's actual execution paths instead of applying it
as a checklist to every file.

## Algorithms

- Identify search, sorting, traversal, parsing, matching, scheduling, aggregation, optimization,
  retry, and synchronization strategies, including algorithms embedded in framework calls.
- Check whether the algorithm exploits relevant properties: ordering, uniqueness, sparsity,
  locality, bounded domains, monotonicity, repeated queries, or incremental updates.
- Inspect termination, degenerate inputs, adversarial inputs, duplicate values, numeric limits, and
  recursion depth when they affect correctness or complexity.
- Account for output size. An operation producing `k` results cannot generally run in less than
  `Ω(k)` time merely because lookup is fast.

## Data structures

Evaluate structures against the operation mix, not in isolation:

- lookup by key, membership, insertion, deletion, ordered iteration, min/max, range query, prefix
  query, graph adjacency, queueing, and random access;
- read/write ratio, cardinality, duplicate handling, ordering guarantees, mutation frequency, and
  concurrency;
- object overhead, capacity slack, locality, pointer chasing, retained references, and copying;
- the cost of maintaining indexes, heaps, caches, denormalized views, or precomputed state.

Check whether equality, hashing, comparison, ownership, and mutability semantics preserve the
structure's invariants.

## Complexity derivation

- Name independent variables and define what operation is being bounded.
- Count calls across layers. A loop containing a database query, linear membership test, sort, or
  copy inherits that inner cost.
- Distinguish auxiliary space from input and output storage; mention peak memory and retained memory
  when useful.
- Identify amortized operations and the sequence over which amortization holds.
- For recursive or divide-and-conquer code, state the recurrence or explain the call tree.
- For randomized or hash-based behavior, state the expectation and pathological case when relevant.
- For concurrent code, distinguish total work, critical-path latency, contention, and maximum
  in-flight memory.
- For lazy pipelines and generators, distinguish construction cost, per-item cost, full-consumption
  cost, and repeated enumeration.

## Operational costs beyond Big-O

Inspect factors that can dominate practical behavior:

- database round trips, query plans, missing or overused indexes, N+1 access, transaction scope;
- network round trips, payload volume, retries, timeouts, rate limits, and fan-out;
- filesystem access, buffering, random versus sequential I/O, and repeated parsing;
- serialization, compression, allocation rate, garbage collection, cache locality, and lock
  contention;
- unbounded queues, caches, buffers, task creation, or concurrency.

These costs complement asymptotic analysis; they do not justify unsupported performance claims.

## Evidence hierarchy

Prefer, in order:

1. representative production or realistic profiling data with known inputs;
2. project benchmarks and regression tests;
3. controlled measurements performed during the audit;
4. direct code-derived operation counts and complexity bounds;
5. reasoned hypotheses requiring validation.

Label the evidence level for material findings. A higher-ranked source is not automatically valid
if its workload does not match the path being discussed.
