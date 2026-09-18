# Reporting and prioritization

## Verdict

Use one contextual verdict:

- **Healthy:** no material maintenance or operational risk was found in the assessed scope.
- **Needs attention:** meaningful improvements exist, but the project remains usable and the
  risks are bounded.
- **At risk:** one or more confirmed conditions threaten security, correctness, recovery,
  maintainability, or the ability to ship and support the project.

Do not calculate a numeric score. Scores imply precision and comparability that projects with
different purposes do not have.

## Severity

- **Critical:** credible immediate risk of compromise, destructive loss, or unusable releases.
- **High:** likely material failure or a serious obstacle to safe maintenance.
- **Medium:** bounded weakness that should enter a planned maintenance cycle.
- **Low:** worthwhile improvement with limited present impact.

Severity describes impact and urgency, not implementation effort. Report effort separately as
`small`, `medium`, or `large`, with uncertainty where appropriate.

## Report template

```markdown
# Project Health Report: <project>

Analyzed: <timestamp>
Baseline: <repository URL, branch, and commit>
Verdict: <Healthy | Needs attention | At risk>

## Executive summary
<Purpose-aware assessment and the two or three most important conclusions.>

## Priority findings

### [<severity>] <finding title>
- Evidence: <file:line, command result, workflow, issue/PR, setting, release, or URL>
- Impact: <what can plausibly go wrong and who is affected>
- Recommendation: <smallest useful improvement>
- Effort: <small | medium | large>
- Confidence: <high | medium | low, with reason when not high>

## Quick wins
<High-value, low-effort improvements not already covered above.>

## What is working well
<Positive practices supported by evidence.>

## Not assessed and limitations
<Unavailable permissions, tools, runtime validation, platforms, or private settings.>

## Recommended next cycle
<A short ordered set of changes suitable for one maintenance iteration.>
```

Omit empty sections except `Not assessed and limitations`. Keep generic observations out of
the findings. If a recommendation cannot name a project-specific benefit, do not include it.

## Prioritization rules

1. Confirmed data-loss, security, correctness, and recovery risks come first.
2. Broken user-facing promises outrank internal polish.
3. Recurring automation failures outrank speculative future concerns.
4. Prefer changes that eliminate several related symptoms at once.
5. Do not promote a low-impact item merely because it is easy.
6. Separate mandatory remediation from optional modernization.

When evidence conflicts, show the conflict and lower confidence instead of choosing the most
alarming interpretation.
