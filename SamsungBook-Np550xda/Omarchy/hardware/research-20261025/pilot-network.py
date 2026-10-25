"""Follow-up: repeat Ethernet energy measurements, then test Wi-Fi PS latency."""
from pathlib import Path
import json, re, signal, subprocess, time

def stop(*args): raise KeyboardInterrupt
signal.signal(signal.SIGINT,stop); signal.signal(signal.SIGTERM,stop)
roots={n:Path('/sys/class/powercap')/p for n,p in [('package','intel-rapl:0'),('psys','intel-rapl:1')]}
def read_energy(): return {n:int((p/'energy_uj').read_text()) for n,p in roots.items()}
def power(a,b,dt): return {n:((b[n]-a[n])%int((p/'max_energy_range_uj').read_text()))/1e6/dt for n,p in roots.items()}
def cpu():
 vals=list(map(int,Path('/proc/stat').read_text().splitlines()[0].split()[1:9])); return sum(vals), vals[3]+vals[4]
def busy(a,b): return 100*(1-(b[1]-a[1])/(b[0]-a[0]))
result={'protocol':{'ethernet':'6 trials on/auto/auto/on/on/auto, 12s settle and 8s measure; energy exploratory, package versus psys and CPU activity recorded to expose confounding','wifi':'4 trials off/on/on/off; local default gateway only, 30 pings at 200ms; no profile changes; require zero loss and <5ms added average RTT for an interactive-use recommendation'},'ethernet':[],'wifi':[]}
control=Path('/sys/bus/pci/devices/0000:02:00.0/power/control'); old=control.read_text()
try:
 for setting in ('on','auto','auto','on','on','auto'):
  if Path('/sys/class/net/enp2s0/operstate').read_text().strip()!='down': raise RuntimeError('Cable state changed')
  control.write_text(setting); time.sleep(12); c=cpu(); e=read_energy(); t=time.monotonic(); time.sleep(8); elapsed=time.monotonic()-t
  result['ethernet'].append({'setting':setting,'status':control.with_name('runtime_status').read_text().strip(),'cpu_busy_percent':busy(c,cpu()),'watts':power(e,read_energy(),elapsed)})
finally:
 control.write_text(old); result['ethernet_restored']=control.read_text().strip()

def cmd(args): return subprocess.check_output(args,text=True,stderr=subprocess.STDOUT)
previous=cmd(['/usr/bin/iw','dev','wlo1','get','power_save']).strip().split()[-1]
route=json.loads(cmd(['/usr/bin/ip','-j','route','show','default','dev','wlo1']))
gateway=next(r['gateway'] for r in route if 'gateway' in r)
try:
 for setting in ('off','on','on','off'):
  cmd(['/usr/bin/iw','dev','wlo1','set','power_save',setting]); time.sleep(2); c=cpu(); e=read_energy(); t=time.monotonic()
  ping=subprocess.run(['/usr/bin/ping','-n','-q','-c','30','-i','0.2','-W','1',gateway],capture_output=True,text=True)
  elapsed=time.monotonic()-t
  loss=re.search(r'([\d.]+)% packet loss',ping.stdout)
  rtt=re.search(r'= ([\d.]+)/([\d.]+)/([\d.]+)/([\d.]+) ms',ping.stdout)
  result['wifi'].append({'setting':setting,'actual':cmd(['/usr/bin/iw','dev','wlo1','get','power_save']).strip(),'ping_status':ping.returncode,'packet_loss_percent':float(loss[1]) if loss else None,'rtt_min_avg_max_mdev_ms':list(map(float,rtt.groups())) if rtt else None,'cpu_busy_percent':busy(c,cpu()),'watts':power(e,read_energy(),elapsed)})
finally:
 cmd(['/usr/bin/iw','dev','wlo1','set','power_save',previous]); result['wifi_restored']=cmd(['/usr/bin/iw','dev','wlo1','get','power_save']).strip()
print(json.dumps(result,indent=2))
