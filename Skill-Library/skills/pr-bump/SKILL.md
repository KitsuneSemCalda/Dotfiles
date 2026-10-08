---
name: pr-bump
description: Consolidate eligible Dependabot dependency updates into one compatible, verified batch. Use for routine Dependabot bump queues when the user asks to review or land them together. Route suspicious sources, install hooks, or incompatible changes to a full PR audit; do not use for arbitrary PRs or releases.
---

# Dependabot Bump Batch

Batch compatible updates instead of merging Dependabot PRs one by one. The unit of review and CI is the combined lockfile and manifest state, not a collection of individually green badges. Record each source PR and what the batch does with it.

## Supply-chain floor before installation

Inspect the proposed manifests and lockfiles before running a package manager. For every direct and transitive artifact in the resulting lockfile, verify the exact package identity, version, public registry origin, and expected artifact checksum or registry-provided integrity against registry metadata. Inspect the changed dependency graph, maintainer or namespace changes where visible, and package names for plausible typosquatting. A known-vulnerability scanner is supplemental; it cannot establish that a newly published package is benign.

A matching checksum confirms the artifact bytes against the recorded source; it does not prove the package is benign. Review consequential code and behavior changes when the package's trust or impact warrants it.

Stop the fast path and route the affected update to `pr-audit` if a dependency resolves from Git, a path, a private or unexpected registry, has no trustworthy digest for the artifact, resembles a different expected package, or introduces an install/build hook. Do not execute newly introduced hooks to decide whether they are safe. Use a credential-free disposable environment for lockfile generation, dependency installation, and tests. Disable lifecycle scripts during resolution when the package manager supports it; if safe resolution is unavailable, stop the fast path. If isolation or public-registry verification is unavailable, report the batch as unverified rather than weakening the floor.

## Build one compatible bundle

Read the manifests, constraints, lockfile, Dependabot PR heads, and release notes for behavior or compatibility changes. Select the latest mutually compatible versions that satisfy the project's declared support range. Combine eligible updates into one proposed branch or grouped PR. Keep major upgrades, urgent security fixes, and incompatible ecosystems separate when they cannot satisfy the same compatibility and review gate; do not serialize ordinary compatible PR merges merely because Dependabot opened them separately.

Regenerate the lockfile with the project's package manager in the isolated environment, then verify every final artifact against the supply-chain floor before installing or testing. Run one CI pass for the combined head SHA, then fix forward and rerun affected checks if the bundle fails. Do not substitute several old PR checks for the combined result. Merge or push only when the user's request authorizes it and the combined review and CI gates pass.

## Report

List included PRs and selected versions, excluded PRs with individual reasons, registry and integrity evidence, the combined SHA and CI result, and any remaining risks. The batch is incomplete while a claimed included update has no verified disposition.

GitHub supports [grouped Dependabot updates](https://docs.github.com/en/code-security/tutorials/secure-your-dependencies/optimizing-pr-creation-version-updates); use existing grouping when it fits. Lockfile integrity and install-script behavior vary by ecosystem, so inspect the actual manager and format. For example, [npm records integrity and install scripts](https://docs.npmjs.com/files/package-lock.json/) and [Bundler supports lockfile checksums](https://bundler.io/blog/2024/12/19/bundler-v2-6.html).
