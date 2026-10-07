# Visual assets for a product README

Use this when the README needs a new icon, screenshot, terminal demo, GIF, or video. Pick media from the product's actual interaction: an app overview, the task a new user cares about, or the result of a command. Keep source recordings or reusable VHS tapes when they make future updates easier.

Before capturing, check what is installed (`command -v omarchy grim slurp vhs ffmpeg ffprobe magick`) and whether the product can be launched in this session. On Omarchy, inspect `omarchy capture --help`; command names and options can change. Prepare a representative product state, select the action worth showing, and identify the output asset the README needs. Use the environment's capture tools directly when possible. If no graphical session or working product is available, use verified existing media or a clearly labeled example and report the gap.

## Capture

- **Desktop app:** On Omarchy, use `omarchy capture screenshot windows save` for a window or `omarchy capture screenshot region save` for a selected area. These print the saved image path and normally use the user's Pictures directory; `OMARCHY_SCREENSHOT_DIR` can direct output to a staging directory. For motion, `omarchy capture screenrecording` selects a region or monitor and `omarchy capture screenrecording --stop-recording` finalizes the MP4 and prints its path. It normally uses the user's Videos directory; `OMARCHY_SCREENRECORD_DIR` can direct output to a staging directory. Create the staging directory first, and confirm the installed script supports these variables before relying on them. Check whether another recording is active before starting or stopping one, since the command may toggle or stop that recording. Avoid desktop or microphone audio unless it serves the demo. Elsewhere, use the desktop's native capture tool. On Wayland, `grim` with `slurp` can save a selected region directly to a chosen file when the Omarchy wrapper is unsuitable.
- **Terminal app:** Write a short VHS `.tape` that runs the real command against safe sample data. Create the destination directory, include `Output docs/media/demo.gif` or `Output docs/media/demo.mp4`, set a readable terminal size, and run `vhs validate demo.tape` before `vhs demo.tape`. Keep the tape when it makes future recapture useful. Check the actual output: a successful recording can still show an error, a private path, or stale behavior. VHS is for terminal sessions, not a substitute for demonstrating a GUI.
- Capture only the window or region needed to understand the action. Hide secrets and personal content before recording; review every frame afterward. If a command changes external state, stage the demo with sample data or an isolated environment appropriate to the project.

## Prepare and choose a format

- Use `ffmpeg` to trim pauses and resize recordings before committing. For example, `ffmpeg -ss 2 -i raw.mp4 -t 12 -vf "fps=24,scale=1280:-2:force_original_aspect_ratio=decrease" -c:v libx264 -crf 26 -preset medium -pix_fmt yuv420p -an demo.mp4`. Adjust the crop, duration, and audio to the content; retain audio only if it helps comprehension and is safe to share.
- For short inline motion, an example GIF conversion is `ffmpeg -i demo.mp4 -filter_complex "[0:v]fps=12,scale=960:-2:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse" -loop 0 demo.gif`. Inspect the result and compare file size with the source. A large GIF can make the repository and README slow; use a poster image linked to the video instead.
- Use a still PNG or WebP for a GUI screenshot. Preserve readable text; avoid resizing until labels become illegible. Use `ffprobe` to inspect video length and dimensions and ordinary file listing to inspect asset sizes. Do not treat encoding completion as proof that the content is correct.
- For video, inspect the beginning, key action, and final state. Extract a representative poster frame with FFmpeg for a linked video; crop or redact only in ways that keep the demonstrated behavior truthful. Preview the final asset at the size it will appear in the README.

## SVG marks and icons

Look for an existing SVG, logo, app icon, color palette, and license before drawing. When a new mark is justified, use a small `viewBox`, simple paths or shapes, and colors with enough contrast on light and dark backgrounds. Avoid embedded raster data, external fonts, scripts, and remote resources. Preview at README size and small icon size; render with `rsvg-convert` or another local renderer when available. An icon may identify the product, but it should not imply a feature or affiliation the project does not have.

## Put media in the README

- Store assets under a stable project path such as `docs/media/`. Use relative links and meaningful filenames. Prefer a short alt description of what the viewer learns, such as `![Catalog with search results for virtual machines](docs/media/catalog.png)`.
- For a GIF, describe the sequence in alt text or adjacent prose. Provide a static frame if motion is distracting or inaccessible.
- For a longer video, link a still image, for example `[![App after a search](docs/media/poster.png)](docs/media/demo.mp4)`, or use a text link to the MP4 or hosted video. GitHub README rendering does not reliably play embedded video across clients. State the action and result near the link so the README remains useful without playback.
- Check the rendered README, every local path, SVG preview, first and last frames, and the key action in the middle. Replace media when the interface or behavior changes materially.
