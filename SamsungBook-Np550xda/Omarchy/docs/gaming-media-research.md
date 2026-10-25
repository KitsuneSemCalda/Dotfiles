# SamsungBook gaming and multimedia: bounded research, 2026-10-25

## Decision and baseline

Apply VA-API decoding in mpv, persist the Intel VPL runtime dependencies used by
existing OBS profiles, and run a synthetic media smoke test during `--hardware`
(and therefore `--all`). Provide an explicit foreground workload launcher using
the existing power-profiles-daemon. Retain the tested Java JACK exception.
These changes do not establish a general FPS increase or better recording quality.

Local identity: NP550XDA-KF2BR, i5-1135G7, four cores/eight threads, Tiger Lake
integrated GPU, 16 GiB installed RAM. Kernel 7.2.8-9-omarchy; Mesa 26.2.5;
PipeWire 1.6.9; WirePlumber 0.5.18; intel-media-driver/vpl-gpu-rt 26.3.5;
libvpl 2.17.0; mpv 0.41.0; OBS 32.2.2. Actual installed hardware takes precedence
over original retail RAM/storage. Samsung's accessible support pages describe
related SKUs, so they are not evidence for undocumented firmware tweaks here.

Research budget: two targeted discovery passes, upstream passages and local
functional tests across audio scheduling, video codecs, playback and power
profiles. Stop when these changes have functional evidence; thermal/FPS,
physical audio latency and prolonged OBS capture remain separate workloads.

## Hypotheses and foundation

- H1: mpv's default software decoding leaves supported Intel decoding unused.
  Accept acceleration only if a synthetic file opens with an explicit hardware
  decoder. Reject any claim of lower CPU/power consumption without measurements.
- H2: installed VPL supports the existing OBS Quick Sync configuration. Accept
  package compatibility after a real synthetic QSV encode and VA-API decode;
  this does not establish that an OBS scene/stream works.
- H3: the native profile-hold API can bound a performance request to a process.
  Require observed performance during the command and restoration afterward.
  A speed benefit remains untested; shared CPU/GPU thermal headroom can make a
  more aggressive CPU policy counterproductive for an integrated GPU game.
- H4: globally smaller audio buffers improve everything. Rejected as a general
  claim: block duration is N / sample_rate; 256/48000 is 5.33 ms, but neither
  physical round-trip latency nor stability follows from that number. Smaller
  buffers shorten scheduling deadlines. Keep the working 48 kHz/default policy.

Audio correctness and stable deadlines take precedence over nominal low
latency. Video API availability, functional encoding, output fidelity and
end-to-end application performance are different measurements.

## Sources and access

All sources accessed 2026-10-25; page update dates unknown unless stated.
ArchWiki direct pages returned Anubis access denial. Only indexed excerpts were
available; these guided discovery, and pivotal behavior was checked upstream.

| Source / institution | Passage actually inspected | Role and limits |
| --- | --- | --- |
| [ArchWiki PipeWire](https://wiki.archlinux.org/title/PipeWire) | Indexed JACK clients / PIPEWIRE_LATENCY | Orientation; not full-page access |
| [ArchWiki troubleshooting](https://wiki.archlinux.org/title/PipeWire/Troubleshooting) | Indexed sample-rate changes, warnings about resampling and latency | Supports retaining defaults; no local benchmark |
| [ArchWiki VA-API](https://wiki.archlinux.org/title/VA-API) | Indexed Intel installation and codec table | Intel media-driver, firmware and VPL discovery |
| [ArchWiki GameMode](https://wiki.archlinux.org/title/GameMode) | Indexed temporary optimizations / configuration | Alternative investigated, not installed |
| [Intel media-driver README](https://github.com/intel/media-driver) | Supported Platforms and Known Issues, HuC item 2 | TGL support; bitrate-control firmware dependency; upstream master, local version recorded above |
| [Intel VPL GPU runtime](https://github.com/intel/vpl-gpu-rt) | README runtime/platform overview | Runtime lineage; local encode is stronger functional evidence |
| [mpv stable manual](https://mpv.io/manual/stable/) | Hardware decoding, auto/vaapi and software fallback | Official behavior; live binary also reports hwdec default no |
| [PipeWire context configuration](https://docs.pipewire.org/page_man_pipewire_conf_5.html) | loop.rt-prio, context property rules | Java client exception; server RT remains enabled |
| [PipeWire JACK configuration](https://docs.pipewire.org/page_man_pipewire-jack_conf_5.html) | client rules, latency and realtime priority | Per-client controls rather than global realtime removal |
| [GameMode upstream](https://github.com/FeralInteractive/gamemode/blob/master/README.md) | README temporary optimization overview | Additional daemon not needed for the selected profile-hold scope |
| Local `/usr/bin/powerprofilesctl` | launch help and HoldProfile/ReleaseProfile implementation | Installed API semantics and signal/exit handling |

## Locally executed evidence

- User confirmed Minecraft sound after the Java JACK rule. The game previously
  completed a world session and saved normally. Java audio threads were TS;
  PipeWire/Pulse remained RR20 and WirePlumber RR1. This does not certify every mod.
- Generated a four-second 1080p30 testsrc2 H.264 file with libx264 ultrafast CRF22.
  mpv auto selected VA-API after failed Vulkan Video and NVIDIA probes. Selected
  `hwdec=vaapi` to avoid irrelevant probes; unsupported content can fall back to
  software. No shader/HDR/upscaling changes are needed for the known SDR monitor.
- `check-samsung-media` encoded 90 synthetic 720p30 frames with h264_qsv CQP24,
  then decoded the resulting file with explicit VA-API and downloaded frames.
  Both commands returned zero. Temporary media is removed automatically.
- `samsung-workload gaming powerprofilesctl get` returned performance; the next
  profile query returned balanced. Unit checks cover AC/battery selection,
  literal arguments and invalid commands. No command is evaluated by a shell.

## Application and limitations

`--hardware --backup` installs mpv, libvpl, vpl-gpu-rt and Intel firmware along
with existing hardware dependencies, copies the settings/helpers, and executes
`check-samsung-media`. It fails if the media smoke test fails. `--all` includes it.
The check does not record the screen or microphone. Existing OBS profiles already
use Quick Sync, 48 kHz, MKV and separate tracks; they were retained.

Use `samsung-workload gaming COMMAND ...` or `samsung-workload content COMMAND ...`
for an explicit foreground process. On battery at launch it runs without a
performance hold. AC state is sampled at startup only; unplugging later does
not release the hold. Do not use a launcher that immediately hands off to an
already-running process: the hold lasts only as long as the wrapped process.
This is an optional performance request, not an automatic FPS optimization.

No GameMode, alternate scheduler/kernel, overclock, realtime-limit removal,
global tiny quantum, forced 192 kHz, speculative GPU environment flags or
speaker EQ was deployed. Each needs a relevant baseline and success criterion.
OBS streaming bitrate control still depends on the previously configured HuC
policy becoming active after reboot. CQP success is not proof of CBR success.

Pending decisive tests: fixed game replay with frame-time percentiles on balanced
versus performance and equal thermal starting state; ten-minute OBS capture while
gaming with encoder/render-lag counters; physical audio loopback plus xrun counts
before adopting lower latency. No capture or prolonged workload was claimed here.
