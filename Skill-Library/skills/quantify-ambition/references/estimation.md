# Evidence and estimation

## Number classes

Label important numbers using these classes:

- **Known:** measured directly from the project or supplied by the user.
- **Benchmark:** sourced from a comparable system or authoritative external source.
- **Estimate:** derived from stated inputs and assumptions.
- **Target:** a strategic choice describing the desired future.
- **Limit:** a hard capacity, policy, physical, legal, or budget constraint.
- **Unknown:** material but not yet defensibly quantifiable.

Never present one class as another. Include the observation date for facts likely to change.

## Estimation method

1. Define the question and output unit.
2. Decompose it into factors that can be estimated independently.
3. State the formula before inserting values.
4. Provide sources or assumptions for each input.
5. Calculate a range or scenarios.
6. Check units and order of magnitude.
7. Identify which input most changes the result.
8. Name the cheapest measurement that would improve confidence.

Example structure:

```text
monthly compute cost
= active entities
× operations per entity per day
× days per month
× cost per operation
```

Prefer transparent arithmetic that the user can revise over opaque precision.

## Scenario design

Use scenarios when uncertainty is material:

- **Conservative:** credible progress with restrained adoption or resources.
- **Base:** coherent outcome if the main hypotheses hold.
- **Ambitious:** the scale implied by the full vision, including its consequences.

Scenarios must vary coherent assumptions together. They are not simply the same estimate with
arbitrary multipliers.

## Ranges and uncertainty

- Use one significant digit when inputs are order-of-magnitude guesses.
- Avoid percentages without a denominator and time window.
- Avoid averages when peaks, tails, or cohorts determine feasibility.
- Show sensitivity when one uncertain input dominates the outcome.
- Distinguish uncertainty that research can reduce from uncertainty that requires an
  experiment or real operation.

## Research discipline

Research a value when it is current, externally verifiable, and material to the thesis.
Prefer primary sources such as official statistics, technical documentation, filings,
research papers, standards, and direct pricing pages. Cite the page supporting the specific
number and do not silently reuse an adjacent claim.

Comparable projects are evidence about possible ranges, not proof that this project will
perform similarly. State the differences that weaken the comparison.

## Metric quality test

A useful metric has:

- a defined unit, population, and time window;
- a reproducible collection method;
- a relationship to the intended outcome;
- a decision that changes when the metric changes;
- resistance to obvious gaming;
- acceptable collection cost and ethical implications.

If it fails these tests, revise it or classify it as exploratory rather than elevating it to a
target.
