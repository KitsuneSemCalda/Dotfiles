# Quantification dimensions

Choose dimensions that change a decision. Omit categories that do not apply and add
domain-specific ones when necessary.

## Impact and beneficiaries

- Who experiences the intended change, and how many could realistically be reached?
- What changes for each beneficiary: time, cost, access, capability, quality, safety,
  knowledge, behavior, or another outcome?
- How deep, durable, and attributable must that change be?
- What is the aggregate effect at each scenario's scale?

Distinguish people exposed, people who try, active participants, retained participants, and
people who receive the intended benefit.

## Adoption and distribution

- Addressable population and reachable initial segment.
- Acquisition or discovery channels and their capacity.
- Activation, frequency, retention, referral, and concentration.
- Time or friction required to adopt, migrate, learn, or trust the project.
- Network effects, coordination thresholds, and cold-start constraints.

Do not treat downloads, page views, registrations, or stars as impact unless the causal link
is demonstrated.

## Technical scale

- Concurrent and total users, agents, devices, organizations, or sites.
- Requests, events, transactions, jobs, tokens, files, or records per unit of time.
- Data retained, transferred, replicated, and deleted.
- Latency percentiles, availability, recovery objectives, accuracy, and error budgets.
- Peak-to-average ratio, geographic scope, offline behavior, and growth headroom.
- Safety, privacy, abuse, and human-review capacity.

Use units throughout. Convert product assumptions into technical load explicitly rather than
jumping directly to an architecture.

## Resources and economics

- People by capability and stage, including operations and support.
- Calendar time, sequencing constraints, and external dependencies.
- One-time and recurring money, compute, storage, bandwidth, facilities, or materials.
- Unit cost at relevant scales and the variables that dominate it.
- Funding, revenue, sponsorship, volunteer effort, institutional support, or another
  sustainability mechanism appropriate to the project.

Include the cost of maintenance, governance, compliance, support, and failure recovery where
material. Do not assume all projects must maximize revenue.

For a project intended to generate income, continue with
[commercial-viability.md](commercial-viability.md) rather than treating revenue as one more
isolated metric.

## Quality and trust

- Minimum useful quality and the quality required at the full vision.
- Reliability, correctness, safety, accessibility, privacy, explainability, or fairness.
- User trust, institutional legitimacy, contributor health, and governance capacity.
- Tradeoffs that are unacceptable even if they improve reach, speed, or cost.

## Time and stages

- Time to first credible proof, first independent use, sustained use, and intended scale.
- Learning rate: how often critical hypotheses can be tested.
- External windows, deadlines, dependencies, and irreversible commitments.
- Useful intermediate states that create value before the complete vision exists.

## Ambition-specific dimensions

Some projects are ambitious for reasons not captured above. Examples include scientific
uncertainty, cultural change, geographic coverage, regulatory approval, ecosystem formation,
physical manufacturing, or long-duration stewardship. Define units and observable proxies
specific to that source of ambition rather than forcing it into a generic product metric.
