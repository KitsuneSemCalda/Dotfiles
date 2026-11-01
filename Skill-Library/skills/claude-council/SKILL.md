---
name: claude-council
description: Consult several AI providers through claude-council and synthesize their independent answers. Use when the user requests a council, multiple model opinions, or a second opinion from a named provider.
---

# Claude Council

Use the bundled upstream scripts from any harness. Resolve paths below relative to this skill's directory, and run from the user's project directory so explicit file paths and caches belong to that project. Bash and jq are required; API providers also need curl. Windows requires Git Bash.

Discover the default roster without sending a prompt:

```sh
bash <skill-directory>/upstream/scripts/query-council.sh --list-default-models
```

Run a consultation:

```sh
bash <skill-directory>/upstream/scripts/run-council.sh --no-pane --no-auto-context -- "The question and relevant evidence"
```

The script prints a Markdown file path. Read that file, report provider failures, and synthesize the answers in the user's language: agreement, material disagreements, recommendation, and the premise that could change it. Agreement between models does not verify a fact. The driving harness writes the synthesis; the shell scripts gather and format the provider answers.

Honor COUNCIL_PROVIDERS from the launching environment. Use --providers=codex,grok-cli (or another supported list) when the user specifies seats. Without a pinned list, upstream discovers available CLI/API providers; discovery does not prove authentication. Keep the same roster across harnesses when comparing results. Models still vary in their answers.

The question reaches every selected provider and its vendor. Include only relevant context; --file=path deliberately attaches a file. The default command above disables automatic file collection. Prompts and answers are saved in plaintext in .claude/council-cache/ under the working directory, even outside Claude Code; upstream makes that directory self-ignoring for Git.

For roles, debate, images, async jobs, model overrides, or provider details, read [the upstream reference](upstream/docs/REFERENCE.md) and [synthesis guidance](upstream/prompts/synthesis.md). The local/agents modes, slash-command orchestration, hooks, and mods described upstream require Claude-specific integration and are not part of this portable installation. Do not use the council recursively from one of its own seats.
