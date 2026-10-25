from pathlib import Path
import json, subprocess, struct

def read(path):
    try: return Path(path).read_text().strip()
    except (OSError, UnicodeError) as e: return type(e).__name__

out = {'memory': [], 'cpu_idle_parameters': {}, 'gpu_debug': {}, 'pci_links': {}}
for p in sorted(Path('/sys/firmware/dmi/entries').glob('17-*/raw')):
    raw = p.read_bytes(); n = raw[1]; strings = raw[n:].rstrip(b'\x00').split(b'\x00')
    def word(offset): return struct.unpack_from('<H', raw, offset)[0] if n >= offset+2 else None
    def text(offset):
        ix = raw[offset] if n > offset else 0
        return strings[ix-1].decode(errors='replace') if ix and ix <= len(strings) else ''
    out['memory'].append({'locator':text(16),'bank':text(17),'size_field':word(12),'data_width':word(10),'speed_MTs':word(21),'configured_MTs':word(32),'manufacturer':text(23),'part':text(26)})
for p in Path('/sys/module/intel_idle/parameters').glob('*'): out['cpu_idle_parameters'][p.name]=read(p)
for name in ('enable_guc','enable_psr','enable_fbc','enable_dc'):
    out['i915_'+name]=read('/sys/module/i915/parameters/'+name)
for base in Path('/sys/kernel/debug/dri').glob('*'):
    if not base.is_dir(): continue
    for name in ('i915_dmc_info','i915_fbc_status','i915_edp_psr_status','i915_runtime_pm_status','i915_power_domain_info','i915_gem_drop_caches'):
        if name == 'i915_gem_drop_caches': continue
        p=base/name
        if p.exists(): out['gpu_debug'][str(p)]=read(p)
    for p in base.glob('gt*/uc/*_info'): out['gpu_debug'][str(p)]=read(p)
for addr in ('0000:00:1c.0','0000:00:1d.0','0000:01:00.0','0000:02:00.0'):
    proc=subprocess.run(['/usr/bin/lspci','-vv','-s',addr],capture_output=True,text=True)
    out['pci_links'][addr]='\n'.join(l for l in proc.stdout.splitlines() if any(k in l for k in ('LnkCap:','LnkCtl:','LnkSta:','L1SubCap:','L1SubCtl','ASPM','ClockPM','DevCtl2:')))
for p in Path('/sys/class/powercap').glob('intel-rapl:*'):
    if (p/'name').exists(): out[str(p)]={n:read(p/n) for n in ('name','energy_uj','max_energy_range_uj','constraint_0_name','constraint_0_power_limit_uw','constraint_1_name','constraint_1_power_limit_uw')}
print(json.dumps(out,indent=2))
