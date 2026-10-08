# Skill evaluation cases

Use these prompts after changing a skill's description or instructions. For each case, check whether the intended skill is selected, whether an unrelated skill stays out, and whether the answer meets the observable criterion. A correct routing decision alone is not a successful evaluation. Record the model, date, and any failure before changing a skill to address it. These are manual probes, not claims that the skills have passed them.

| Prompt | Intended skill | Observable criterion |
| --- | --- | --- |
| “Review the complexity of the import path for ten million rows. Identify the input variables.” | algorithmic-project-review | Derives costs from the code and separates measured from inferred bottlenecks. |
| “This generated architecture review sounds impressive. Check whether its findings follow from the repo.” | anti-ai-mediocrity | Challenges unsupported claims at exact locations and keeps supported findings. |
| “How would different readers react to these three blog posts?” | blog-reader-panel | Grounds distinct reader reactions in passages and states the sample boundary. |
| “Audit this repository and its GitHub automation for maintenance problems.” | github-project-health | Checks available local and GitHub evidence without treating unavailable settings as defects. |
| “Remove the AI writing tells from this essay while preserving my facts and voice.” | humanizer | Removes genuine tells while preserving factual claims and deliberate style. |
| “/i-have-adhd: explain how to migrate this database safely.” | i-have-adhd | Gives complete, scannable guidance without inventing a time estimate or handing delegated work back. |
| “Teach me why this index fixes my slow query; give me a different example to practice.” | learn-from-work | Explains the transfer principle with an example from another domain. |
| “This change adds a new cache service. Find the simplest complete implementation.” | ponytail | Checks the need for the service, preserves requested behavior, and verifies material risk. |
| “Is this sentence correct English? Keep my wording unless it is wrong.” | preserve-my-english | Makes only necessary local edits and labels optional preferences. |
| “Refactor this module so adding a payment provider stops changing the pricing rules.” | principled-refactoring | Traces the actual dependency, preserves behavior, and adds only the boundary needed for a real variation. |
| “Rewrite this project's README for someone deciding whether to install it.” | product-readme | Gives a verified route to first useful result and uses real media when it helps. |
| “What scale and resources would this research platform need to serve a million users?” | quantify-ambition | Distinguishes facts, estimates, targets, and assumptions in a changeable model. |
| “Investigate whether this published performance claim holds under our workload.” | skeptical-research | Checks primary evidence and alternatives; does not present proposed tests as executed. |
| “Can outsiders install, understand, and keep using this prototype?” | software-product-review | Traces a user journey and gives a conditional product readiness judgment. |
| “Map this service's architecture and failure paths, then prioritize engineering fixes.” | software-project-analysis | Connects technical findings to observed paths and avoids a general product viability verdict. |

## Negative routing and conflict probes

- “Fix the failing parser test.” Ordinary implementation should proceed without automatically loading `ponytail`, `learn-from-work`, or a project audit.
- “Add a new endpoint.” Do not invoke `principled-refactoring` solely because the work touches architecture. “Assess this repo's design” remains a read-only project review unless the user requests structural edits.
- “Apply all ten JPL rules to this small JavaScript utility.” `principled-refactoring` should explain the original safety-critical C scope, apply only useful transferable checks, and avoid arbitrary C-specific constraints.
- “Fix typos in this English paragraph.” Use `preserve-my-english` if authorship-preserving correction is requested; do not use `humanizer` unless AI writing patterns are the task.
- “Why is this loop quadratic?” Use `algorithmic-project-review` for a project or path review; a one-line conceptual question may need no skill.
- “Is this app worth releasing to new users?” Use `software-product-review`. “What can fail under concurrent writes?” uses `software-project-analysis` or a narrower technical review.
- “Audit release workflow health.” Use `github-project-health`; do not turn it into a broad architecture or market assessment.
- “Estimate how long this one feature will take.” Do not invoke `quantify-ambition`.
- “Summarize this supplied article.” Do not invoke `skeptical-research` unless the user requests verification or a defensible investigation.
- A user who activates `i-have-adhd` and then requests a detailed comparison should still receive all relevant options. A user who asks to stop the format should get the ordinary response shape on the next turn.
- A user who requests a full implementation while `ponytail` is active should receive that implementation. Simplicity must not become a reason to omit an explicit requirement.
