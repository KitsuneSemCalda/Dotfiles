"""Bounded experiments; restore global knobs even after a failed workload."""
import hashlib, json, multiprocessing as mp, os, signal, statistics, time
from pathlib import Path

OUT = {'protocol': {'hwp': '8 counterbalanced trials; 60 warmup then 300 IO-woken SHA256 bursts, 5ms between requests; pinned worker CPU2; >=10% lower median and no >5% more psys joules/request required for adoption', 'ethernet': 'ABBA, 12s settle then 6s sampling; disconnected only; require suspended state and separated psys power ranges for adoption'}, 'hwp': [], 'ethernet': []}

def stop(signum, frame): raise KeyboardInterrupt
signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGINT, stop)
ENERGY = {name: Path(path) for name,path in [('package','/sys/class/powercap/intel-rapl:0'),('psys','/sys/class/powercap/intel-rapl:1')]}
def energy(): return {n:int((p/'energy_uj').read_text()) for n,p in ENERGY.items()}
def delta(before,after): return {n:((after[n]-before[n])%int((p/'max_energy_range_uj').read_text()))/1e6 for n,p in ENERGY.items()}
def worker(conn):
    os.sched_setaffinity(0, {2})
    data=b'x'*(512*1024)
    while conn.recv_bytes() != b'quit': conn.send_bytes(hashlib.sha256(data).digest())
expected=hashlib.sha256(b'x'*(512*1024)).digest()
hwp=Path('/sys/devices/system/cpu/intel_pstate/hwp_dynamic_boost'); old=hwp.read_text()
ctx=mp.get_context('fork'); parent, child = ctx.Pipe(); proc=ctx.Process(target=worker,args=(child,)); proc.start()
try:
    for setting in (0,1,1,0,1,0,0,1):
        hwp.write_text(str(setting)); time.sleep(.3)
        for _ in range(60):
            time.sleep(.005); parent.send_bytes(b'go'); assert parent.recv_bytes()==expected
        samples=[]; before=energy(); start=time.monotonic()
        for _ in range(300):
            time.sleep(.005); t=time.perf_counter_ns(); parent.send_bytes(b'go'); assert parent.recv_bytes()==expected; samples.append((time.perf_counter_ns()-t)/1000)
        elapsed=time.monotonic()-start; joules=delta(before,energy()); ordered=sorted(samples)
        OUT['hwp'].append({'setting':setting,'median_us':statistics.median(samples),'p95_us':ordered[int(.95*(len(ordered)-1))],'p99_us':ordered[int(.99*(len(ordered)-1))],'seconds':elapsed,'joules':joules})
finally:
    hwp.write_text(old)
    parent.send_bytes(b'quit'); proc.join(3)
    if proc.is_alive(): proc.terminate(); proc.join()
    OUT['hwp_restored']=hwp.read_text().strip()

control=Path('/sys/bus/pci/devices/0000:02:00.0/power/control'); prev=control.read_text()
if Path('/sys/class/net/enp2s0/operstate').read_text().strip() != 'down': raise RuntimeError('Ethernet no longer disconnected')
try:
    for setting in ('on','auto','auto','on'):
        control.write_text(setting); time.sleep(12); before=energy(); start=time.monotonic(); time.sleep(6); elapsed=time.monotonic()-start
        OUT['ethernet'].append({'setting':setting,'runtime_status':control.with_name('runtime_status').read_text().strip(),'watts':{n:j/elapsed for n,j in delta(before,energy()).items()}})
finally:
    control.write_text(prev); OUT['ethernet_restored']=control.read_text().strip()
print(json.dumps(OUT,indent=2))
