// Package hardware observes Linux counters. Missing sensors remain absent, never zero-valued evidence.
package hardware

import (
	"bufio"
	"context"
	"encoding/csv"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"time"

	"inferctl/internal/profile"
)

type CPU struct {
	Architecture   string    `json:"architecture"`
	Model          string    `json:"model"`
	PhysicalCores  int       `json:"physical_cores"`
	Threads        int       `json:"threads"`
	FrequenciesMHz []float64 `json:"frequencies_mhz,omitempty"`
	Governors      []string  `json:"governors,omitempty"`
	BusyTicks      uint64    `json:"busy_ticks"`
	TotalTicks     uint64    `json:"total_ticks"`
	Load           string    `json:"load_average"`
	ThrottleCount  *uint64   `json:"throttle_count,omitempty"`
}
type Memory struct{ Total, Available, WorkingSet, PageCache, SwapTotal, SwapUsed, SwapInPages, SwapOutPages uint64 }
type GPU struct {
	ID          string   `json:"id"`
	Vendor      string   `json:"vendor"`
	Device      string   `json:"device"`
	Integrated  *bool    `json:"integrated,omitempty"`
	VRAMTotal   *uint64  `json:"vram_total_bytes,omitempty"`
	VRAMUsed    *uint64  `json:"vram_used_bytes,omitempty"`
	SharedTotal *uint64  `json:"shared_total_bytes,omitempty"`
	Temperature *float64 `json:"temperature_c,omitempty"`
	Utilization *float64 `json:"utilization_percent,omitempty"`
	Clock       *float64 `json:"clock_mhz,omitempty"`
	Power       *float64 `json:"power_watts,omitempty"`
}
type Disk struct {
	Name, Kind                                                 string
	ReadBytes, WriteBytes, Operations, BusyMS, ReadMS, WriteMS uint64
}
type Snapshot struct {
	SwapDevices  []SwapDevice       `json:"swap_devices,omitempty"`
	ZswapEnabled *bool              `json:"zswap_enabled,omitempty"`
	At           time.Time          `json:"at"`
	CPU          CPU                `json:"cpu"`
	Memory       Memory             `json:"memory"`
	GPUs         []GPU              `json:"gpus"`
	Disks        []Disk             `json:"disks"`
	Mounts       []string           `json:"mounts"`
	Temperatures map[string]float64 `json:"temperatures_c"`
	PSI          map[string]string  `json:"psi"`
	CgroupV2     bool               `json:"cgroup_v2"`
	Warnings     []string           `json:"warnings,omitempty"`
}

