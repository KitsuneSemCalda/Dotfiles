# Maintenance scenarios and recorded checks

Use these prompts to exercise the skill after material changes. Evaluate decisions and evidence
status, not exact wording. The 2026-10-03 run was a manual walkthrough by the updating agent with
local calculations and online documentary inspection; it was not a blind evaluation or a run
of each harness's model. These examples do not establish reliability across domains.

## Quantitative: fixed-work parallel speedup

### Prompt and advance criteria

“A job takes 100 seconds, with 80 seconds potentially parallelizable and 20 seconds serial.
Would moving to eight workers guarantee at least 4x speedup? Compare keeping the baseline,
parallelizing, and reducing serial work. Validate the reasoning before recommending use.”

Treat these durations as a synthetic fixture, not measured profiling data. Before calculation,
set success at end-to-end speedup ≥4x with identical work and correct output. Require agreement
within 1e-9 between the formula and an explicit balanced-task schedule, plus cases p=0, p=1,
and n=1. Budget: one domain reference, one local calculation pass, and a targeted revision if
necessary; real workload benchmarking is outside this fixture.

### Foundation and reconstruction

**Lawrence Livermore National Laboratory**, [Introduction to Parallel Computing Tutorial](https://hpc.llnl.gov/documentation/tutorials/introduction-parallel-computing-tutorial),
sections “Amdahl's Law,” “Scalability,” and “Strong and Weak Scaling.” Institutional tutorial,
publication/update date and numbered version not identified; accessed 2026-10-03. Relevant
passages were read, not the entire tutorial. It is a primary institutional teaching resource,
not the original Amdahl paper or an empirical benchmark of this job.

For fixed total work, fraction p of baseline runtime parallelizable, n workers, and no overhead,
T(n)=T(1)[(1−p)+p/n]. Thus speedup is dimensionless, n=1 recovers baseline, p=0 yields no gain,
and p=1 gives ideal n-fold gain. Real overhead and imbalance violate ideal assumptions.

Here p=0.8 and n=8. The equal-load assumption is assumed; formula consistency is locally
checked; the application's runtime fractions remain unverified. A measured ≥4x result with
these actual premises would challenge the fixed-work decomposition, not magically confirm it.

### Locally executed results, 2026-10-03

Python 3.14.7, standard library only. Explicit schedule: 800 synthetic tasks of 0.1 seconds,
round-robin over eight workers, plus 20 serial seconds. Formula and schedule agreed within
1e-9; all three boundary checks passed. These are arithmetic checks, not wall-clock timings.

| Candidate | Assumed duration (s) | Calculated speedup | Meets 4x? |
| --- | --- | --- | --- |
| Baseline | 100 | 1.000000 | No |
| Ideal parallel | 30 | 3.333333 | No |
| Parallel plus illustrative 8 s overhead | 38 | 2.631579 | No |
| Serial work reduced to 10 s, one worker | 90 | 1.111111 | No |
| Serial reduction plus eight workers and 8 s overhead | 28 | 3.571429 | No |

The ideal fraction required for 4x on eight workers is at least 0.857143. Sensitivity with
8 s overhead and p=0.7/0.8/0.9 gave 46.75/38/29.25 s and 2.139037/2.631579/3.418803x.
Same output/work is assumed for each hypothetical alternative; no implementation was benchmarked.

Reproduce the decisive consistency check locally:

```python
from math import isclose

baseline, serial, p, workers = 100, 20, 0.8, 8
ideal = baseline * (1 - p + p / workers)
loads = [0.0] * workers
for i in range(800):
    loads[i % workers] += 0.1
assert isclose(ideal, serial + max(loads), abs_tol=1e-9)
for fraction, n, expected in [(0, 8, 1), (1, 8, 8), (0.8, 1, 1)]:
    assert isclose(1 / (1 - fraction + fraction / n), expected)
for duration in [100, ideal, ideal + 8, 90, 10 + 80 / workers + 8]:
    print(duration, baseline / duration)
print((1 - 1 / 4) / (1 - 1 / workers))
for fraction in [0.7, 0.8, 0.9]:
    duration = baseline * (1 - fraction + fraction / workers) + 8
    print(fraction, duration, baseline / duration)
```

**Disposition:** reject the guarantee under the fixture; none of the compared options meets
the target. A representative benchmark with equal outputs, measured overhead, repeated trials,
and an advance ≥4x criterion remains **proposed, not executed**. No third-party benchmark was used.

**Revision supported by this exercise:** explicitly check that parameters measure the modeled
quantity (runtime fraction, not code-line fraction) and include overhead before practical transfer.
Repeat the local schedule and boundary checks after that clarification; numerical results are
unchanged. Stop because the fixture decides the guarantee; practical suitability needs profiling.

## Interpretive: equality language and historical implementation

### Prompt and criteria

“Can I say in an essay that the 1776 Declaration of Independence abolished slavery because
it states that all men are created equal? Compare that reading with political justification
and with the suggestion that equality language had no possible normative significance.”

Criteria: whole-document fit, chronology, distinction between stated principle and implemented
institution, corroboration, and unsupported assumptions. Do not turn a moral preference into
historical evidence. Budget: three archival documents and relevant AHA methodological sections;
stop once the narrow essay claim is decided, leaving authorial intent and later reception open.
This is a known-case manual regression exercise, not a preregistered historical discovery.

### Inspected primary documents

All accessed 2026-10-03; publisher/custodian is the U.S. National Archives. These are different
historical documents in one archive, not independent replications. No original manuscripts were
physically examined. Archival commentary was kept separate from the transcribed documents.

- **Continental Congress**, Declaration (1776-07-04), [Stone Engraving transcription](https://www.archives.gov/founding-docs/declaration-transcript).
  Read the preamble, grievances, and concluding declaration; page reviewed 2026-02-25.
  The equality principle and conclusion about independent states support political justification;
  the inspected text does not enact abolition. Normative language does not itself demonstrate
  implementation. The text alone cannot settle every signer's intentions or subsequent reception.
- **Constitutional Convention**, Constitution (1787-09-17), [original text transcription with amendment annotations](https://www.archives.gov/founding-docs/constitution-transcript).
  Read Article I §2 and Article IV §2; page reviewed 2026-09-08. The original text distinguishes
  free and other persons for representation and addresses return of persons held to service.
  It supplies intervening institutional evidence against the inference of universal implemented
  equality. It does not alone reconstruct every state practice in 1776.
- **U.S. Congress**, Amendment XIII, [joint resolution and transcription](https://www.archives.gov/milestone-documents/13th-amendment).
  Read §§1–2 and document dating: passed 1865-01-31, ratified 1865-12-06; page reviewed 2022-05-10.
  It explicitly prohibits slavery and involuntary servitude with a criminal-punishment exception.
  Its later date alone would not prove the full intervening history.

### Documentary analysis and revision

Foundations: separate political justification, normative principle, and institutional change.
The AHA reference in [sources.md](sources.md) provides source-criticism practices; there is no
formal history BoK asserted here. Wording/dates are supported observations; political function is
a contextual interpretation; moral equality is a normative proposition, not a measured preference.

Compare all three readings by the same criteria. “Abolition in 1776 follows from the wording”
adds an unsupported bridge from principle to implementation. Political justification fits the
document's conclusion and leaves that bridge open. “No possible normative significance” also
overreaches: lack of demonstrated implementation does not prove absence of normative meaning.
Determining effects on later movements would need reception evidence outside this budget.

The initial comparison with Amendment XIII alone left a chronological gap. Review the affected
premise and inspect the original constitutional clauses as intervening evidence. Reassess the
readings using the same criteria; the narrow essay claim remains unsupported. Add guidance that
later documents alone cannot establish earlier implementation or continuous practice.

**Disposition:** use the equality statement as a declared principle in political justification;
do not cite it as proof of abolition in 1776. Keep intent, reception, and state-level implementation
outside the established scope. No equations, numerical confidence, experiments, or pilot were
invented. This was **documentary analysis performed**, with no local empirical test or third-party
experiment; further archival investigation is **proposed, not executed**.

## Structural and harness checks

Run the skill-creator validator, resolve every relative reference, and inspect frontmatter/name
and the installer discovery/copy behavior. Exercise the existing Perl installer in a temporary
HOME with Claude, Codex, and OpenCode directories, then compare copied file bytes against the
source. Do not edit installers or invent harness-specific metadata for this portable skill.

An installer copy test establishes packaging compatibility, not how a harness model will follow
the instructions. PowerShell/Windows execution needs a suitable environment; do not report it
as executed when unavailable.

Recorded on 2026-10-03: `quick_validate.py` returned “Skill is valid!”; all relative Markdown
references resolved; final newlines and trailing whitespace checks passed, including the
untracked files. The existing Perl installer discovered the skill and copied its five files
byte-for-byte to all three temporary harness directories. The published Python example was
executed after the two foundation clarifications and reproduced the results above. `git diff
--check` passed for tracked changes. PowerShell was not available; no Windows execution or
independent harness-model evaluation was performed.
