# Connected peripherals: research and applied adjustments

Investigated 2026-10-25 on the NP550XDA-KF2BR, PipeWire 1.6.9 and the installed
Hyprland Lua configuration. Scope: connected microphone, external display and
its adapter, USB hub, keyboard and mouse. The notebook's internal webcam and
Bluetooth controller were distinguished from external peripherals.

The investigation was bounded to identity/topology, vendor capabilities,
negotiated modes, microphone levels, audio scheduling and existing device
workarounds. Apply only corrections tied to observed behavior. No refresh-rate
overclock, fabricated color calibration, automatic gain/EQ or generic USB
parameter bundle was considered established by this inventory.

## Inventory and hypotheses

| Device / path | Locally observed | Interpretation |
| --- | --- | --- |
| Fifine K688, USB 3142:0068 | MV-SILICON fifine Microphone, snd_usb_audio, 12 Mbit/s, directly on notebook port 3-1 | No external hub shared with this microphone |
| Samsung B2030N via HDMI-to-VGA | User confirmed adapter; HDMI-A-2 exposes RGT 0x1352 0x01010101 | Adapter identity replaces the panel identity |
| Huasheng hub, 214b:7260 | USB 2.0, 480 Mbit/s, keyboard and mouse behind it | Not a USB 3 hub; those HID devices do not need USB 3 bandwidth |
| Dareu EK75, 260d:0045 | Wired mode, multiple HID interfaces, 1 ms interrupt endpoint interval | Existing knob rule covers 0045 and receiver 0042 |
| Generic optical mouse, 18f8:0f97 | Low-speed USB, 10 ms interrupt interval | USB ID alone does not identify an exact commercial model |

Initial hypotheses were that microphone transport/format might be unsuitable,
that monitor identification might be lost in the adapter, and that scheduling
might explain an audio reliability opportunity. The first was not supported by
the level/format inspection; the latter two had direct local evidence.

## Applied: identify the display chain and keep native timing