func read(p string) string   { b, _ := os.ReadFile(p); return strings.TrimSpace(string(b)) }
func number(s string) uint64 { n, _ := strconv.ParseUint(strings.TrimSpace(s), 10, 64); return n }
func ptrNumber(p string) *uint64 {
	s := read(p)
	if s == "" {
		return nil
	}
	n, e := strconv.ParseUint(s, 10, 64)
	if e != nil {
		return nil
	}
	return &n
}
func scaled(p string, div float64) *float64 {
	s := read(p)
	if s == "" {
		return nil
	}
	n, e := strconv.ParseFloat(s, 64)
	if e != nil {
		return nil
	}
	n /= div
	return &n
}
func glob(p string) []string { v, _ := filepath.Glob(p); return v }
func kv(path string) map[string]uint64 {
	m := map[string]uint64{}
	f, e := os.Open(path)
	if e != nil {
		return m
	}
	defer f.Close()
	s := bufio.NewScanner(f)
	for s.Scan() {
		v := strings.Fields(s.Text())
		if len(v) > 1 {
			m[strings.TrimSuffix(v[0], ":")] = number(v[1])
		}
	}
	return m
}
func SnapshotNow(ctx context.Context) (Snapshot, error) {
	s := Snapshot{At: time.Now().UTC(), Temperatures: map[string]float64{}, PSI: map[string]string{}}
	if read("/proc/stat") == "" {
		return s, fmt.Errorf("Linux /proc unavailable")
	}
	s.CPU.Architecture = runtime.GOARCH
	cores := map[string]bool{}
	pkg, core := "", ""
	governors := map[string]bool{}
	for _, b := range strings.Split(read("/proc/cpuinfo"), "\n\n") {
		for _, l := range strings.Split(b, "\n") {
			k, v, ok := strings.Cut(l, ":")
			if !ok {
				continue
			}
			switch strings.TrimSpace(k) {
			case "model name":
				s.CPU.Model = strings.TrimSpace(v)
			case "physical id":
				pkg = strings.TrimSpace(v)
			case "core id":
				core = strings.TrimSpace(v)
			}
		}
		if core != "" {
			cores[pkg+":"+core] = true
		}
	}
	s.CPU.PhysicalCores = len(cores)
	for _, p := range glob("/sys/devices/system/cpu/cpu[0-9]*") {
		if read(p+"/online") == "0" {
			continue
		}
		s.CPU.Threads++
		if s.CPU.PhysicalCores == 0 {
			packageID := read(p + "/topology/physical_package_id")
			coreID := read(p + "/topology/core_id")
			if packageID != "" && coreID != "" {
				cores[packageID+":"+coreID] = true
			}
		}
		if f := scaled(p+"/cpufreq/scaling_cur_freq", 1000); f != nil {
			s.CPU.FrequenciesMHz = append(s.CPU.FrequenciesMHz, *f)
		}
		if g := read(p + "/cpufreq/scaling_governor"); g != "" {
			governors[g] = true
		}
	}
	if s.CPU.PhysicalCores == 0 {
		s.CPU.PhysicalCores = len(cores)
	}
	for g := range governors {
		s.CPU.Governors = append(s.CPU.Governors, g)
	}
	fields := strings.Fields(strings.Split(read("/proc/stat"), "\n")[0])
	var idle uint64
	for i := 1; i < len(fields) && i <= 8; i++ {
		n := number(fields[i])
		s.CPU.TotalTicks += n
		if i == 4 || i == 5 {
			idle += n
		}
	}
	s.CPU.BusyTicks = s.CPU.TotalTicks - idle
	s.CPU.Load = read("/proc/loadavg")
	// core_throttle_count counts physical core events; take maximum to avoid counting shared files twice.
	for _, p := range glob("/sys/devices/system/cpu/cpu*/thermal_throttle/core_throttle_count") {
		n := ptrNumber(p)
		if n != nil && (s.CPU.ThrottleCount == nil || *n > *s.CPU.ThrottleCount) {
			s.CPU.ThrottleCount = n
		}
	}
	m := kv("/proc/meminfo")
	v := kv("/proc/vmstat")
	s.Memory = Memory{Total: m["MemTotal"] * 1024, Available: m["MemAvailable"] * 1024, PageCache: (m["Cached"] + m["SReclaimable"]) * 1024, SwapTotal: m["SwapTotal"] * 1024, SwapUsed: (m["SwapTotal"] - m["SwapFree"]) * 1024, SwapInPages: v["pswpin"], SwapOutPages: v["pswpout"]}
	// Host working-set approximation excludes reclaimable file cache and buffers; not workload RSS.
	excluded := (m["MemFree"] + m["Buffers"] + m["Cached"] + m["SReclaimable"]) * 1024
	if excluded < s.Memory.Total {
		s.Memory.WorkingSet = s.Memory.Total - excluded
	}
	for _, k := range []string{"cpu", "memory", "io"} {
		if v := read("/proc/pressure/" + k); v != "" {
			s.PSI[k] = v
		}
	}
	s.CgroupV2 = read("/sys/fs/cgroup/cgroup.controllers") != ""
	for _, p := range glob("/sys/class/thermal/thermal_zone*/temp") {
		if t := scaled(p, 1000); t != nil {
			s.Temperatures[read(filepath.Dir(p)+"/type")+"@"+filepath.Base(filepath.Dir(p))] = *t
		}
	}
	for _, p := range glob("/sys/class/hwmon/hwmon*/temp*_input") {
		if t := scaled(p, 1000); t != nil {
			s.Temperatures[read(filepath.Dir(p)+"/name")+"@"+p] = *t
		}
	}
	for _, p := range glob("/sys/class/drm/card[0-9]*") {
		if strings.Contains(filepath.Base(p), "-") {
			continue
		}
		d := p + "/device"
		vendor := read(d + "/vendor")
		if vendor == "" {
			continue
		}
		g := GPU{ID: filepath.Base(p), Device: read(d + "/device"), VRAMTotal: ptrNumber(d + "/mem_info_vram_total"), VRAMUsed: ptrNumber(d + "/mem_info_vram_used"), SharedTotal: ptrNumber(d + "/mem_info_gtt_total")}
		switch vendor {
		case "0x8086":
			g.Vendor = "Intel"
		case "0x1002":
			g.Vendor = "AMD"
		case "0x10de":
			g.Vendor = "NVIDIA"
		default:
			g.Vendor = vendor
		}
		g.Utilization = scaled(d+"/gpu_busy_percent", 1)
		g.Clock = scaled(d+"/gt_cur_freq_mhz", 1)
		for _, h := range glob(d + "/hwmon/hwmon*") {
			g.Temperature = scaled(h+"/temp1_input", 1000)
			g.Power = scaled(h+"/power1_average", 1e6)
		}
		s.GPUs = append(s.GPUs, g)
	}
	// NVIDIA's PCI bus ID is used as a stable GPU identifier. No GPU tooling is required for CPU-only systems.
	if _, e := exec.LookPath("nvidia-smi"); e == nil {
		c, cancel := context.WithTimeout(ctx, time.Second)
		out, e := exec.CommandContext(c, "nvidia-smi", "--query-gpu=pci.bus_id,name,memory.total,memory.used,temperature.gpu,utilization.gpu,clocks.sm,power.draw", "--format=csv,noheader,nounits").Output()
		cancel()
		if e == nil {
			rows, _ := csv.NewReader(strings.NewReader(string(out))).ReadAll()
			filtered := s.GPUs[:0]
			for _, g := range s.GPUs {
				if g.Vendor != "NVIDIA" {
					filtered = append(filtered, g)
				}
			}
			s.GPUs = filtered
			for _, r := range rows {
				if len(r) != 8 {
					continue
				}
				g := GPU{ID: strings.TrimSpace(r[0]), Vendor: "NVIDIA", Device: strings.TrimSpace(r[1])}
				values := make([]*float64, 6)
				for i := 2; i < 8; i++ {
					f, e := strconv.ParseFloat(strings.TrimSpace(r[i]), 64)
					if e == nil {
						values[i-2] = &f
					}
				}
				if values[0] != nil {
					n := uint64(*values[0] * 1048576)
					g.VRAMTotal = &n
				}
				if values[1] != nil {
					n := uint64(*values[1] * 1048576)
					g.VRAMUsed = &n
				}
				g.Temperature = values[2]
				g.Utilization = values[3]
				g.Clock = values[4]
				g.Power = values[5]
				s.GPUs = append(s.GPUs, g)
			}
		} else {
			s.Warnings = append(s.Warnings, "nvidia-smi unavailable: "+e.Error())
		}
	}
	for _, line := range strings.Split(read("/proc/diskstats"), "\n") {
		v := strings.Fields(line)
		if len(v) < 14 {
			continue
		}
		name := v[2]
		if read("/sys/block/"+name+"/dev") == "" || strings.HasPrefix(name, "loop") || strings.HasPrefix(name, "ram") {
			continue
		}
		kind := "SSD/virtual"
		if read("/sys/block/"+name+"/queue/rotational") == "1" {
			kind = "HDD"
		} else if strings.HasPrefix(name, "nvme") {
			kind = "NVMe"
		}
		if zramName(name) {
			kind = "zram"
		}
		s.Disks = append(s.Disks, Disk{Name: name, Kind: kind, ReadBytes: number(v[5]) * 512, WriteBytes: number(v[9]) * 512, Operations: number(v[3]) + number(v[7]), BusyMS: number(v[12]), ReadMS: number(v[6]), WriteMS: number(v[10])})
	}
	devices, swapErr := swapDevices("/proc/swaps", "/sys/block")
	s.SwapDevices = devices
	if swapErr != nil {
		s.Warnings = append(s.Warnings, "swap devices unavailable: "+swapErr.Error())
	}
	switch read("/sys/module/zswap/parameters/enabled") {
	case "Y", "1":
		b := true
		s.ZswapEnabled = &b
	case "N", "0":
		b := false
		s.ZswapEnabled = &b
	}
	s.Mounts = strings.Split(read("/proc/mounts"), "\n")
	return s, nil
}
func (s Snapshot) Identity() string {
	type identity struct {
		Architecture, CPU string
		Threads           int
		RAM               uint64
		GPUs              []string
	}
	v := identity{Architecture: s.CPU.Architecture, CPU: s.CPU.Model, Threads: s.CPU.Threads, RAM: s.Memory.Total}
	for _, g := range s.GPUs {
		v.GPUs = append(v.GPUs, g.ID+g.Vendor+g.Device)
	}
	return profile.Hash(v)[:24]
}
func (s Snapshot) MaxTemp() *float64 {
	var t *float64
	for _, v := range s.Temperatures {
		if t == nil || v > *t {
			x := v
			t = &x
		}
	}
	for _, g := range s.GPUs {
		if g.Temperature != nil && (t == nil || *g.Temperature > *t) {
			t = g.Temperature
		}
	}
	return t
}
func CPUUsage(a, b Snapshot) *float64 {
	if b.CPU.TotalTicks <= a.CPU.TotalTicks || b.CPU.BusyTicks < a.CPU.BusyTicks {
		return nil
	}
	v := 100 * float64(b.CPU.BusyTicks-a.CPU.BusyTicks) / float64(b.CPU.TotalTicks-a.CPU.TotalTicks)
	return &v
}
