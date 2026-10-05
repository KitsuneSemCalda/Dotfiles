---
name: product-readme
description: Create or revise a software product README for people deciding whether and how to use it, including useful screenshots, demos, and SVG marks. Use for product-facing repository homepages, including rewrites of developer-centric READMEs. Do not use for API references, internal architecture docs, or contributor guides alone.
---

# Product README

Write the repository's front page from the perspective of a person encountering the product for the first time. The OmaStore README is a useful example of the progression: identify the product and its audience, show what using it looks like, explain what it can do, give a working path to start, then offer deeper operational and development detail. Adapt that progression to the actual product instead of copying its sections, claims, or visual style.

## Ground the story

- Inspect the product, current README, branding, installation and usage paths, release artifacts, existing media, and relevant docs or code before drafting. Identify the intended users and the main task they want to complete. If evidence is thin, say so and keep claims narrow.
- Check commands, supported platforms, requirements, links, and important behavior against the repository. Prefer a short path that works for a new user. Do not invent downloads, features, guarantees, screenshots, or maturity claims.
- Distinguish what is available now from planned work. Place material limitations close to the promise or instruction they qualify, in language a user can act on.

## Write for a first visit

- In the opening, answer what this is, who it is for, and what the reader can accomplish. Use concrete verbs and everyday language; explain project-specific terms before relying on them.
- Show the product in action near the opening when a visual helps explain it. Prefer an actual screenshot or short demonstration of the main task over decoration. Give each visual descriptive alt text and nearby context; a video also needs a useful still image or text summary.
- Lead with user outcomes and the most important capabilities. Explain implementation details only when they help a reader decide, install, use, or trust the product.
- Make the route to first success easy to find: prerequisites, install or access, a minimal usage example, and what result to expect. Separate alternative install methods and source builds when they would interrupt that route.
- Add links to deeper docs for authors, contributors, API users, architecture, and troubleshooting when those audiences exist. Keep the README useful on its own without duplicating whole manuals.

## Make the visuals

- If the current media is missing, outdated, or fails to show the main task, create new assets from a working product when feasible. Choose the smallest set that makes the product understandable: often a mark, one overview image, and one short task demonstration. Do not add a visual merely to fill a section.
- Match the tool to the content: use VHS for a reproducible terminal session; use the desktop's capture tools for a real GUI; use FFmpeg to trim, resize, or encode a recording. On Omarchy, discover the available `omarchy capture` commands before using them. [Visual assets](references/visual-assets.md) has concrete tool and embedding guidance; read it when creating or replacing media.
- For a project that needs a mark or icon, inspect existing branding first. Create a simple, original SVG that remains legible at small sizes and uses the project's visual language. Keep it as editable vector source. Reuse a valid existing icon when it already serves the README; do not invent a new identity by default.
- Capture real behavior with a clean, representative state. Remove personal data, tokens, notifications, and unrelated windows before capture. Never present a mockup, edited sequence, or staged output as unmodified product behavior. If the product cannot run here, use verified existing media or a labeled example, and explain the limitation.
- Keep repository assets reasonably small and local so the README works from a clone. Prefer a still image for quick scanning, a short optimized GIF when inline motion matters, and a linked video for longer demonstrations. A GIF should not be the only explanation of a feature.

## Edit and verify

Preserve the project's actual voice, language, audience, and branding unless the user asks to change them. Reorganize existing material as needed, keeping accurate details discoverable. Avoid marketing filler, badge clutter, exhaustive command dumps, and claims of safety or ease that the evidence cannot support.

Before finishing, read the rendered order as a newcomer: can someone understand the product and reach a first useful result without knowing the repository? Check local links and asset paths, media playback or previews, SVG rendering, commands and version names, and whether caveats are visible at the point of decision. Report any claim, instruction, or demonstration that could not be verified.
