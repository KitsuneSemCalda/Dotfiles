---
name: loop
description: Schedule and manage persistent /loop tasks that run one bounded agent iteration at a time. Use when the user invokes /loop or $loop, or asks to list, change, pause, resume, run, or cancel an existing loop. Do not use for programming loops or one-off tasks.
---

# /loop

Accept `/loop [interval] <prompt>`, natural equivalents, and `/loop` alone. Keep the public response
compact: task ID, schedule, prompt, whether the first run happened, and next run. Do not ask the user
to configure cron, locks, state, or a terminal session.

Use [scripts/loop.py](scripts/loop.py) as the task manager and one-iteration runner. Read
[references/operation.md](references/operation.md) for parsing, CLI usage, runtime limits, and
recovery. The manager stores state under XDG state and installs only its own marked crontab blocks.
Never put the prompt in a shell command. Never implement recurrence with `while true`, `sleep`,
recursive agent calls, tmux, screen, or a resident process.

For a new request, pass the user's text to `loop.py create -- <text>`. An initial `5m`, `2h`, etc.
selects a fixed interval; a clear trailing “every 20m” or “a cada 20 minutos” also works. A prompt
without an interval uses a dynamic 1m–1h cadence. An empty `/loop` uses `.loop.md` in the project,
then the user's XDG `skills/loop.md`, then conservative built-in maintenance instructions. An
explicit prompt ignores these files. `30s` is rounded to 1m only with a clear notice.

If the prompt starts with `/skill-name`, verify the installed Skill exists and permits automatic
invocation. Reject invalid or explicit-only Skills; never treat the payload as shell. The task's
agent performs the real work. This Skill manages when to invoke it, what minimal prior state to
pass, and when to stop.

Each cron activation starts at most one bounded iteration and exits. Treat `no_change` as success.
Stop a wait-until task when its condition is met; keep an indefinite monitoring task scheduled.
One task's lock prevents overlapping runs. A loop inherits only the authorization in the original
request and the agent's normal policies; automation never grants extra permission to push, merge,
deploy, delete, purchase, publish, alter infrastructure, or send messages.

For management requests use `loop.py list|status|run|pause|resume|edit|cancel`. Resolve names or
IDs unambiguously before mutation. Edit an existing task rather than making a duplicate. Never
touch unrelated crontab entries. If cron or a supported noninteractive agent CLI is missing, report
the precise missing capability and do not claim a loop was scheduled.
