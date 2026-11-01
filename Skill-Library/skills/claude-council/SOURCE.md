# Source

- Repository: https://github.com/hex/claude-council
- Commit: b264cdec39b5df208954b4709c5fd2e70e947ca2
- License: MIT; retained in upstream/LICENSE.
- Imported: 2026-11-01.

upstream/ contains the unmodified runtime scripts, configuration, prompts,
schemas, README and reference from that commit. Claude plugin registration,
commands, agents, hooks, mods, development scripts and upstream skills are
excluded. SKILL.md is the local portable adapter; it calls the same upstream
runtime from every harness. No Claude plugin or hooks are registered.

To update, replace the vendored subset from a reviewed commit, verify each
file against Git's blob SHA in upstream-files.json, update this provenance
and the manifest, then rerun the Skill-Library installer.
