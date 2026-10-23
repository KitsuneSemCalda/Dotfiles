# Loop operation

The Skill is the user interface; `scripts/loop.py` owns parsing, state, cron edits, locking, and
execution. Invoke it from the Skill directory with Python 3. The project directory is captured at
creation. `LOOP_AGENT=codex` or `LOOP_AGENT=claude` selects the CLI; by default the first supported
CLI found on PATH is used. Unsupported CLIs fail clearly. No bypass-approval flags are used.

```text
python3 scripts/loop.py create -- '/loop 5m check the build until it finishes'
python3 scripts/loop.py create --now -- '/loop check CI'
python3 scripts/loop.py list
python3 scripts/loop.py status e4af821c
python3 scripts/loop.py run e4af821c
python3 scripts/loop.py pause e4af821c
python3 scripts/loop.py resume e4af821c
python3 scripts/loop.py edit e4af821c --interval 1h
python3 scripts/loop.py edit e4af821c --prompt 'check the PR every hour'
python3 scripts/loop.py cancel e4af821c
```

`create` installs the schedule first. The default first execution is the next scheduled tick;
`--now` also performs one immediate run and reports its outcome. A CLI invocation with `/loop`
alone resolves the default maintenance prompt at creation time. Store `original_prompt` and the
resolved prompt; later changes to `.loop.md` do not silently broaden an existing task's authority.

Fixed minute intervals dividing 60 and hour intervals dividing 24 use direct cron schedules.
Other periods and all dynamic tasks use a one-minute cron tick plus `next_run_at`. Every activation
checks the due time before starting an agent. Cron's minute resolution means a task may start up to
one minute after its due time. The user is told when subminute input was rounded. The optional
`LOOP_MIN_INTERVAL` and `LOOP_MAX_INTERVAL` bound dynamic scheduling (defaults 1m and 1h).

The runner gives the agent the original request, current project facts, a bounded persistent
memory field, and the previous result. It requires one JSON result with `result`, `summary`,
`memory`, and optional `next_interval` and `reason`. Results are `changed`, `no_change`,
`completed`, `failed`, `timeout`, `skipped`, or `blocked`. A `completed` result disables a wait-until
task. Invalid agent output is a failure and is logged. Dynamic no-change and external-failure
backoff is bounded; activity can request a shorter interval within the configured limits.

Only one run of a task is allowed at a time. A lock collision records `skipped` in the event log.
Each run has a timeout (default 30 minutes, configurable with `--timeout`). Optional `--jitter 30s`
adds one bounded start delay to scheduled runs; it is not the recurrence mechanism. Output and state stay
private in `${XDG_STATE_HOME:-~/.local/state}/skills/loop/<id>/`. Inspect `status` and `runs.log`
for failures. Cancellation removes only the task's marked cron block and retains the task record.

The manager requires a working `crontab` command; it never installs cron packages or enables a
service on the user's behalf. `run <id>` performs one immediate iteration without the due-time
check; use it only when the user intends a manual run.