The [Samsung support page](https://www.samsung.com/br/support/model/LS20PUYKFLZD/)
identifies B2030N. Samsung's user manual, section 6-13, specifies analog RGB
and 1600×900 at 60 Hz as optimum and maximum resolution. The readable
[Samsung-authored manual transcript hosted by Manualzilla](https://manualzilla.com/doc/6809160/samsung-b2030n-user-manual)
was inspected because the official PDF download was inaccessible in the browser
tool. Publication/revision metadata of that transcript is unknown.

The connected adapter's EDID has a valid checksum but describes a digital RGT
device, identifies 1024×768 as preferred, advertises 1080p and HDMI audio, and
contains generic/mismatched physical/color metadata. Those advertised properties
cannot be used as the physical Samsung panel's specifications.

The existing Samsung-description rule therefore did not match the connected
chain. Added a separate rule for the exact observed RGT description in
home/.config/hypr/monitors.lua: 1600×900@60, scale 1, 8-bit, sRGB, VRR off.
The [Hyprland monitor documentation](https://wiki.hypr.land/0.55.0/Configuring/Basics/Monitors/)
supports description selectors and these explicit mode/color fields.

Applied with a backup at
~/.config/hypr/monitors.lua.before-peripherals-20261025, then ran hyprctl reload
and configerrors. Final query: HDMI-A-2, 1600×900, 60.000 Hz, sRGB, XRGB8888,
no configuration errors. The monitor already used that mode before the change;
the correction makes the actual adapter identity persistently match the rule,
rather than claiming an immediate resolution increase.

Limit: this identifies an adapter, not a unique physical display. If another
panel is attached through the same adapter, revisit the 1600×900 rule. No kernel
EDID replacement was installed. The original Samsung rule is retained for a
connection that passes its real EDID through.

DDC probing did not produce a usable external display in this chain. Brightness
or phase changes through ddcutil were not forced. The manual's AUTO control is
available in analog mode: after setting native resolution, pressing the physical
AUTO button can align sampling/position. Coarse/fine adjustment, brightness and
visual confirmation remain physical calibration tasks, not executed tests.
No ICC profile, measured color accuracy or 75 Hz native mode was claimed.

## Microphone: verified levels, preserve the raw source

The source is mono, unmuted, volume 1.00; ALSA capture mixer shows 0 dB. The
PipeWire graph is at 48 kHz with configured quantum 1024. A quantum of 1024/48000
is 21.33 ms of graph scheduling interval; it is not an end-to-end latency test.
No global quantum reduction was applied without xrun and load comparisons.

Local ALSA descriptors expose mono S16_LE and S24_3LE at 44.1/48 kHz; PipeWire
also advertises both formats. A
[FIFINE support article, 2026-04-27](https://help.fifinedesign.com/en/articles/13448495-fixing-fifine-am8-k688-low-volume-after-windows-11-update)
recommends mono 16-bit/48 kHz for a Windows-specific troubleshooting case. This
supports a conservative compatibility choice but does not prove that this
Linux device cannot transport 24-bit samples. Neither a descriptor nor a format
container establishes 24 effective ADC bits. No forced-format rule was added.

With explicit user consent, one 15-second FFmpeg astats measurement processed
the default Fifine source to a null output. No voice file was created. The Pulse
client requested stereo and received duplicate mono channels; the results are
not evidence of a stereo microphone. The stream was 48 kHz/S16_LE.

- Peak: -9.36 dBFS; min/max samples -10956 / 11151, below digital full scale.
- Whole-window RMS: -27.96 dBFS; includes speaking and any pauses.
- No controlled silence interval or calibrated noise/SNR measurement was done.
- The astats noise-floor result was not usable as an acoustic noise measurement.

This sample does not justify raising gain or installing a compressor, gate or
noise suppressor. Gain, hardware knobs and mute were preserved. Ran the existing
select-k688-microphone helper after device discovery to remember its stable
source name as the preferred input. Capture buses were not started or altered.

The [FIFINE product documentation](https://fifinemicrophone.com/products/fifine-amplitank-k688-microphone)
describes onboard monitoring and USB controls. Headphones attached to the mic
can use its direct monitoring path; no host loopback needs to be added for that
purpose. XLR routing and preamp requirements are separate from the USB path
actually tested here.

## Applied: enable the normal realtime audio scheduling mechanism

Observed before the change:

- PipeWire/WirePlumber logs reported missing RTKit service.
- rtkit and realtime-privileges were both absent.
- PipeWire limits had RLIMIT_RTPRIO=0 and RLIMIT_NICE=0.
- Actual data-loop threads used ordinary TS scheduling.

The [PipeWire realtime module documentation](https://docs.pipewire.org/page_module_rt.html)
explains direct realtime-limit support and fallback to the realtime portal or
RTKit. Thus this was an observed scheduling gap, not an inference from warnings
alone. The retrieved documentation is 1.6.10, one patch newer than installed
PipeWire 1.6.9; behavior was verified locally.

Installed official Arch rtkit 0.14-2 and restarted pipewire, pipewire-pulse and
wireplumber. Discovery was asynchronous: an immediate source-selection attempt
found no node; a subsequent query found the microphone and selected it normally.
No physical reconnect was needed.

RTKit activated over D-Bus. Its systemd unit can show disabled while active;
D-Bus activation provides its startup path, so no redundant enable/startup
service was added. Actual post-change thread inspection showed:

| Process | Data thread scheduler | Priority |
| --- | --- | --- |
| pipewire | SCHED_RR | 20 |
| pipewire-pulse | SCHED_RR | 20 |
| wireplumber | SCHED_RR | 1 |

The installer now includes rtkit in --calibrate dependencies, also covered by
--all. Existing RT policy values were not raised. This verifies scheduling
availability, not reduced glitches or latency under a representative heavy load.
A sustained recording/xrun comparison remains unexecuted. The final graph
snapshot reported no node errors, but was idle and is not a stress test.

## Keyboard, mouse and remaining limits

The current wired EK75 ID is covered by the existing hwdb rule suppressing the
faulty knob interface. No new RGB driver, firmware or HID remapping was installed.
Its 1 ms endpoint interval and the mouse's 10 ms interval describe USB polling
requests, not measured switch/sensor-to-screen latency. USB2 hub speed is not a
reason to force a global 1000 Hz mouse parameter or disable all autosuspend.

Archived [technical artifacts](../hardware/peripherals-20261025/) contain adapter
EDID, enumerated microphone formats, graph clock configuration and numerical
microphone statistics only. No recordings, credentials or full application dump
were archived. All linked sources were accessed 2026-10-25; Samsung support and
FIFINE product revision dates were not visible in the inspected text.

Stopping decision: two observed configuration gaps were corrected, microphone
levels checked, and the default input remembered. Remaining decisive checks
require visual OSD calibration, physical reconnect/reboot, or an explicitly
controlled audio workload. No microphone pickup, ADC noise, analog adapter
quality, display gamma or hardware input latency improvement was claimed.

## Installer enforcement

`omarchy.pl --hardware` (included in `--all`) now installs RTKit and enables a
Samsung graphical-session verifier. It checks realtime data-loop threads in
PipeWire, pipewire-pulse and WirePlumber, including the Linux
SCHED_RESET_ON_FORK flag on RTKit-granted scheduling policies. If needed it
restarts the audio services, waits for discovery, and stores the Fifine source
preference. A disconnected microphone is explicitly pending; no recording is
performed. The known monitor mode and closed-lid panel state are checked too.
The first live session verification passed. Eight isolated hardware-policy
regression tests pass, alongside clamshell and device-calibration tests.

## Minecraft regression after enabling RTKit

On 2026-10-25, Dragon Mine Z Kakarot (Forge 1.20.1) exited with code 9 during
startup/world loading. The update-check HTTP timeout was followed by normal
loading and did not establish the cause. No matching kernel OOM, systemd-oomd
kill, or native core dump was recorded. A new launch reproduced the exit.
An isolated tracefs signal_generate trace captured:

```
data-loop.0-533821: sig=9 errno=0 code=128 comm=data-loop.0 pid=533821 grp=1 res=0
```

The game logged `OpenAL initialized on device JACK Default`. Kernel-origin
SIGKILL on that realtime audio thread is consistent with RLIMIT_RTTIME
exhaustion. The trace establishes the signal and target, not the exact kernel
call stack. RTKit activation plausibly exposed this failure path.

The first controlled workaround selected Pulse and disabled OpenAL mixer
realtime scheduling. The game survived and loaded a world, but lost sound:
its bundled OpenAL 1.21.1 could not load libpulse. A standalone device-open test
confirmed this failure, while system OpenAL 1.25.2 successfully opened the same
output. That workaround was withdrawn, preserving its live file as
`~/.config/alsoft.conf.pulse-test-20261025`; no Prism settings were changed.

At the user's request, the final approach targets PipeWire JACK itself.
`home/.config/pipewire/jack.conf.d/60-java-audio.conf` matches process binary
`java`, setting context `loop.rt-prio = 0` and JACK `rt.prio = 0`. The audio
server and other clients keep their realtime policy. `pw-config` successfully
merged both rules. A restarted game is required for runtime validation.
No system realtime timeout limits are raised or disabled.

The official [PipeWire context documentation](https://docs.pipewire.org/page_man_pipewire_conf_5.html)
defines zero loop priority as disabling realtime scheduling. The
[JACK configuration reference](https://docs.pipewire.org/page_man_pipewire-jack_conf_5.html)
documents per-client matching and realtime-priority limits.

Runtime verification after restarting on 2026-10-25: Minecraft PID 564763
logged `OpenAL initialized on device JACK Default` at 15:27:42 and completed
startup. Its two `pw-alsoft` threads and `data-loop.0` were all TS (normal
scheduling), rather than realtime. It remained running beyond the previous
failure point. Hardware and session units both reported active/success.
World-entry and audible playback confirmation are tracked separately from
these process-level checks.
