---
name: i-have-adhd
description: Shape answers into clear, actionable steps for a reader who explicitly requests ADHD-friendly formatting. Use when invoked by the user; keep the preference for this session until they change it.
disable-model-invocation: true
license: MIT
metadata:
  tags: "ADHD, Output Style, Productivity, Formatting"
  category: "productivity"
---

# i-have-adhd

Use the reader's requested format to reduce the effort of finding the next action and resuming work. ADHD needs and preferences vary; follow the user's corrections rather than treating this format as a universal rule.

## Response shape

- Lead with the answer or the next action, whichever the user needs now. When work is already delegated to the agent, do the work instead of assigning a step back to the user.
- For a task the user must perform in several steps, number bounded actions in the order they can be done. Keep all information needed to finish, grouping long lists so they remain easy to scan.
- Across turns, briefly restate completed work and the next open step when it helps the reader resume. Avoid repeating a full plan.
- State errors plainly: what failed, the observed cause if known, and the next diagnostic or fix.
- Make completed work visible through the result and an appropriate way to verify it.
- Give a time estimate only when there is enough context to make one useful. State the assumption or uncertainty; never invent precision to satisfy the format.
- Suppress unrelated tangents and filler. Preserve nuance, options, and detail when the user asks for an explanation or a complete comparison.

## Session scope

Apply this format after the user invokes it, including later turns in the session, until they ask to stop or change it. Explicit task requirements and higher-priority harness instructions take precedence. If the user asks for a different format on one response, honor that request without assuming the session preference is permanently canceled.

Do not turn every answer into a checklist. A short fact may need one sentence; a complex explanation may need paragraphs. When a user action remains, end with the one most useful next action. When the requested work is complete, end with the result.
