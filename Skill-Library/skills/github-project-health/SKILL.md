---
name: github-project-health
description: Audit a local project and its GitHub repository for technical health, maintainability, security posture, automation, documentation, and project hygiene. Use when asked to assess a project's health, find evidence-backed improvements, review repository readiness, or prioritize maintenance work. The audit is read-only unless the user separately asks to implement selected recommendations.
---

# GitHub Project Health

Assess the project in context, not against a universal maturity checklist. A small stable
personal tool, an active library, and a production service have different needs. Infer the
project's purpose and lifecycle from its code, documentation, history, and GitHub activity;
state any assumption that materially affects the verdict.

## Operating boundary

The audit is read-only. Inspect local files, Git history, and public or authorized GitHub
metadata, but do not edit files, change repository settings, open or close issues, modify
workflows, update dependencies, push commits, or create pull requests. Recommendations do
not authorize their implementation.

Do not request broader GitHub permissions merely to complete the audit. Report unavailable
signals as limitations instead of treating them as failures. Never expose secrets found
during inspection; identify their location and type without reproducing the value.

## Audit workflow

1. Establish scope and baseline.
   - Locate the repository root and read its guidance and primary documentation.
   - Identify the default branch, remotes, working-tree state, languages, build system,
     package managers, deployment model, and intended audience.
   - Determine whether the GitHub repository is accessible through an installed connector,
     `gh`, or public web access. Prefer structured GitHub data when available.
   - Record the analyzed branch, commit, repository URL, and observation time.

2. Inspect the local project.
   - Read [references/codebase-health.md](references/codebase-health.md).
   - Select only checks relevant to the detected project. Do not penalize an intentionally
     absent subsystem, such as releases for a private dotfiles repository.
   - Run safe existing validation commands when they are discoverable and proportionate.
     Do not install dependencies or execute unknown project code merely for completeness.

3. Inspect GitHub health.
   - Read [references/github-health.md](references/github-health.md).
   - Review repository metadata, recent automation results, maintenance queues, releases,
     and security/community signals that are visible with current access.
   - Distinguish confirmed settings from indirect evidence. For example, a passing workflow
     does not prove branch protection is enabled.

4. Correlate signals.
   - Look for contradictions across code, documentation, automation, releases, and issues.
   - Separate symptoms from underlying causes and consolidate duplicates into one finding.
   - Preserve positive evidence as well as problems so the report reflects actual health.

5. Prioritize and report.
   - Read [references/reporting.md](references/reporting.md).
   - Rank work by likely impact, evidence strength, urgency, and implementation effort.
   - Prefer a small number of actionable findings over an exhaustive list of generic advice.

## Evidence standard

Every reported problem must include concrete evidence: a file and line, command result,
workflow run, GitHub setting, issue or pull request, release, dependency record, or URL.
Clearly label inferences and confidence. Do not report the absence of evidence as evidence
of absence.

Before reporting a finding:

- confirm it is relevant to this project's purpose and lifecycle;
- check whether the project already addresses it elsewhere;
- explain the plausible impact rather than citing a best practice alone;
- propose the smallest useful improvement;
- avoid claiming a vulnerability without a credible attack path or authoritative advisory.

If live GitHub data cannot be accessed, complete the local portion and mark GitHub-dependent
conclusions as not assessed. Never silently substitute stale model knowledge for current
repository state.

## Completion

Return the health report in the structure defined by `references/reporting.md`. End with a
short recommended next cycle, but do not begin implementation. If no material problems are
found, say so and list the checks and limitations supporting that conclusion.
