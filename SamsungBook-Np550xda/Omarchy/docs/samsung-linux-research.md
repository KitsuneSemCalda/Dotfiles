# Samsung NP550XDA-KF2BR: Linux research and applied adjustments

Investigation: 2026-10-25. Scope: this installed machine, Omarchy kernel
7.2.8-9-omarchy, Intel media driver 26.3.5, power-profiles-daemon 0.30,
thermald 2.5.13. This is a compatibility investigation, not a measured claim of
higher FPS, lower temperatures, or longer battery life.

## Questions and decision criteria

Can documented hardware support fix an observed limitation? Can daily power
use be balanced while retaining performance for heavy work? Apply reversible,
supported changes only; reject generic tuning without a local failure or
representative benchmark. Compare against existing Omarchy behavior first.
Research covered vendor support, CPU specifications, kernel interfaces, media
firmware and power-profile lifecycle. Stop after resolving the two actionable
items; battery runtime, memory topology and storage performance remain outside
this validation.

Initial hypotheses:

- Missing Samsung drivers might explain missing features. Rejected: the stock
  samsung_galaxybook driver is already bound to ACPI SAM0428.
- The installed Intel media driver might be sufficient for low-power encoding
  with bitrate control. Rejected by the local encoder test below.
- A balanced default plus a temporary performance hold can serve both quiet
  desktop use and heavy commands. Lifecycle verified locally; thermal and
  throughput benefits have not been measured.

## Hardware observed locally

| Component | Observation | Limit on the conclusion |
| --- | --- | --- |
| Model | DMI board NP550XDA-KF2BR, product 550XDA | Match the board before applying its workaround |
| BIOS | P23CFB.053.241029.HQ, 2024-10-29 | No claim that this is the latest available BIOS |
| CPU | i5-1135G7, 4 cores / 8 threads, turbo up to 4.2 GHz | Thermal headroom affects sustained speed |
| Memory | Two 8 GiB modules; SMBIOS reports 2667 MT/s configured for both | Channel interleaving not independently verified; see follow-up |
| Graphics | Intel 8086:9a49, i915 | Availability of the xe module is not a reason to switch |
| Network | AX201 / iwlwifi; Realtek 8168 / r8169 | No matching Wi-Fi failure observed in the inspected boot log |
| SSD | Samsung MZVLQ256HAJD-000, 256 GB decimal | A PCI controller label mentioning 980 does not identify the SSD as retail 980 |
| Internal panel | BOE 0x0812, 1920×1080 at about 60 Hz | No measured color profile |
| Battery | 900 / 3780 mAh, 547 cycles, end threshold 80% | Controller estimates, not an independently measured discharge capacity |

Battery health estimate: `900 / 3780 * 100 = 23.81%`. At the nominal
11.4 V, the reported full capacity corresponds to about 10.26 Wh versus
43.09 Wh design. Earlier checked-in inxi output reports 30.7%; differing
readings alone do not establish the rate or cause of deterioration. Software
cannot restore physically lost cell capacity.

