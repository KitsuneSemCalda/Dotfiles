---
name: release
description: Prepare and publish a requested project release with changelog-based version classification, exact-SHA CI gates, and an annotated immutable version tag. Use only when the user explicitly asks to cut or publish a release. For OmaStore-specific build packaging, use omastore-release.
---

# Release

Never cut a release merely because fixes are merged or a version looks due. Start only from an explicit release request. Record the intended repository, branch, prior version, proposed version, target commit, and publication channel.

## Classify before numbering

Read the unreleased changelog and verify its categories against the actual changes and public contract. For a project using SemVer, the highest-impact change determines the minimum bump: compatible fix to patch, backward-compatible addition to minor, incompatible public behavior to major. This library applies the major rule even before 1.0; a breaking change cannot ship as a patch. If the requested number conflicts with the verified classification, present the exact conflicting changes and ask the user to choose a matching version or defer the release before editing version files, tagging, or publishing. Do not silently bump or relabel. If the project uses another version scheme or a stated pre-1.0 policy, identify that policy and resolve conflicts explicitly.

Update the changelog and version metadata together. Validate the release notes, artifacts, and build path. Commit those changes so the intended tag target is an exact SHA. Confirm every required pre-tag check is green and not pending or skipped for that SHA; a previous SHA's result does not count.

## Tag and publish

Inspect the release workflow before pushing a tag. If a tag push would automatically publish before the tag's checks pass, prepare a draft or repair the gate first. Check that the proposed tag does not exist locally or remotely. Create an annotated version tag on the verified SHA and never move or rewrite a published tag. Push the tag only after the pre-tag gate passes and the request authorizes publication.

If tag-triggered checks exist, verify they pass for the same commit SHA before publishing the release or promoting a draft. Confirm the tag still resolves to the verified commit, release assets match the intended build, and required checks are green. If any required check is pending, skipped, or failed, stop publication and report the exact gate. Do not treat a draft as published.

## Report

State version and classification, changelog entry, tag and commit SHA, pre-tag and tag CI results, artifact or release URL if published, and any pending gate. Do not claim a release is complete until the publication state is verified.

[SemVer](https://semver.org/) defines the major/minor/patch contract for projects that adopt it. GitHub documents [exact-commit required checks](https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/troubleshooting-required-status-checks) and [immutable releases](https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases).
