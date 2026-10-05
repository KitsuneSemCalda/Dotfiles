# Foundations and discriminating tests

## Select the foundation

Map the decisive claim to a discipline, then locate the relevant BoK, handbook, standard,
critical edition, or recognized scholarly reference. Read its applicable sections rather than
collecting titles. Record edition, chapters, definitions adopted, and why they apply. Formal BoKs
are maps of a field, not proofs of the claim or mandatory compliance checklists. Where definitions
vary across traditions, declare the convention and inspect whether the conclusion survives another.

Examples: a software claim might need applicable SWEBOK knowledge areas plus a language
specification; a statistical model might need the NIST/SEMATECH handbook's modeling and design
sections. Historical work may need a critical edition, archival provenance, and recognized
historiography rather than a formal BoK. Do not cite any of these as read unless actually inspected.

For each pivotal claim, keep a small dependency record:

| Element | What to record |
| --- | --- |
| Claim | Scope, quantifiers, and what decision it affects |
| Foundations | Definitions, premises, mechanism, applicable chapters |
| Premise status | Verified with evidence; assumed for the model; inferred with reasoning |
| Validity conditions | Population, period, workload, jurisdiction, edition, or other boundary |
| Challenge | Credible contrary evidence, counterexample, or competing explanation |
| Discriminating check | Outcome that changes confidence or distinguishes alternatives |

“Verified” means supported within the specified scope, not eternally certain. An observation can
be verified while the causal interpretation remains inferred. A preference or ethical commitment
is a stated decision input, not an empirical premise to be proved by popularity.

## Assess the evidence behind premises

For decision-critical sources, inspect relevance to the actual population, intervention,
environment, workload, or period; sample selection, controls, measurement quality, uncertainty,
and reproducibility; correlation versus causal identification and possible confounding; effect
size and practical importance rather than statistical significance alone; incentives, conflicts,
selective reporting, and independent corroboration. Use domain-appropriate equivalents for
nonexperimental evidence. A primary source can be biased or unsuitable; its role and method matter
more than its label. Track corrections, retractions, and version changes when consequential.

## Quantitative reconstruction

Define variables and units before equations. Derive the needed relation from explicit premises,
then identify which parameter values were measured, published, inferred, or chosen for illustration.
Check dimensional consistency, limiting cases, plausible magnitude, and sensitivity to uncertain
inputs. Use a calculator for simple arithmetic and Python, preferably its standard library, when
the calculation needs repetition, precision, uncertainty propagation, simulation, or a parameter
sweep. Keep the code, input values and their provenance, units, environment, and decisive outputs
reproducible. Do not run code copied from a retrieved page blindly.

Test the relationship independently when feasible: compare a closed form with a direct construction,
check a known case, or seek an adversarial input. Recomputing the same mistaken formula twice is
weak evidence. Rounding, uncertainty, measurement resolution, and model discrepancy can dominate
floating-point precision. Numerical agreement validates the computation only within its premises.
For a stochastic check, record the random seed and show how results vary across plausible inputs;
do not promote a simulated outcome to an observed one.

Check that a parameter measures the modeled quantity: a parallel fraction is a fraction of
baseline runtime for the fixed workload, not a fraction of source-code lines. Include overhead
and resource limits before transferring an ideal bound to a practical prediction.

For data-driven models, inspect assumptions and residual structure where appropriate; a favorable
summary statistic alone does not establish adequacy. Distinguish fitting data from predicting new
observations. Avoid choosing a hypothesis or tuning parameters on the same evidence used to claim
confirmation without disclosing that dependence.

## Choose a check by the uncertainty it resolves

| Uncertainty | Possible check | What it cannot establish alone |
| --- | --- | --- |
| Logical entailment | Proof, explicit argument, counterexample | Truth of empirical premises |
| Implementation behavior | Minimal reproduction, invariant, boundary case | Suitability for every environment |
| Quantitative consequence | Independent calculation, sensitivity, simulation | Real-world parameter accuracy |
| Comparative performance | Controlled benchmark with equivalent tasks | Transfer to unmeasured workloads |
| Empirical mechanism | Controls, discriminating measurements, replication | Universal causality from one study |
| Historical or textual interpretation | Provenance, chronology, full passages, rival reading | Intent or reception without relevant records |
| Practical suitability | Representative pilot with acceptance criteria | Broad deployment beyond observed conditions |

Before results, write the hypotheses, comparator, metric or qualitative criterion, expected
outcomes, and how each changes the conclusion. Choose controls for relevant confounders. For
benchmarks, preserve output correctness, input distribution, hardware, versions, resource budget,
warm-up, repetitions, and uncertainty as applicable. For experiments, justify sampling, controls,
and measurement. Proportionate checks need not become elaborate study designs.

If a failed check exposes a premise, revise the premise before retesting. Record what changed and
why, including criteria changed after results. Do not erase the failed prediction or label a
post-hoc explanation as independently confirmed.

## Interpretive investigations

Separate at least three possible questions: what a document says, what someone intended or did,
and whether a position is justified. They require different evidence. A text can establish its
wording without establishing implementation, private intent, or moral truth.

- **History:** examine authorship, authenticity, dating, provenance, intended audience, genre,
  contemporaneous context, and corroboration. Distinguish an original document from a later
  transcription and scholarly interpretation. An archive's commentary and its hosted document
  are different evidence roles, not automatically independent corroboration. Silence is evidence
  only when the record would reasonably be expected to contain the missing information.
  A later document does not by itself establish what happened earlier; seek intervening or
  contemporaneous corroboration before making a continuity claim.
- **Narrative:** inspect full passages, narrator reliability, chronology, genre, and competing
  readings. Distinguish textual support from authorial intent and reader response. Aesthetic
  preference can guide a choice without becoming an objective quality claim.
- **Philosophy:** reconstruct premises and inferential steps charitably, check consistency,
  ambiguity, counterexamples, and objections. Separate validity from premise acceptance and
  normative commitments from empirical claims. A counterexample may challenge an argument
  without experimentally resolving a value disagreement.

Use qualitative criteria such as contextual fit, coverage of relevant passages, coherence,
explanatory scope, and unsupported assumptions. Decide these before selecting a favored reading;
compare rivals by the same criteria. Predictions can be expected documentary traces, passages
inconsistent with a reading, or consequences of an argument. Not every interpretation has an
experimental refutation condition. Report underdetermination when plausible readings remain.

“Application” can mean using a claim in an essay, adopting an interpretation, or making a practical
choice. Do not invent a deployment or pilot when the task asks only for understanding.