The [Samsung support page for this exact SKU](https://www.samsung.com/br/support/model/NP550XDA-KF2BR/)
was accessible, but did not provide a complete technical specification in its
retrieved text. Commercial listings disagree about memory speed, so no memory
speed or upgrade limit is accepted from those listings here.
[Intel's CPU specifications](https://www.intel.com/content/www/us/en/products/sku/208658/intel-core-i51135g7-processor-8m-cache-up-to-4-20-ghz/specifications.html)
confirm 4 cores, 8 threads, 80 GPU execution units, Quick Sync and two memory
channels. Its DDR4-3200 and 64 GB controller capabilities do not establish the
Samsung board's supported memory speed or maximum capacity. CPU Thunderbolt
and HDMI capabilities likewise do not establish the wiring of the laptop ports.

## Applied: balanced defaults, temporary performance

The system previously used performance on AC with no saved Omarchy supply
profiles. Applied through existing Omarchy commands:

```sh
omarchy powerprofiles set battery power-saver
omarchy powerprofiles set ac balanced
```

Omarchy saves each selection under its state directory and applies it at
session initialization and supply changes. No additional power manager or
polling service was added. The existing maintenance implementation uses the
same defaults when explicitly enabled; its timer is not installed on this host.

Before-change values were saved locally to
`~/.local/state/dotfiles/samsung-power-before-20261025.json`.
To return to the former AC behavior: `omarchy powerprofiles set ac performance`.
The battery profile can independently be changed through the same command.

For heavy commands, use the existing temporary hold instead of leaving the
entire session permanently in performance:

```sh
powerprofilesctl launch --profile performance --reason 'Heavy build' make -j4
```

Verified locally: `balanced → performance` inside the launched process,
then `balanced` after it exits. After applying balanced, EPP reads
`balance_performance` and `intel_pstate/no_turbo` remains `0`: turbo was not
disabled. The profile is system-wide while held, not limited to that process.
A concurrent power-saver hold takes priority, and manual changes can cancel
holds, as documented by the
[daemon's HoldProfile API](https://upower.pages.freedesktop.org/power-profiles-daemon/gdbus-org.freedesktop.UPower.PowerProfiles.html).
The [kernel intel_pstate documentation, active HWP mode](https://docs.kernel.org/admin-guide/pm/intel_pstate.html)
explains why powersave does not mean a fixed minimum CPU frequency. No runtime
or power-consumption improvement has been quantified.

## Applied for next boot: Intel HuC firmware

VA-API enumeration succeeded on `/dev/dri/renderD128`, using Intel iHD 26.3.5.
It advertised H.264/HEVC encoding and H.264/HEVC/VP9/AV1 decoding. Enumeration
alone did not prove that a particular rate-control mode worked.

Local discriminating tests used a synthetic 1280×720, 30 FPS test pattern,
90 frames, h264_vaapi and `-low_power 1`:

- Quality control, `-qp 24`: exit 0.
- Bitrate control, `-b:v 4M -maxrate 4M -bufsize 8M`: failed; driver reported
  only CQP available for the selected mode.

The [Intel media driver's Known Issues and Limitations](https://github.com/intel/media-driver#known-issues-and-limitations)
identifies HuC firmware as necessary for low-power bitrate control and documents
`i915 enable_guc=2` for Tiger Lake. This matches the local failure; it is a
supported workaround, not a demonstrated general GPU speed increase.

Applied `/etc/modprobe.d/60-dotfiles-intel-huc.conf` with
`options i915 enable_guc=2`, then successfully rebuilt the Limine UKI using
`limine-mkinitcpio`. The builder reported successful initcpio and UKI generation
and installation to `/boot/EFI/Linux/omarchy_linux-omarchy.efi`.
It also printed missing-firmware warnings for xhci_pci_renesas and qat_6xxx;
neither is the HuC firmware checked for this change. No firmware was downloaded.
The running i915 module was not unloaded. Activation and encoder success are
**pending reboot**. Existing OBS settings were not rewritten.

Reapply or reverse only on the checked model:

```sh
pkexec bash SamsungBook-Np550xda/Omarchy/scripts/enable-intel-huc.sh
pkexec bash SamsungBook-Np550xda/Omarchy/scripts/enable-intel-huc.sh --restore
```

The script refuses an existing conflicting GuC policy and refuses to remove
modified configuration. Both actions rebuild the boot image. After reboot,
repeat the exact failing test:

```sh
ffmpeg -hide_banner -loglevel error \
  -vaapi_device /dev/dri/renderD128 \
  -f lavfi -i testsrc2=size=1280x720:rate=30 -frames:v 90 \
  -vf 'format=nv12,hwupload' -c:v h264_vaapi -low_power 1 \
  -b:v 4M -maxrate 4M -bufsize 8M -f null -
```

Acceptance: exit 0 with frames encoded. If still failing, inspect HuC loading
in the kernel log and firmware authentication state before adding more flags.
A test encode passing does not prove an OBS workload or improved efficiency.

## Existing support retained and alternatives rejected

- Samsung battery extension and firmware attributes are already exposed by the
  in-kernel driver. Battery threshold is already 80%; no duplicate service was
  added. Firmware exposes power_on_lid_open and block_recording, both currently
  0; no platform_profile file was exposed. According to the
  [kernel Samsung driver documentation](https://docs.kernel.org/admin-guide/laptops/samsung-galaxybook.html),
  features are individually probed and vary by model. Do not force old
  samsung-laptop SABI calls or install a duplicate out-of-tree driver.
- thermald is already enabled and active with --adaptive, alongside
  power-profiles-daemon. Intel documents Tiger Lake support in the
  [thermald release history](https://github.com/intel/thermal_daemon/blob/master/README.txt).
  Retained existing limits; no undervolting, MSR writes or raised power caps.
- Zram has higher swap priority than the disk swapfile. Existing memory knobs
  were not retuned without a workload comparison. Hibernation configuration
  was retained.
- No blanket i915 PSR/FBC disable, forced xe driver, Wi-Fi power-saving disable,
  global PCIe ASPM force, USB autosuspend rewrite, or speculative sleep-mode
  switch was justified by the observations.
- SSD supports discard, but `lsblk -D` reports zero discard capacity on the
  encrypted root mapping. fstrim.timer is disabled, and the repository's
  maintenance timer is absent. Simply enabling a timer would not fix the
  root mapping. The [kernel dm-crypt documentation, allow_discards](https://www.kernel.org/doc/html/latest/admin-guide/device-mapper/dm-crypt.html)
  explains both the default block and the exposure of allocation information.
  No encryption or boot-unlock policy was changed. Root-only dry-run and SMART
  inspection were not completed; noninteractive sudo required a password.

## Sources and limits

All links above were accessed 2026-10-25. Samsung's exact-SKU support page has
no visible update date in the retrieved portion; Intel's specification revision
is unknown. Kernel HTML is the current documentation, not a source checkout of
the installed Omarchy kernel. Intel media-driver and thermald READMEs are
current upstream documentation; the thermald release history explicitly
includes 2.5.13. The Samsung
[battery-care page](https://www.samsung.com/br/support/computing/como-cuidar-da-bateria-do-galaxy-book-e-aumentar-sua-vida-util/)
was updated 2026-09-26 and describes battery protection and aging symptoms;
it is general Galaxy Book advice, not a capacity test of this battery.

Locally executed: sysfs/DMI/PCI inventory, service states, profile lifecycle,
VA-API enumeration, synthetic encoder controls and boot-image generation.
Documentary analysis: vendor specifications and driver mechanisms.
Not executed: post-reboot HuC validation, unplugged battery runtime, calibrated
thermal/noise benchmarks and SSD performance tests. A follow-up below verifies
DIMM capacities and configured speeds from SMBIOS.

## Deeper follow-up: firmware, idle states and runtime power

Same host and date, after the initial adjustments and before reboot. The user
requested a deeper search for overlooked capabilities. Research was bounded to
CPU wakeup policy and idle states, Samsung firmware controls, PCIe/runtime PM,
Wi-Fi, memory topology/reclaim, GPU power states, and specialized acceleration.
Two controlled local pilots were used to distinguish useful changes from knobs
that merely exist. These are short, synthetic, exploratory measurements in a
live desktop session, not laboratory battery-runtime or application benchmarks.

The [research artifacts](../hardware/research-20261025/) contain the read-only
scan, exact successful pilot procedures and JSON results. The scan omits serial
numbers; its archived output removes redundant debugfs aliases and the long
power-domain dump. The pilot scripts temporarily write sysfs and restore original
values in finally blocks. They are manual research procedures, not startup
services. One initial pilot launch failed because Python 3.14 defaults to
forkserver; it was corrected to an explicit fork context before any successful
measurements. That failed attempt supplies no performance evidence.

### Confirmed hardware details and misleading apparent opportunities

| Candidate | Local evidence | Decision |
| --- | --- | --- |
| Faster RAM / channel fixes | SMBIOS type 17 has two 8192 MiB entries; one reports 2667 MT/s capability, the other 3200; both configured at 2667 | Mixed module capabilities are real. No BIOS speed unlock or channel change demonstrated |
| Deeper CPU idle | C3_ACPI has ACPI FFH MWAIT hint 0x60, not an ordinary inference from the label C3 | No override of the firmware idle table |
| NVMe ASPM | SSD and upstream port both have L1, L1.1 and L1.2 enabled | Global ASPM forcing would not unlock those states |
| Ethernet ASPM | L1 disabled on Realtek path | Driver source contains explicit safety disables; retain these masks |
| GPU power firmware | DMC 2.12 loaded; HuC and GuC currently disabled; all relevant i915 parameters -1 (automatic) | Confirms pending HuC change; do not treat -1 as every feature being disabled |
| GPU FBC | Debugfs reports internal plane not visible | Expected with internal panel disabled; no case for forcing FBC on HDMI |
| CPU power limits | Package long-term 20 W, short-term 45 W at scan time; thermal throttle counters zero | No evidence justifying higher limits |
| Memory reclaim | Multi-Gen LRU enabled at 0x0007 | All documented main components already active |
| Huge pages | THP always; defrag madvise | Already enabled; changing it needs a workload-specific memory/latency comparison |
| Zram | zstd selected; essentially unused during scan | No live algorithm reset or compression tuning from an idle sample |

SMBIOS reports firmware configuration, not an electrical verification of channel
interleaving. A 3200-rated module alongside a 2667-rated module does not prove
that replacing either would make this board run faster.

The [Linux v7.2 intel_idle implementation](https://raw.githubusercontent.com/torvalds/linux/v7.2/drivers/idle/intel_idle.c)
constructs Cn_ACPI labels from ACPI table position, and independently preserves
the MWAIT hint. Its CPU model table has no Tiger Lake-specific native entry.
That explains why an ACPI label alone cannot establish missing deep idle
support. It does not measure package C10 residency on this host.

The [v7.2 r8169 implementation](https://raw.githubusercontent.com/torvalds/linux/v7.2/drivers/net/ethernet/realtek/r8169_main.c)
contains L1 safety handling and separate runtime suspend/resume callbacks.
Runtime idle schedules suspension after ten seconds without carrier. Allowing
runtime PM is distinct from overriding the driver's ASPM exclusions.
The [runtime PM documentation, section 5](https://docs.kernel.org/power/runtime_pm.html)
explains that power/control=on prevents driver-managed runtime suspension,
whereas auto permits it.

The [Multi-Gen LRU ABI](https://docs.kernel.org/admin-guide/mm/multigen_lru.html)
documents 0x0007 as the three components enabled. Its min_ttl_ms protection is
currently zero; raising it trades reclaim for earlier OOM kills, so it was not
added as a generic responsiveness fix. The
[THP documentation](https://docs.kernel.org/admin-guide/mm/transhuge.html)
describes both TLB benefits and memory/latency costs. These features are already
present, not undiscovered switches that automatically improve every workload.

### CPU I/O wake boost: tested, rejected for deployment

Hypothesis: hwp_dynamic_boost=1 improves response to an I/O-woken compute burst.
Mechanism is documented in the
[intel_pstate HWP dynamic boost ABI](https://docs.kernel.org/admin-guide/pm/intel_pstate.html):
it temporarily raises the minimum performance request for tasks waking from I/O.
It does not directly increase the maximum turbo ratio.

Protocol: eight counterbalanced trials, values 0/1/1/0/1/0/0/1; one worker pinned
to CPU2, pipe wakeups separated by 5 ms, SHA256 of a fixed 512 KiB buffer, verified
digest, 60 warmups then 300 measured wakeups per trial. Acceptance was defined
before the successful run: at least 10% lower median latency without over 5%
higher psys energy per request. Energy came from RAPL package and psys counters,
with counter wrap handling; psys is hardware telemetry, not a wall meter.

| Setting | Trial median latencies, microseconds | Median of trial medians |
| --- | --- | --- |
| 0 | 1229.69, 1286.63, 1287.08, 1271.92 | 1279.27 us |
| 1 | 1294.06, 1264.68, 1279.63, 1251.32 | 1272.16 us |

The median-of-medians difference is about 0.56%, with overlapping trial results.
It fails the predefined threshold. No persistent boost change was applied;
original value 0 was restored. This does not rule out a benefit in a different
workload or power profile, but it rejects deploying it from this experiment.

### Ethernet runtime PM and Wi-Fi: follow-up measurements

Initial ABBA Ethernet test (12 s settle plus 6 s samples) transitioned correctly
between active with on and suspended with auto. Psys power was 14.63/11.50 W for
on and 11.07/9.97 W for auto, but package power also changed substantially. That
confound prevents attributing the entire difference to the Ethernet controller.
A second counterbalanced run records CPU activity and both energy domains.

Wi-Fi power saving is explicitly disabled by the installed Omarchy NetworkManager
configuration; this is a distribution policy, not absent AX201 capability.
The [NetworkManager wireless settings](https://www.networkmanager.dev/docs/api/latest/settings-802-11-wireless.html)
identify powersave=2 as disabled and 3 as enabled. The
[Linux wireless power-save mechanism](https://wireless.docs.kernel.org/en/latest/en/users/documentation/dynamic-power-save.html)
explains why idle power and wakeup latency must be compared together. The pilot
uses only the local router and restores the original iw state; no connection
profile, SSID, credentials or access-point configuration is changed.

### Follow-up results and applied Ethernet pilot

The six Ethernet trials returned the following values. CPU activity is included
because the desktop was in use; psys minus package is a diagnostic residual,
not a calibrated measurement of Ethernet power alone.

| Policy | Status | CPU busy | Package W | Psys W | Psys − package W |
| --- | --- | --- | --- | --- | --- |
| on | active | 17.04% | 8.926 | 18.156 | 9.230 |
| auto | suspended | 13.17% | 5.123 | 12.545 | 7.422 |
| auto | suspended | 11.18% | 4.419 | 11.525 | 7.106 |
| on | active | 11.42% | 5.329 | 13.569 | 8.239 |
| on | active | 12.25% | 5.096 | 12.749 | 7.654 |
| auto | suspended | 10.68% | 4.294 | 11.316 | 7.021 |

The predefined state/range checks passed: all auto samples suspended; all on
samples active; observed psys ranges did not overlap. CPU activity varied, so
the median psys difference of 2.04 W is **not** accepted as an isolated Ethernet
saving. Both driver behavior and the direction across repetitions support a
bounded runtime-PM pilot; the exact battery-runtime benefit remains unknown.

Applied a device-specific udev rule matching Realtek 10ec:8168, Samsung
144d:c195 and driver r8169, permitting power/control=auto on add/bind. This uses
the normal driver callback and does not write link registers or enable ASPM.
The rule passed udevadm verify. Apply/reverse using:

```sh
pkexec bash SamsungBook-Np550xda/Omarchy/scripts/enable-samsung-ethernet-pm.sh
pkexec bash SamsungBook-Np550xda/Omarchy/scripts/enable-samsung-ethernet-pm.sh --restore
```

The script refuses the wrong board, mismatched adapter, conflicting rule or
removal of a modified rule. Restore removes its managed rule and returns the
observed original runtime policy on. The scripts are now integrated into `omarchy.pl --hardware`, also included
by `--all`. Plain installation without either flag does not apply these root
operations. The boot and graphical-session services verify the applied policy;
HuC remains pending until reboot and a successful runtime encode test.

Validation still needed: physically connect Ethernet after runtime suspension,
verify link/DHCP/data transfer, then unplug and verify suspension again; repeat
after suspend/resume and reboot. If link detection or throughput regresses,
restore the original policy using the command above. No wired-throughput or
physical cable test was performed in this session.

Wi-Fi results, four windows of 30 pings to the local router:

| Power save | Packet loss | Mean RTT ms | Max RTT ms |
| --- | --- | --- | --- |
| off | 0% | 7.957 | 202.411 |
| on | 0% | 2.573 | 16.382 |
| on | 0% | 2.230 | 3.016 |
| off | 0% | 1.422 | 6.740 |

The first off window had a large outlier. There is no basis to claim that power
saving improved latency, and its energy contribution was not isolated from
varying package activity. No packet loss or reproducible severe latency penalty
was observed, but throughput, roaming, longer inactivity and suspend/resume
were not tested. Wi-Fi was restored to power save off; no persistent change.
It remains a candidate for a future battery-specific pilot, not a proven
optimization of this installation.

### Specialized accelerator does not imply general acceleration

The PCI GNA function exists and no driver was bound in the PCI inventory.
[Intel's accelerator overview](https://www.intel.com/content/www/us/en/developer/articles/technical/machine-learning-hw-accelerators-web-platform.html)
describes GNA for continuous speech/noise workloads and distinguishes it from
CPU VNNI and GPU processing. Intel's
[OpenVINO 2023.1 release notes](https://www.intel.cn/content/www/cn/zh/developer/articles/release-notes/openvino/2023-1.html)
announced discontinuation of the GNA plugin with 2024.0. Neither an old kernel
module nor a retired plugin was installed as a generic LLM accelerator.

The Samsung driver also probes each optional firmware feature before exposing
it; its [v7.2 platform profile initialization](https://raw.githubusercontent.com/torvalds/linux/v7.2/drivers/platform/x86/samsung-galaxybook.c)
returns unsupported when the performance-mode query fails. With battery and
privacy attributes exposed but no platform profile, arbitrary SCAI writes would
be an unsupported experiment, not unlocking a documented fan control.

All follow-up sources accessed 2026-10-25. Upstream kernel code is pinned to
v7.2; equivalence to every Omarchy patch is not assumed. Live sysfs/debugfs and
pilot results are the evidence for this machine. General documentation is
mechanistic evidence, not proof of a local performance improvement.

Final post-apply check: Ethernet runtime policy auto, runtime_status suspended,
and suspended-time counter advancing. Wi-Fi power save off, active CPU profile
balanced, HWP dynamic boost 0. Hyprland configerrors was empty. The inspected
five-minute kernel log contained link-down notices after the deliberate PM
transitions and no matching PCIe/AER error. These checks do not substitute for
the physical wired-link validation listed above.

Stopping decision: this pass established one additional driver-supported,
reversible pilot and rejected automatic deployment of the CPU and Wi-Fi knobs.
Further confidence now depends on a cable/reboot check or controlled application
and battery workloads, rather than collecting more undocumented register writes.
