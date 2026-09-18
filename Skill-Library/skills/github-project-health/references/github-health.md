# GitHub health

Inspect only signals available through current authorization. Prefer GitHub APIs, an installed
connector, or `gh` over scraping. Public web access is a fallback. Record when a conclusion is
based only on repository files rather than confirmed GitHub settings.

## Repository identity

- Description, topics, homepage, visibility, default branch, archived status, and license
  reflect the actual project.
- The landing page makes purpose, maturity, support status, and basic usage clear.
- Links, badges, package coordinates, and release download instructions resolve correctly.

## Automation

- Inspect recent workflow runs, not only workflow YAML.
- Identify recurring failures, flaky jobs, skipped required checks, excessive permissions,
  stale action versions, and important branches or platforms without coverage.
- Check whether dependency automation exists and whether its pull requests are being handled.
- Treat missing CI as a finding only when automation would materially reduce project risk.

## Change and maintenance flow

- Review the age and disposition of open issues and pull requests in context.
- Look for blocked maintainers, unanswered actionable reports, duplicate queues, and automated
  update noise rather than penalizing raw counts.
- Compare active work with milestones, project boards, TODO files, and documented roadmaps
  when they exist.
- Inspect whether recent commits and merged pull requests follow the project's own stated
  process. Low activity is not unhealthy for a finished or stable project.

## Releases and distribution

- Tags, GitHub releases, changelog entries, package registries, and shipped artifacts agree.
- Release automation is reproducible and does not depend on mutable or undocumented inputs.
- Users can identify the latest supported release and compatibility requirements.
- Do not require releases for repositories that are deployed or consumed directly by design.

## Security and governance

When visible, assess:

- security policy and vulnerability-reporting route;
- dependency and code-scanning alerts;
- secret scanning and push protection;
- branch protection or rulesets;
- required reviews and status checks;
- workflow token permissions and environment protection;
- ownership, contribution guidance, code of conduct, and support expectations.

Do not claim private settings are disabled merely because they are not visible. Label them
`not assessed` unless an authenticated source confirms their state.

## Useful GitHub queries

Adapt these to the available interface rather than requiring `gh` specifically:

- repository metadata and default branch;
- workflow definitions and recent runs, including failed logs;
- open issues and pull requests sorted by age and recent activity;
- releases and tags;
- dependency update pull requests;
- visible vulnerability alerts, rulesets, and branch protection;
- community profile files and repository security settings.

Avoid collecting large volumes of content without a hypothesis. Start with summary signals,
then inspect individual runs, issues, or pull requests that explain an anomaly.
