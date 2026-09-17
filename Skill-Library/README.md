# Skill-Library

Personal library of AI coding-agent skills, versioned with the rest of the
dotfiles and installed globally — not tied to any single project. Each
skill teaches an agent CLI something non-obvious about how to work on this
machine or in this workflow.

## Format

Each skill is a directory under [`skills/`](skills/) named after the skill,
containing at least a `SKILL.md`:

```
skills/
  <skill-slug>/
    SKILL.md        # YAML frontmatter (name, description) + instructions
    ...             # optional supporting scripts/references
```

`SKILL.md` uses the same convention already shared by Claude Code and
Codex: YAML frontmatter with `name` and `description`, followed by a
Markdown body with the actual instructions. A skill written this way needs
no per-agent adaptation to work with either CLI; `install.pl` just copies
the directory as-is into each agent's skills folder.

## Installing

```sh
perl Skill-Library/install.pl            # install every skill into every agent detected
perl Skill-Library/install.pl --agent codex
perl Skill-Library/install.pl --list     # show skills in the library and agents detected
perl Skill-Library/install.pl --dry-run  # preview without copying
```

An agent is only targeted if it's actually installed on the machine
(detected by the presence of its config directory, e.g. `~/.claude` or
`~/.codex`). Installing copies files — it does not symlink — so re-run
`install.pl` after editing a skill here to push the update out, and edit
skills here rather than in an agent's own skills directory, since that
copy isn't versioned.

## Adding a skill

Create `skills/<slug>/SKILL.md` with frontmatter and instructions, then run
`install.pl`.

### Importing a skill from upstream

Skills imported from other open-source collections keep a `SOURCE.md` inside
their directory recording the upstream repository, license, and commit they
were copied from. If an upstream skill references shared files (checklists,
references) that live outside its own directory, those files are embedded into
the skill's own `references/` directory and the paths in `SKILL.md` rewritten
to match, so every skill in this library is self-contained.

This library previously had a batch of skills imported wholesale from
upstream collections without curation; most were never relevant to this
machine's actual work and just added noise to every agent's skill listing.
They were removed. Prefer adding skills one at a time, for something you
actually hit repeatedly, over importing a whole collection again.
