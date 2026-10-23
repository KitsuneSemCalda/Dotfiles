# Reporting a substantial review

Scale detail to the artifact and user request. Use the following structure when the review covers
significant implementation decisions; omit empty sections for a narrow critique.

## Summary and major findings

Give a short assessment and rank the few issues with the highest user impact. Locate each finding
in the artifact and distinguish observed failure, measured bottleneck, derived risk, and hypothesis.

## Engineering lens review and disagreements

Summarize the relevant Carmack, Torvalds, DHH, Ritchie, and Thompson assessments independently.
State actual disagreements and the project constraint used to resolve them. Do not force a conflict
where the lenses agree or where a lens adds no useful observation.

## Evidence and assumptions

Report what was measured or observed, the workload and environment where relevant, and what remains
unverified. Do not present a test pass as proof of performance or a profiler trace as proof of
correctness.

## Recommendations

Order by P0 correctness or safety, P1 material architecture, P2 evidenced performance, P3
simplification, and P4 polish. For each material recommendation include:

- **Problem and evidence:** exact location, behavior, measurement, or missing proof;
- **Impact:** user consequence and affected workload;
- **Proposed change and expected benefit:** concrete mechanism, with measured or hypothetical gain
  clearly labeled;
- **Cost and risk:** implementation, maintenance, migration, and regression exposure;
- **Confidence:** high, medium, low, or speculative, with validation needed.

Include a “What should not be changed” section for sound choices. Conclude with a short verdict:
Excellent, Strong, Adequate, Mediocre, Overengineered, Underengineered, Performance-constrained,
Architecturally unstable, or Requires measurement. Explain it with evidence, not rhetoric.
